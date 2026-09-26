import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

http.Response jsonResponse(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  HttpStatus.ok,
  headers: const {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'remote catalog stock changes prevent local reverse without queuing it',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cnkh-remote-reverse-',
      );
      final database = AppDatabase.forTesting(
        '${temp.path}/pos.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      var purchaseUploads = 0;
      var saleUploads = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/v1/health') {
          return jsonResponse({
            'ok': true,
            'protocol': 1,
            'cursor': 42,
            'stock_policy': 'desktop',
            'capabilities': ['mutations_v1'],
          });
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/mutations') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final op = (body['operations'] as List).single as Map;
          if (op['kind'] == 'purchase') purchaseUploads++;
          return jsonResponse({
            'ok': true,
            'acknowledged': [op['id']],
          });
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/products') {
          return jsonResponse({
            'ok': true,
            'cursor': 42,
            'items': [
              {
                'pc_id': 'p1',
                'name_zh': '商品',
                'name_en': 'Product',
                'sku': 'P1',
                'barcode': 'P1',
                'price_cents': 500,
                'cost_cents': 320,
                'stock': 14,
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
            const [
              '/api/v1/customers',
              '/api/v1/suppliers',
              '/api/v1/categories',
            ].contains(request.url.path)) {
          return jsonResponse({'ok': true, 'cursor': 42, 'items': []});
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/sales') {
          return jsonResponse({'ok': true, 'cursor': 42, 'items': []});
        }
        if (request.method == 'POST' && request.url.path == '/api/v1/sales') {
          saleUploads++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final sale = (body['sales'] as List).single as Map;
          return jsonResponse({
            'ok': true,
            'receipts': [
              {
                'client_sale_id': sale['client_sale_id'],
                'receipt_no': sale['receipt_no'],
              },
            ],
          });
        }
        return http.Response('not found', HttpStatus.notFound);
      });

      try {
        final db = await database.db;
        await repo.upsertProduct(
          const Product(
            id: 'p1',
            nameZh: '商品',
            nameEn: 'Product',
            sku: 'P1',
            barcode: 'P1',
            priceCents: 500,
            costCents: 300,
            stock: 10,
          ),
        );
        await repo.setSetting('lan_sync_host', 'http://127.0.0.1:8787');
        await repo.createPurchase(
          supplierId: 's1',
          supplierName: 'Supplier',
          totalCents: 1600,
          operator: 'admin',
          lines: [
            {
              'productId': 'p1',
              'qty': 5,
              'unitCostCents': 320,
              'beforeCostCents': 300,
            },
          ],
        );

        final sync = LanSyncClient(
          repo,
          database: database,
          httpClient: client,
        );
        const config = LanSyncConfig(
          baseUrl: 'http://127.0.0.1:8787',
          token: 'token',
        );
        await sync.synchronize(config);

        expect(purchaseUploads, 1);
        expect((await repo.getProduct('p1'))!.stock, 14);
        final purchase = (await db.query('purchases')).single;
        await expectLater(
          PurchaseOcrRepository(repo).reversePurchase(
            purchaseId: purchase['id'] as String,
            operator: 'admin',
            reason: 'incorrect invoice',
          ),
          throwsA(isA<StateError>()),
        );
        expect((await repo.getProduct('p1'))!.stock, 14);
        expect((await repo.getProduct('p1'))!.costCents, 320);
        expect((await db.query('purchases')).single['reversed'], 0);
        expect(await db.query('purchase_reversals'), isEmpty);
        expect(await db.query('sync_outbox'), isEmpty);

        await db.insert('sales', {
          'id': 'sale-after-remote-stock-change',
          'receipt_no': 'M-SALE-REMOTE-1',
          'sold_at': '2026-09-26T10:00:00Z',
          'cashier': 'admin',
          'payment_method': 'cash',
          'subtotal_cents': 100,
          'total_cents': 100,
          'paid_cents': 100,
          'lines_json': '[]',
        });
        await queueMutation(
          db,
          'sale_upload',
          'sale-after-remote-stock-change',
          {'id': 'sale-after-remote-stock-change'},
        );
        await sync.synchronize(config);
        expect(saleUploads, 1);
        expect(await db.query('sync_outbox'), isEmpty);
        expect((await repo.getProduct('p1'))!.stock, 14);
      } finally {
        client.close();
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
