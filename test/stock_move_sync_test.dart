import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

http.Response _json(Map<String, Object?> value) => http.Response(
      jsonEncode(value),
      HttpStatus.ok,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Desktop sale then void with net zero stock blocks local purchase reverse',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-stock-events-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    String? mobilePurchaseId;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 3,
          'stock_moves_cursor': 3,
          'stock_policy': 'desktop',
          'capabilities': ['mutations_v1', 'stock_moves_v1'],
        });
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/mutations') {
        final operation = ((jsonDecode(request.body) as Map)['operations']
            as List).single as Map;
        mobilePurchaseId =
            ((operation['payload'] as Map)['id'] ?? operation['entity_id'])
                ?.toString();
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
        return _json({
          'ok': true,
          'cursor': 3,
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
        final ownPurchase = mobilePurchaseId;
        expect(ownPurchase, isNotNull);
        return _json({
          'ok': true,
          'cursor': 3,
          'items': [
            {
              'cursor': 1,
              'id': 'remote-mobile-purchase',
              'product_id': 'desktop-p1',
              'change': 5.0,
              'reason': 'purchase',
              'notes': 'PO-MOBILE-1',
              'created_at': '2026-09-27T08:00:00Z',
              'source_id': ownPurchase,
            },
            {
              'cursor': 2,
              'id': 'desktop-sale',
              'product_id': 'desktop-p1',
              'change': -4.0,
              'reason': 'sale',
              'notes': 'PC-SALE-1',
              'created_at': '2026-09-27T08:01:00Z',
              'source_id': 'desktop-sale-id',
            },
            {
              'cursor': 3,
              'id': 'desktop-sale-void',
              'product_id': 'desktop-p1',
              'change': 4.0,
              'reason': 'sale_void',
              'notes': 'PC-SALE-1',
              'created_at': '2026-09-27T08:02:00Z',
              'source_id': 'desktop-sale-id',
            },
          ],
        });
      }
      if (request.method == 'GET' &&
          const ['/api/v1/customers', '/api/v1/suppliers', '/api/v1/categories']
              .contains(request.url.path)) {
        return _json({'ok': true, 'cursor': 3, 'items': []});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/sales') {
        return _json({'ok': true, 'cursor': 3, 'items': []});
      }
      return http.Response('not found', 404);
    });

    try {
      await repo.upsertProduct(const Product(
        id: 'phone-p1', nameZh: '商品', nameEn: 'Product', sku: 'SKU-1',
        barcode: '10001', priceCents: 500, costCents: 200, stock: 10,
      ));
      await (await database.db).delete('sync_outbox');
      await repo.setSetting('lan_sync_host', 'http://127.0.0.1:8787');
      await repo.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        lines: const [{'productId': 'phone-p1', 'qty': 5, 'unitCostCents': 250}],
        totalCents: 1250,
        operator: 'admin',
      );
      final sync = LanSyncClient(repo, database: database, httpClient: client);
      const config = LanSyncConfig(baseUrl: 'http://127.0.0.1:8787', token: 't');
      await sync.synchronize(config);

      final db = await database.db;
      final purchase = (await db.query('purchases')).single;
      await expectLater(
        PurchaseOcrRepository(repo).reversePurchase(
          purchaseId: purchase['id'] as String,
          operator: 'admin',
          reason: 'test reverse',
        ),
        throwsA(isA<StateError>()),
      );
      expect((await repo.getProduct('phone-p1'))!.stock, 15);
      expect((await db.query('purchases')).single['reversed'], 0);
      expect(await db.query('purchase_reversals'), isEmpty);
      expect(await db.query('sync_outbox'), isEmpty);
      final markers = await db.query(
        'stock_moves',
        where: "reason='desktop_catalog_sync'",
      );
      expect(markers, hasLength(2));
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('an unconfirmed reverse response retains ordering until a known ACK',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-reverse-retry-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    var rejectReverse = true;
    final sentKinds = <String>[];
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
        final operation = ((jsonDecode(request.body) as Map)['operations']
            as List).single as Map;
        sentKinds.add(operation['kind'] as String);
        if (rejectReverse && operation['kind'] == 'purchase_reverse') {
          return _json({
            'ok': false,
            'acknowledged': [],
            'error': 'Desktop inventory changed after this purchase',
          });
        }
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
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
      final db = await database.db;
      await queueMutation(db, 'purchase_reverse', 'purchase-1', {
        'purchase_id': 'purchase-1',
        'reason': 'offline reverse',
      });
      await queueMutation(db, 'supplier_upsert', 'supplier-2', {
        'row': {'id': 'supplier-2', 'name': 'Later supplier'},
      });
      final before = await db.query('sync_outbox', orderBy: 'seq ASC');
      final sync = LanSyncClient(repo, database: database, httpClient: client);
      const config = LanSyncConfig(baseUrl: 'http://127.0.0.1:8787', token: 't');

      await expectLater(sync.synchronize(config), throwsStateError);
      final failed = await db.query('sync_outbox', orderBy: 'seq ASC');
      expect(failed.map((row) => row['id']), before.map((row) => row['id']));
      expect(failed.first['last_error'], contains('inventory changed'));
      expect(sentKinds, ['purchase_reverse']);

      rejectReverse = false;
      await sync.synchronize(config);
      expect(sentKinds, ['purchase_reverse', 'purchase_reverse', 'supplier_upsert']);
      expect(await db.query('sync_outbox'), isEmpty);
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('paired Desktop without stock history capability blocks local reversal',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-old-desktop-history-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    try {
      await repo.upsertProduct(const Product(
        id: 'p1', nameZh: '商品', nameEn: 'Product', sku: 'P1', barcode: 'P1',
        priceCents: 500, costCents: 100, stock: 10,
      ));
      final db = await database.db;
      await db.delete('sync_outbox');
      await repo.setSetting('lan_sync_host', 'http://legacy-desktop');
      await repo.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        lines: const [{'productId': 'p1', 'qty': 2, 'unitCostCents': 200}],
        totalCents: 400,
        operator: 'admin',
      );
      final purchase = (await db.query('purchases')).single;
      await expectLater(
        PurchaseOcrRepository(repo).reversePurchase(
          purchaseId: purchase['id'] as String,
          operator: 'admin',
          reason: 'legacy Desktop cannot provide full stock history',
        ),
        throwsA(isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('升级 Desktop'),
        )),
      );
      expect((await repo.getProduct('p1'))!.stock, 12);
      expect((await db.query('purchases')).single['reversed'], 0);
      expect(await db.query('purchase_reversals'), isEmpty);
      expect((await db.query('sync_outbox')).map((row) => row['kind']), ['purchase']);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('restored Desktop stock cursor replaces stale host markers from the new snapshot',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-stock-restore-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 5,
          'stock_moves_cursor': 2,
          'stock_policy': 'desktop',
          'capabilities': ['mutations_v1', 'stock_moves_v1'],
        });
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
        expect(request.url.queryParameters, isEmpty);
        return _json({
          'ok': true,
          'cursor': 5,
          'items': [
            {
              'pc_id': 'desktop-p1', 'name_zh': '商品', 'name_en': 'Product',
              'sku': 'SKU-1', 'barcode': '10001', 'price_cents': 500,
              'cost_cents': 250, 'stock': 10, 'unit': 'pcs', 'category': '',
              'is_deleted': 0, 'reorder_level': 0, 'has_image': false,
            },
          ],
        });
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/stock-moves') {
        expect(request.url.queryParameters, isEmpty);
        return _json({
          'ok': true,
          'cursor': 2,
          'items': [
            {'cursor':1,'id':'current-sale','product_id':'desktop-p1','change':-2.0,'reason':'sale','notes':'R-1','created_at':'2026-09-27T08:00:00Z'},
            {'cursor':2,'id':'current-sale-void','product_id':'desktop-p1','change':2.0,'reason':'sale_void','notes':'R-1','created_at':'2026-09-27T08:01:00Z'},
          ],
        });
      }
      if (request.method == 'GET' &&
          const ['/api/v1/customers', '/api/v1/suppliers', '/api/v1/categories']
              .contains(request.url.path)) {
        return _json({'ok': true, 'cursor': 5, 'items': []});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/sales') {
        return _json({'ok': true, 'cursor': 5, 'items': []});
      }
      return http.Response('not found', 404);
    });
    try {
      final db = await database.db;
      await repo.upsertProduct(const Product(
        id:'phone-p1', nameZh:'商品', nameEn:'Product', sku:'SKU-1',
        barcode:'10001', priceCents:500, costCents:250, stock:10,
      ));
      await db.delete('sync_outbox');
      await db.insert('sync_entity_ids', {
        'entity':'product','remote_id':'desktop-p1','local_id':'phone-p1',
      });
      await db.insert('stock_moves', {
        'id':'mobile-purchase','product_id':'phone-p1','change':5.0,
        'reason':'purchase','created_at':'2026-09-26T08:00:00Z',
        'operator':'staff','notes':'PO-1',
      });
      await db.insert('stock_moves', {
        'id':'desktop-stock:stale-sale','product_id':'phone-p1','change':-4.0,
        'reason':'desktop_catalog_sync','created_at':'2026-09-26T09:00:00Z',
        'operator':'desktop-sync','notes':'Desktop sale: stale [stale-sale]',
      });
      await repo.setSetting('lan_sync_products_cursor','100');
      await repo.setSetting('lan_sync_stock_moves_cursor','20');
      final sync=LanSyncClient(repo,database:database,httpClient:client);
      await sync.synchronize(const LanSyncConfig(baseUrl:'http://127.0.0.1:8787',token:'t'));
      final markers=await db.query('stock_moves',where:"reason='desktop_catalog_sync'",orderBy:'rowid');
      expect(markers.map((row)=>row['id']),['desktop-stock:current-sale','desktop-stock:current-sale-void']);
      expect(await db.query('stock_moves',where:"reason='purchase'"),hasLength(1));
      expect(await repo.getSetting('lan_sync_stock_moves_cursor'), '2');
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive:true);
    }
  });
}
