import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

void main() {
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  late HttpServer server;
  late LanSyncClient client;
  late LanSyncConfig config;
  late List<int> uploadedStates;
  late List<String> operationOrder;
  var blockActiveSales = false;
  var loseFirstAck = false;
  const product = Product(id: 'p1', nameZh: '商品', nameEn: 'Product',
      sku: 'P1', barcode: 'P1', priceCents: 100, stock: 10);

  setUp(() async {
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('offline-cancel-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
    uploadedStates = [];
    operationOrder = [];
    blockActiveSales = false;
    loseFirstAck = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/sales') {
        final sales = body['sales'] as List;
        final sale = sales.single as Map;
        uploadedStates.add(sale['voided'] as int);
        operationOrder.add('sale_upload');
        if (blockActiveSales && sale['voided'] != 1) {
          request.response.statusCode = 409;
          request.response.write(jsonEncode({'ok': false, 'error': '库存不足'}));
        } else {
          final lost = loseFirstAck;
          loseFirstAck = false;
          request.response.write(jsonEncode({'ok': true, 'receipts': lost ? [] : [
            {'client_sale_id': sale['client_sale_id'], 'receipt_no': sale['receipt_no']},
          ]}));
        }
      } else {
        final ops = body['operations'] as List;
        operationOrder.add((ops.single as Map)['kind'] as String);
        request.response.write(jsonEncode({'ok': true,
          'acknowledged': ops.map((op) => (op as Map)['id']).toList()}));
      }
      await request.response.close();
    });
    client = LanSyncClient(repo);
    config = LanSyncConfig(baseUrl: 'http://127.0.0.1:${server.port}');
    await client.saveConfig(config);
  });
  tearDown(() async {
    await server.close(force: true);
    await database.close();
    await dir.delete(recursive: true);
  });
  Future<SaleRecord> sell() => repo.createSale(
      cart: CartState(items: [CartItem(product: product, qty: 2)]),
      paymentMethod: 'CASH', paidCents: 200, cashier: 'staff');

  test('cancelled offline sale drains despite zero host stock with neutral edits between', () async {
    final sale = await sell();
    await repo.upsertCustomer(const Customer(id: 'c1', name: 'Customer'));
    await repo.voidSale(sale.id, 'cancel offline');
    await repo.upsertSupplier(const Supplier(id: 's1', name: 'Next operation'));
    blockActiveSales = true;
    await client.pushSales(config);
    expect(uploadedStates, [1]);
    expect(operationOrder, ['sale_upload', 'customer_upsert', 'sale_void', 'supplier_upsert']);
    expect(await (await database.db).query('sync_outbox'), isEmpty);
    expect((await repo.getProduct('p1'))!.stock, 10);
  });

  test('lost cancellation ACK preserves queue and retry sends cancelled state again', () async {
    final sale = await sell();
    await repo.voidSale(sale.id, 'cancel offline');
    loseFirstAck = true;
    blockActiveSales = true;
    await expectLater(client.pushSales(config), throwsStateError);
    expect(await (await database.db).query('sync_outbox'), hasLength(2));
    await client.pushSales(config);
    expect(uploadedStates, [1, 1]);
    expect(await (await database.db).query('sync_outbox'), isEmpty);
    expect((await repo.getProduct('p1'))!.stock, 10);
  });

  test('intervening stocktake retains original sale and void operation order', () async {
    final sale = await sell();
    await repo.adjustStock(productId: 'p1', newStock: 9, operator: 'admin');
    await repo.voidSale(sale.id, 'cancel after stocktake');
    await client.pushSales(config);
    expect(uploadedStates, [0]);
    expect(operationOrder, ['sale_upload', 'stocktake', 'sale_void']);
    expect((await repo.getProduct('p1'))!.stock, 11);
  });

  test('an active sale still reaches host inventory validation unchanged', () async {
    await sell();
    blockActiveSales = true;
    await expectLater(client.pushSales(config), throwsStateError);
    expect(uploadedStates, [0]);
    expect(await (await database.db).query('sync_outbox'), hasLength(1));
  });
}
