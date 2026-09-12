import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  late HttpServer server;
  late LanSyncClient client;
  late LanSyncConfig config;
  const canonical = 'CANONICAL-RECEIPT';
  const product = Product(
    id: 'local-product', nameZh: '本机商品', nameEn: 'Local product',
    sku: 'LOCAL-1', barcode: 'LOCAL-1', priceCents: 100, costCents: 40, stock: 10,
  );
  const otherProduct = Product(
    id: 'other-product', nameZh: '电脑商品', nameEn: 'Desktop product',
    sku: 'OTHER-1', barcode: 'OTHER-1', priceCents: 100, costCents: 40, stock: 7,
  );

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-receipt-stock-');
    database = AppDatabase.forTesting('${temp.path}/pos.db');
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
    await repo.upsertProduct(otherProduct);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'receipts': [
          for (final sale in body['sales'] as List)
            {'client_sale_id': sale['client_sale_id'], 'receipt_no': canonical},
        ],
      }));
      await request.response.close();
    });
    client = LanSyncClient(repo);
    config = LanSyncConfig(baseUrl: 'http://127.0.0.1:${server.port}');
    await client.saveConfig(config);
  });

  tearDown(() async {
    await server.close(force: true);
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<SaleRecord> sell() => repo.createSale(
    cart: CartState(items: [CartItem(product: product, qty: 2)]),
    paymentMethod: 'CASH', paidCents: 200, cashier: 'staff',
  );

  test('canonical receipt rename moves stock references before old number is reused', () async {
    final sale = await sell();
    final db = await database.db;
    await client.pushSales(config);
    final moves = await db.query('stock_moves', where: "reason='sale'");
    expect(moves.single['notes'], canonical);
    expect((await repo.salesAll()).single.receiptNo, canonical);

    // Reproduce a Desktop sale pulled into the now-free original receipt
    // number. It sold another product and has no local stock deduction rows.
    final uploaded = (await db.query('sales')).single;
    await db.insert('sales', {
      ...uploaded,
      'id': 'desktop-sale',
      'receipt_no': sale.receiptNo,
      'subtotal_cents': 300,
      'total_cents': 300,
      'paid_cents': 300,
      'lines_json': jsonEncode([
        {'productId': otherProduct.id, 'qty': 3, 'unitPriceCents': 100},
      ]),
    });
    await repo.voidSale('desktop-sale', 'cancel Desktop sale');
    expect((await repo.getProduct(product.id))!.stock, 8);
    expect((await repo.getProduct(otherProduct.id))!.stock, 10);
    await repo.voidSale(sale.id, 'cancel own sale');
    await repo.voidSale(sale.id, 'retry');
    expect((await repo.getProduct(product.id))!.stock, 10);
  });

  test('retrying an acknowledged upload keeps one stock reference', () async {
    await sell();
    final db = await database.db;
    final operation = (await db.query('sync_outbox')).single;
    await client.pushSales(config);
    // Simulate restart with an outbox operation retained after an ACK.
    await db.insert('sync_outbox', operation);
    await client.pushSales(config);
    final moves = await db.query('stock_moves', where: "reason='sale'");
    expect(moves, hasLength(1));
    expect(moves.single['notes'], canonical);
    expect((await repo.getProduct(product.id))!.stock, 8);
    expect(await db.query('sync_outbox'), isEmpty);
  });
}
