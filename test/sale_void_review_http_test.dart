import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sale void review survives restart, safe work advances, and retry keeps ID',
    () async {
      final dir = await Directory.systemTemp.createTemp('cnkh-sale-void-http-');
      var database = AppDatabase.forTesting(
        '${dir.path}/phone.db',
        seed: false,
      );
      var repo = PosRepository(database: database);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var rejectSaleVoid = true;
      final mutationRequests = <Map<String, Object?>>[];
      var appliedSaleVoids = 0;
      final serving = server.forEach((request) async {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (a, b) => a..addAll(b),
        );
        final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        late Map<String, Object?> response;
        if (request.uri.path == '/api/v1/sales') {
          final sales = body['sales'] as List;
          response = {
            'ok': true,
            'receipts': [
              for (final raw in sales)
                {
                  'client_sale_id': (raw as Map)['client_sale_id'],
                  'receipt_no': raw['receipt_no'],
                },
            ],
          };
        } else if (request.uri.path == '/api/v1/mutations') {
          final operation = Map<String, Object?>.from(
            (body['operations'] as List).single as Map,
          );
          mutationRequests.add(operation);
          if (operation['kind'] == 'sale_void' && rejectSaleVoid) {
            response = {
              'ok': false,
              'acknowledged': <String>[],
              'error': '税务提交处理中或结果未知，请先核对 MyInvois',
              'rejected_operation': {
                'id': operation['id'],
                'kind': 'sale_void',
                'code': 'sale_void_requires_review',
              },
            };
          } else {
            if (operation['kind'] == 'sale_void') appliedSaleVoids++;
            response = {
              'ok': true,
              'acknowledged': [operation['id']],
            };
          }
        } else {
          response = {'ok': true, 'items': [], 'receipts': []};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });

      try {
        final product = const Product(
          id: 'p1',
          sku: 'P1',
          barcode: '10001',
          nameZh: '商品',
          nameEn: 'Product',
          priceCents: 100,
          costCents: 50,
          stock: 10,
        );
        await repo.upsertProduct(product);
        final sale = await repo.createSale(
          cart: CartState(items: [CartItem(product: product)]),
          paymentMethod: 'CASH',
          paidCents: 100,
          cashier: 'admin',
        );
        await repo.voidSale(sale.id, 'offline cancel');
        final db = await database.db;
        final saleVoid = (await db.query(
          'sync_outbox',
          where: "kind='sale_void'",
        )).single;
        await queueMutation(db, 'customer_upsert', 'later-customer', {
          'row': {'id': 'later-customer', 'name': 'Later'},
        });
        await queueMutation(db, 'stocktake', 'p1', {
          'product_id': 'p1',
          'change': 1,
        });

        final cfg = LanSyncConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          token: 'test',
        );
        // Flutter's default HttpOverrides intentionally rejects network I/O in
        // tests. Use a zone-local real HttpClient so this exercises loopback HTTP.
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        final client = IOClient(HttpClient());
        HttpOverrides.global = previousOverrides;
        try {
          final firstClient = LanSyncClient(repo, httpClient: client);
          final firstResult = await firstClient.pushSales(cfg);
          expect(firstResult, contains('销售作废待核对'));
          final retained = (await db.query(
            'sync_outbox',
            where: "kind='sale_void'",
          )).single;
          expect(retained['id'], saleVoid['id']);
          expect(retained['delivery_state'], 'needs_review');
          expect(
            await db.query('sync_outbox', where: "kind='customer_upsert'"),
            isEmpty,
          );
          expect(
            await db.query('sync_outbox', where: "kind='stocktake'"),
            hasLength(1),
          );
          expect(mutationRequests.map((op) => op['kind']), [
            'product_upsert',
            'sale_void',
            'customer_upsert',
          ]);
          expect((await repo.getProduct('p1'))!.stock, 10);

          await database.close();
          database = AppDatabase.forTesting(
            '${dir.path}/phone.db',
            seed: false,
          );
          repo = PosRepository(database: database);
          final restartedDb = await database.db;
          final afterRestart = (await restartedDb.query(
            'sync_outbox',
            where: "kind='sale_void'",
          )).single;
          expect(afterRestart['id'], saleVoid['id']);
          expect(afterRestart['delivery_state'], 'needs_review');
          await LanSyncClient(repo, httpClient: client).pushSales(cfg);
          expect(
            mutationRequests.where((op) => op['kind'] == 'sale_void'),
            hasLength(1),
          );

          rejectSaleVoid = false;
          await requeueSaleVoidAfterReview(
            restartedDb,
            saleVoid['id'] as String,
          );
          await LanSyncClient(repo, httpClient: client).pushSales(cfg);
          expect(
            mutationRequests
                .where((op) => op['kind'] == 'sale_void')
                .map((op) => op['id']),
            [saleVoid['id'], saleVoid['id']],
          );
          expect(appliedSaleVoids, 1);
          expect(await restartedDb.query('sync_outbox'), isEmpty);
          expect((await repo.getProduct('p1'))!.stock, 10);
        } finally {
          client.close();
        }
      } finally {
        await server.close(force: true);
        await serving;
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
