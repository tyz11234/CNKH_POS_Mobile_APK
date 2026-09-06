import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_history_sync.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Desktop purchase history pull is idempotent and never mutates stock', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-purchase-history-');
    final database = AppDatabase.forTesting('${dir.path}/mobile.db', seed: false);
    final repo = PosRepository(database: database);
    late HttpServer server;
    var reversed = 0;

    try {
      final db = await database.db;
      await repo.upsertSupplier(const Supplier(id: 'local-s1', name: 'Supplier'));
      await repo.upsertProduct(
        const Product(
          id: 'local-p1',
          nameZh: '商品',
          nameEn: 'Product',
          sku: 'P1',
          barcode: '9550000000011',
          priceCents: 500,
          costCents: 200,
          stock: 10,
        ),
      );
      await rememberEntityId(db, 'supplier', 'desktop-s1', 'local-s1');
      await rememberEntityId(db, 'product', 'desktop-p1', 'local-p1');

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.headers.value('X-CNKH-Token') != 'token-1') {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write(jsonEncode({'ok': false, 'error': 'unauthorized'}));
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/v1/health') {
          request.response.write(jsonEncode({
            'ok': true,
            'protocol': 1,
            'capabilities': ['purchases_v1'],
          }));
        } else if (request.uri.path == '/api/v1/purchases') {
          request.response.write(jsonEncode({
            'ok': true,
            'items': [
              {
                'pc_id': 'desktop-purchase-1',
                'purchase_no': 'PO-D-1',
                'supplier_id': 'desktop-s1',
                'supplier_name': 'Supplier',
                'purchased_at': '2026-09-06T12:00:00.000Z',
                'total_cents': 500,
                'notes': 'desktop history',
                'invoice_no': 'INV-D-1',
                'invoice_date': '2026-09-06',
                'discount_cents': 0,
                'tax_cents': 0,
                'delivery_fee_cents': 0,
                'other_fee_cents': 0,
                'source': 'desktop',
                'draft_id': null,
                'ocr_raw_text': '',
                'reversed': reversed,
                'reversed_at': reversed == 1 ? '2026-09-06T13:00:00.000Z' : null,
                'reversed_by': reversed == 1 ? 'admin' : null,
                'reversal_reason': reversed == 1 ? 'corrected' : '',
                'reversal_notes': '',
                'lines': [
                  {
                    'productId': 'desktop-p1',
                    'name': '商品',
                    'qty': 2.0,
                    'unit': 'pcs',
                    'conversionFactor': 1.0,
                    'unitCostCents': 250,
                    'subtotalCents': 500,
                  }
                ],
              }
            ],
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'ok': false}));
        }
        await request.response.close();
      });

      await repo.setSetting(
        'lan_sync_host',
        'http://127.0.0.1:${server.port}',
      );
      await repo.setSetting('lan_sync_token', 'token-1');

      final sync = PurchaseHistorySync(repo, database: database);
      final first = await sync.pullFromSavedDesktop();
      expect(first.supported, isTrue);
      expect(first.changed, 1);

      var purchases = await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: ['desktop-purchase-1'],
      );
      expect(purchases, hasLength(1));
      expect(purchases.single['supplier_id'], 'local-s1');
      final lines = jsonDecode(purchases.single['lines_json'] as String) as List;
      expect((lines.single as Map)['productId'], 'local-p1');
      expect((await repo.getProduct('local-p1'))!.stock, 10);
      expect(await db.query('stock_moves'), isEmpty);

      final second = await sync.pullFromSavedDesktop();
      expect(second.changed, 1);
      purchases = await db.query('purchases');
      expect(purchases, hasLength(1));
      expect((await repo.getProduct('local-p1'))!.stock, 10);
      expect(await db.query('stock_moves'), isEmpty);

      reversed = 1;
      await sync.pullFromSavedDesktop();
      purchases = await db.query('purchases');
      expect(purchases.single['reversed'], 1);
      expect((await repo.getProduct('local-p1'))!.stock, 10);
      expect(await db.query('stock_moves'), isEmpty);
      final reversal = await db.query(
        'purchase_reversals',
        where: 'purchase_id=?',
        whereArgs: ['desktop-purchase-1'],
      );
      expect(reversal, hasLength(1));
      expect(reversal.single['reason'], 'corrected');
    } finally {
      await server.close(force: true);
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
