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
import 'package:cnkh_pos_mobile/services/purchase_history_sync.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

http.Response _json(Map<String, Object?> body) => http.Response(jsonEncode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('independent history pull cannot overwrite an unacknowledged purchase or advance past it', () async {
    final temp=await Directory.systemTemp.createTemp('cnkh-pending-purchase-history-');
    final database=AppDatabase.forTesting('${temp.path}/phone.db',seed:false);
    final repo=PosRepository(database:database);
    http.Client? transport;
    try {
      await repo.upsertProduct(const Product(id:'p1',sku:'P1',barcode:'1',nameZh:'商品',
        nameEn:'Product',priceCents:500,costCents:100,stock:10));
      final db=await database.db;
      await db.delete('sync_outbox');
      await repo.createPurchase(supplierId:'supplier',supplierName:'Supplier',
        lines:[{'productId':'p1','qty':5,'unitCostCents':200}],totalCents:1000,operator:'admin');
      final before=(await db.query('purchases')).single;
      await repo.setSetting('lan_sync_host','http://desktop');
      transport=MockClient((request)async=>_json({'ok':true,'cursor':100,'items':[{
        'pc_id':before['id'],'purchase_no':'OLDER-PO','supplier_name':'Supplier',
        'purchased_at':before['purchased_at'],'total_cents':200,'reversed':1,
        'lines':[{'productId':'p1','qty':1,'unitCostCents':999,'beforeCostCents':900}],
      }]}));
      final history=PurchaseHistorySync(repo,client:transport);
      final pending=await history.pullFromSavedDesktop(capabilityKnown:true,full:true);
      expect(pending.changed,0);
      expect((await db.query('purchases')).single,before);
      expect(await repo.getSetting('lan_sync_purchases_cursor'),'');
      expect((await repo.getProduct('p1'))!.stock,15);
      expect((await repo.getProduct('p1'))!.costCents,200);
      // Model a confirmed upload: only then may the separate history mirror
      // adopt the host's row. Catalog inventory still has its own sync path.
      await db.delete('sync_outbox',where:"kind='purchase'");
      final confirmed=await history.pullFromSavedDesktop(capabilityKnown:true,full:true);
      expect(confirmed.changed,1);
      expect(await repo.getSetting('lan_sync_purchases_cursor'),'100');
      expect((await db.query('purchases')).single['reversed'],1);
      expect((await repo.getProduct('p1'))!.stock,15);
    } finally {
      transport?.close();
      await database.close();
      await temp.delete(recursive:true);
    }
  });

  test('definite Desktop refusal compensates a legacy local undo once and retains the request', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-legacy-undo-rejection-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    final sent = <String>[];
    final transport = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({'ok': true, 'protocol': 1, 'cursor': 3, 'stock_moves_cursor': 3,
          'capabilities': ['mutations_v1','stock_moves_v1','mutation_rejections_v1']});
      }
      if (request.url.path == '/api/v1/mutations') {
        final operation = (jsonDecode(request.body)['operations'] as List).single as Map;
        sent.add(operation['kind'] as String);
        if (operation['kind'] == 'purchase_reverse') {
          return _json({'ok': false, 'acknowledged': [], 'error': 'Desktop has later stock activity',
            'rejected_operation': {'id': operation['id'], 'kind': 'purchase_reverse', 'code': 'purchase_reverse_rejected'}});
        }
        return _json({'ok': true, 'acknowledged': [operation['id']]});
      }
      if (request.url.path == '/api/v1/products') {
        return _json({'ok': true, 'cursor': 3, 'items': [{
          'pc_id': 'desktop-product', 'sku': 'SKU-1', 'barcode': '10001',
          'name_zh': '商品', 'name_en': 'Product', 'price_cents': 500,
          'cost_cents': 200, 'stock': 15, 'is_deleted': 0,
        }]});
      }
      return _json({'ok': true, 'cursor': 3, 'items': []});
    });
    try {
      await repo.upsertProduct(const Product(id: 'phone-product', sku: 'SKU-1', barcode: '10001',
        nameZh: '商品', nameEn: 'Product', priceCents: 500, costCents: 100, stock: 10));
      final db = await database.db;
      await db.delete('sync_outbox');
      await repo.createPurchase(supplierId: 'supplier', supplierName: 'Supplier',
        lines: [{'productId': 'phone-product', 'qty': 5, 'unitCostCents': 200}],
        totalCents: 1000, operator: 'admin');
      final purchase = (await db.query('purchases')).single;
      await PurchaseOcrRepository(repo).reversePurchase(purchaseId: purchase['id'] as String,
        operator: 'admin', reason: 'offline legacy undo');
      expect((await repo.getProduct('phone-product'))!.stock, 10);
      expect((await repo.getProduct('phone-product'))!.costCents, 100);
      final originalRequest = (await db.query('sync_outbox', where: "kind='purchase_reverse'")).single;
      await queueMutation(db, 'supplier_upsert', 'later-supplier', {'row': {'id': 'later-supplier', 'name': 'Later'}});
      final sync = LanSyncClient(repo, httpClient: transport);
      const config = LanSyncConfig(baseUrl: 'http://desktop', token: 'token');
      await sync.saveConfig(config);
      final result = await sync.synchronize(config);
      expect(result, contains('原请求已保留'));
      expect(sent, ['purchase','purchase_reverse','supplier_upsert']);
      expect((await repo.getProduct('phone-product'))!.stock, 15);
      expect((await repo.getProduct('phone-product'))!.costCents, 200);
      expect((await db.query('purchases')).single['reversed'], 0);
      expect(await db.query('purchase_reversals'), isEmpty);
      final retained = (await db.query('sync_outbox')).single;
      expect(retained['id'], originalRequest['id']);
      expect(retained['delivery_state'], 'rejected');
      expect(retained['last_error'], contains('later stock activity'));
      final audit = (await db.query('purchase_audit_log', where: "action='purchase_reverse_rejected'")).single;
      expect(audit['details'], contains('local_reversal'));
      expect(audit['details'], contains('offline legacy undo'));
      await sync.synchronize(config);
      expect((await repo.getProduct('phone-product'))!.stock, 15);
      expect(await db.query('stock_moves', where: "reason='purchase_reversal_rejected'"), hasLength(1));
      expect(await db.query('purchase_audit_log', where: "action='purchase_reverse_rejected'"), hasLength(1));
      expect((await db.query('sync_outbox')).single['id'], originalRequest['id']);
    } finally {
      transport.close();
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
