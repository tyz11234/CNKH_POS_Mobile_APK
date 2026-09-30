import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

http.Response _json(Map<String, Object?> value) => http.Response(
      jsonEncode(value),
      HttpStatus.ok,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unpaired purchase reaches first-pair Outbox before catalog replacement',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-first-pair-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    var purchasePosts = 0;
    var catalogReads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 0,
          'stock_moves_cursor': 1,
          'stock_policy': 'desktop',
          'capabilities': ['mutations_v1', 'stock_moves_v1'],
        });
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/mutations') {
        purchasePosts++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final operation = (body['operations'] as List).single as Map;
        expect(operation['kind'], 'purchase');
        final payload = operation['payload'] as Map;
        final line = (payload['lines'] as List).single as Map;
        expect(line['productId'], 'phone-p1');
        expect(line['productSku'], 'SKU-1');
        expect(line['productBarcode'], '10001');
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
        catalogReads++;
        return _json({
          'ok': true,
          'cursor': 0,
          // Desktop stock 10 + this one confirmed +5 purchase.
          'items': [
            {
              'pc_id': 'desktop-p1',
              'name_zh': '商品',
              'name_en': 'Product',
              'sku': 'SKU-1',
              'barcode': '10001',
              'price_cents': 500,
              'cost_cents': 250,
              'stock': 15,
              'unit': 'pcs',
              'category': '',
              'is_deleted': 0,
              'reorder_level': 0,
              'has_image': false,
            },
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/stock-moves') {
        return _json({'ok': true, 'items': [], 'cursor': 1});
      }
      if (request.method == 'GET' &&
          const ['/api/v1/customers', '/api/v1/suppliers', '/api/v1/categories']
              .contains(request.url.path)) {
        return _json({'ok': true, 'cursor': 0, 'items': []});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/sales') {
        return _json({'ok': true, 'cursor': 0, 'items': []});
      }
      return http.Response('not found', 404);
    });

    try {
      await repo.upsertProduct(const Product(
        id: 'phone-p1',
        nameZh: '商品',
        nameEn: 'Product',
        sku: 'SKU-1',
        barcode: '10001',
        priceCents: 500,
        costCents: 200,
        stock: 10,
      ));
      await (await database.db).delete('sync_outbox');
      await repo.createPurchase(
        supplierId: 'phone-s1',
        supplierName: 'Supplier',
        lines: const [
          {'productId': 'phone-p1', 'qty': 5, 'unitCostCents': 250},
        ],
        totalCents: 1250,
        operator: 'admin',
      );
      final db = await database.db;
      expect(await db.query('sync_outbox'), hasLength(1));

      final sync = LanSyncClient(repo, database: database, httpClient: client);
      const config = LanSyncConfig(
        baseUrl: 'http://127.0.0.1:8787',
        token: 'token',
      );
      await sync.synchronize(config);
      await sync.synchronize(config);

      expect(purchasePosts, 1);
      expect(catalogReads, greaterThanOrEqualTo(1));
      expect((await repo.getProduct('phone-p1'))!.stock, 15);
      expect(await db.query('sync_outbox'), isEmpty);
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('failed first-pair purchase remains durable and retries once', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-pair-retry-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    var fail = true;
    var purchasePosts = 0;
    var catalogReads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 0,
          'stock_policy': 'desktop',
          'capabilities': ['mutations_v1'],
        });
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/mutations') {
        purchasePosts++;
        final operation = ((jsonDecode(request.body) as Map)['operations']
            as List).single as Map;
        if (fail) {
          return _json({
            'ok': false,
            'acknowledged': [],
            'error': 'Desktop unavailable',
          });
        }
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
        catalogReads++;
        return _json({'ok': true, 'cursor': 0, 'items': []});
      }
      if (request.method == 'GET' &&
          const ['/api/v1/customers', '/api/v1/suppliers', '/api/v1/categories']
              .contains(request.url.path)) {
        return _json({'ok': true, 'cursor': 0, 'items': []});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/sales') {
        return _json({'ok': true, 'cursor': 0, 'items': []});
      }
      return http.Response('not found', 404);
    });

    try {
      await repo.upsertProduct(const Product(
        id: 'p1', nameZh: '商品', nameEn: 'Product', sku: 'S1', barcode: 'B1',
        priceCents: 500, costCents: 200, stock: 10,
      ));
      await (await database.db).delete('sync_outbox');
      await repo.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        lines: const [{'productId': 'p1', 'qty': 1, 'unitCostCents': 250}],
        totalCents: 250,
        operator: 'admin',
      );
      final db = await database.db;
      final before = (await db.query('sync_outbox')).single;
      final sync = LanSyncClient(repo, database: database, httpClient: client);
      const config = LanSyncConfig(baseUrl: 'http://127.0.0.1:8787', token: 't');

      await expectLater(sync.synchronize(config), throwsStateError);
      final failed = (await db.query('sync_outbox')).single;
      expect(failed['id'], before['id']);
      expect(failed['last_error'], contains('Desktop unavailable'));
      expect(catalogReads, 0);

      fail = false;
      await sync.synchronize(config);
      expect(purchasePosts, 2);
      expect(catalogReads, 1);
      expect(await db.query('sync_outbox'), isEmpty);
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
