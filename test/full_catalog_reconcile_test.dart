import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

http.Response _json(Map<String, Object?> value) => http.Response(
      jsonEncode(value),
      HttpStatus.ok,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a malformed full response cannot be treated as an empty authoritative catalog', () async {
    final temp=await Directory.systemTemp.createTemp('cnkh-invalid-catalog-');
    final database=AppDatabase.forTesting('${temp.path}/phone.db',seed:false);
    final repo=PosRepository(database:database);
    final transport=MockClient((request)async {
      if(request.url.path=='/api/v1/health') return _json({'ok':true,'protocol':1,'cursor':0,'capabilities':['mutations_v1']});
      if(request.url.path=='/api/v1/products') return _json({'ok':true,'cursor':0});
      return _json({'ok':true,'cursor':0,'items':[]});
    });
    try {
      await repo.upsertProduct(const Product(id:'kept',sku:'KEPT',barcode:'KEPT',nameZh:'保留',
        nameEn:'Kept',priceCents:100,stock:3));
      final db=await database.db;
      await db.delete('sync_outbox');
      await rememberEntityId(db,'product','desktop-kept','kept');
      final sync=LanSyncClient(repo,httpClient:transport);
      await expectLater(sync.synchronize(const LanSyncConfig(baseUrl:'http://desktop',token:'t'),full:true),throwsFormatException);
      expect((await repo.getProduct('kept'))!.isDeleted,0);
      expect((await repo.getProduct('kept'))!.stock,3);
      expect(await repo.getSetting('lan_sync_products_cursor'),'');
    } finally {
      transport.close();
      await database.close();
      await temp.delete(recursive:true);
    }
  });

  test('full snapshot tombstones missing PC rows but preserves local-only rows',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-full-catalog-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    var rejectPending = true;
    var productReads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 5,
          'stock_policy': 'desktop',
          'capabilities': ['mutations_v1'],
        });
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/mutations') {
        final operation = ((jsonDecode(request.body) as Map)['operations']
            as List).single as Map;
        if (rejectPending) {
          return _json({'ok': false, 'acknowledged': [], 'error': 'offline'});
        }
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/products') {
        productReads++;
        expect(request.url.queryParameters, isEmpty);
        return _json({
          'ok': true,
          'cursor': 5,
          'items': [
            {
              'pc_id': 'desktop-kept',
              'name_zh': '电脑商品',
              'name_en': 'Host Product',
              'sku': 'HOST-1',
              'barcode': '90001',
              'price_cents': 1000,
              'cost_cents': 700,
              'stock': 9,
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
        id: 'mapped-removed', nameZh: '旧电脑商品', nameEn: 'Removed',
        sku: 'OLD-PC', barcode: '80001', priceCents: 1000, stock: 4,
      ));
      await repo.upsertProduct(const Product(
        id: 'mobile-only', nameZh: '手机本地商品', nameEn: 'Local only',
        sku: 'MOBILE-ONLY', barcode: '70001', priceCents: 1000, stock: 6,
      ));
      // Catalog rows and mappings model an already-established local cache.
      await db.delete('sync_outbox');
      await db.insert('customers', {
        'id': 'mapped-customer', 'name': '旧客户', 'phone': '', 'notes': '', 'is_deleted': 0,
      });
      await db.insert('suppliers', {
        'id': 'mapped-supplier', 'name': '旧供应商', 'phone': '', 'email': '', 'notes': '', 'is_deleted': 0,
      });
      await db.insert('categories', {
        'id': 'mapped-category', 'name': '旧分类', 'is_deleted': 0, 'updated_at': '',
      });
      for (final mapping in [
        ['product', 'desktop-removed', 'mapped-removed'],
        ['customer', 'desktop-customer', 'mapped-customer'],
        ['supplier', 'desktop-supplier', 'mapped-supplier'],
        ['category', 'desktop-category', 'mapped-category'],
      ]) {
        await db.insert('sync_entity_ids', {
          'entity': mapping[0], 'remote_id': mapping[1], 'local_id': mapping[2],
        });
      }
      await repo.setSetting('lan_sync_products_cursor', '100');
      await queueMutation(db, 'stocktake', 'mapped-removed', {
        'product_id': 'desktop-removed', 'stock': 5.0, 'before_stock': 4.0,
      });

      final sync = LanSyncClient(repo, database: database, httpClient: client);
      const config = LanSyncConfig(baseUrl: 'http://127.0.0.1:8787', token: 't');
      await expectLater(sync.synchronize(config, full: true), throwsStateError);
      expect(productReads, 0);
      expect((await repo.getProduct('mapped-removed'))!.isDeleted, 0);
      expect((await repo.getProduct('mobile-only'))!.isDeleted, 0);
      expect(await db.query('sync_outbox'), hasLength(1));

      rejectPending = false;
      await sync.synchronize(config, full: true);
      expect(productReads, 1);
      expect((await repo.getProduct('mapped-removed'))!.isDeleted, 1);
      expect((await repo.getProduct('mobile-only'))!.isDeleted, 0);
      expect((await db.query('customers')).single['is_deleted'], 1);
      expect((await db.query('suppliers')).single['is_deleted'], 1);
      expect((await db.query('categories')).single['is_deleted'], 1);
      expect(await db.query('sync_outbox'), isEmpty);
    } finally {
      client.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
