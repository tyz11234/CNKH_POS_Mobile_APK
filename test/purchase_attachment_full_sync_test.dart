import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
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
    'failed invoice attachment stays retryable while synchronize pulls business data',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cnkh-attachment-full-sync-',
      );
      final database = AppDatabase.forTesting(
        '${temp.path}/pos.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      var attachmentAttempts = 0;
      var saleUploads = 0;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/api/v1/health') {
          return jsonResponse({
            'ok': true,
            'protocol': 1,
            'cursor': 2,
            'stock_policy': 'desktop',
            'capabilities': ['mutations_v1'],
          });
        }
        if (request.method == 'POST' && path == '/api/v1/mutations') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final op = (body['operations'] as List).single as Map;
          if (op['kind'] == 'purchase_attachment') {
            attachmentAttempts++;
            return http.Response(
              jsonEncode({
                'ok': false,
                'error': 'simulated attachment failure',
                'acknowledged': <String>[],
              }),
              HttpStatus.ok,
              headers: {'content-type': 'application/json'},
            );
          }
          return jsonResponse({
            'ok': true,
            'acknowledged': [op['id']],
          });
        }
        if (request.method == 'GET' && path == '/api/v1/products') {
          return jsonResponse({
            'ok': true,
            'cursor': 2,
            'items': [
              {
                'pc_id': 'product-pulled',
                'name_zh': 'Pulled Product',
                'name_en': 'Pulled Product',
                'sku': 'PULLED-1',
                'barcode': 'PULLED-1',
                'price_cents': 500,
                'cost_cents': 200,
                'stock': 8,
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
            ].contains(path)) {
          return jsonResponse({'ok': true, 'cursor': 2, 'items': []});
        }
        if (request.method == 'GET' && path == '/api/v1/sales') {
          return jsonResponse({
            'ok': true,
            'cursor': 2,
            'items': [
              {
                'pc_id': 'desktop-sale-1',
                'receipt_no': 'PC-SALE-1',
                'sold_at': '2026-09-06T11:00:00Z',
                'cashier': 'admin',
                'payment_method': 'cash',
                'subtotal_cents': 250,
                'total_cents': 250,
                'paid_cents': 250,
                'lines': [],
                'is_deleted': 0,
              },
            ],
          });
        }
        if (request.method == 'POST' && path == '/api/v1/sales') {
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
        await ensureOcrPurchaseSchema(db);
        await repo.upsertProduct(
          const Product(
            id: 'product-pulled',
            nameZh: 'Local Product',
            nameEn: 'Local Product',
            sku: 'PULLED-1',
            barcode: 'PULLED-1',
            priceCents: 300,
            costCents: 100,
            stock: 10,
          ),
        );
        await repo.setSetting('lan_sync_host', 'http://127.0.0.1:8787');
        final original = File('${temp.path}/invoice-original.jpg');
        await original.writeAsBytes(List<int>.generate(32, (i) => i));
        await db.insert('purchase_drafts', {
          'id': 'draft-full-sync',
          'original_image_path': original.path,
          'created_at': '2026-09-06T10:00:00Z',
          'created_by': 'staff',
        });
        await db.insert('purchases', {
          'id': 'purchase-full-sync',
          'purchase_no': 'PO-FULL-SYNC',
          'supplier_name': 'Supplier',
          'purchased_at': '2026-09-06T10:00:00Z',
          'total_cents': 100,
          'lines_json': '[]',
        });
        await db.insert('purchase_attachments', {
          'id': 'attachment-full-sync',
          'purchase_id': 'purchase-full-sync',
          'local_path': original.path,
          'kind': 'invoice_original',
          'created_at': '2026-09-06T10:00:00Z',
        });
        await queueMutation(db, 'purchase', 'purchase-full-sync', {
          'id': 'purchase-full-sync',
          'source': 'ocr',
          'draft_id': 'draft-full-sync',
        });
        await db.insert('sales', {
          'id': 'sale-after-attachment',
          'receipt_no': 'M-SALE-1',
          'sold_at': '2026-09-06T10:01:00Z',
          'cashier': 'staff',
          'payment_method': 'cash',
          'subtotal_cents': 100,
          'total_cents': 100,
          'paid_cents': 100,
          'lines_json': '[]',
        });
        await queueMutation(db, 'sale_upload', 'sale-after-attachment', {
          'id': 'sale-after-attachment',
        });

        final sync = LanSyncClient(
          repo,
          database: database,
          httpClient: client,
        );
        const config = LanSyncConfig(
          baseUrl: 'http://127.0.0.1:8787',
          token: 'token',
        );
        final message = await sync.synchronize(config);

        expect(message, contains('待重试'));
        expect(attachmentAttempts, 1);
        expect(saleUploads, 1);
        expect((await repo.getProduct('product-pulled'))!.stock, 8);
        expect(
          await db.query(
            'sales',
            where: 'receipt_no=?',
            whereArgs: ['PC-SALE-1'],
          ),
          hasLength(1),
        );
        expect(
          (await db.query(
            'sales',
            where: 'id=?',
            whereArgs: ['sale-after-attachment'],
          )).single['synced_at'],
          isNotNull,
        );
        expect(
          (await db.query('purchase_attachments')).single['sync_status'],
          'failed',
        );
        var remaining = await db.query('sync_outbox');
        expect(remaining, hasLength(1));
        expect(remaining.single['kind'], 'purchase_attachment');
        expect(
          remaining.single['last_error'],
          contains('simulated attachment failure'),
        );

        await sync.synchronize(config);
        expect(attachmentAttempts, 2);
        expect(saleUploads, 1);
        expect(
          (await db.query('purchase_attachments')).single['sync_status'],
          'failed',
        );
        remaining = await db.query('sync_outbox');
        expect(remaining, hasLength(1));
        expect(remaining.single['kind'], 'purchase_attachment');
        expect((await repo.getProduct('product-pulled'))!.stock, 8);
        expect(
          await db.query(
            'sales',
            where: 'receipt_no=?',
            whereArgs: ['PC-SALE-1'],
          ),
          hasLength(1),
        );
      } finally {
        client.close();
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
