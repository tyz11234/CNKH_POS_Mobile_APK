import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_history_sync.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> restoredPurchase({
  String notes = 'restored backup content',
}) => {
  'pc_id': 'desktop-purchase-restored',
  'purchase_no': 'PO-RESTORED-1',
  'supplier_id': 'desktop-supplier-1',
  'supplier_name': 'Supplier',
  'purchased_at': '2026-09-20T09:00:00Z',
  'total_cents': 500,
  'notes': notes,
  'invoice_no': 'INV-RESTORED-1',
  'invoice_date': '2026-09-20',
  'discount_cents': 0,
  'tax_cents': 0,
  'delivery_fee_cents': 0,
  'other_fee_cents': 0,
  'source': 'manual',
  'draft_id': null,
  'ocr_raw_text': '',
  'reversed': 0,
  'reversed_at': null,
  'reversed_by': null,
  'reversal_reason': '',
  'reversal_notes': '',
  'is_deleted': 0,
  'lines': [
    {
      'productId': 'desktop-product-1',
      'name': 'Product',
      'qty': 2.0,
      'unit': 'pcs',
      'conversionFactor': 1.0,
      'unitCostCents': 250,
      'subtotalCents': 500,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'cursor rollback from 100 to 20 triggers a full history correction',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cnkh-purchase-cursor-',
      );
      final database = AppDatabase.forTesting(
        '${temp.path}/pos.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      late MockClient httpClient;
      final requestedSince = <String>[];
      try {
        final db = await database.db;
        await ensureOcrPurchaseSchema(db);
        await repo.upsertProduct(
          const Product(
            id: 'local-product-1',
            nameZh: 'Product',
            nameEn: 'Product',
            sku: 'P1',
            barcode: 'P1',
            priceCents: 500,
            costCents: 200,
            stock: 10,
          ),
        );
        await rememberEntityId(
          db,
          'product',
          'desktop-product-1',
          'local-product-1',
        );
        await db.insert('purchases', {
          'id': 'pc-p-desktop-purchase-restored',
          'purchase_no': 'PO-OLD-COPY',
          'supplier_name': 'Supplier',
          'purchased_at': '2026-09-01T09:00:00Z',
          'total_cents': 200,
          'lines_json': '[]',
          'notes': 'stale phone copy',
          'source': 'desktop_sync',
        });
        await rememberEntityId(
          db,
          'purchase',
          'desktop-purchase-restored',
          'pc-p-desktop-purchase-restored',
        );
        await db.insert('purchase_attachments', {
          'id': 'original-attachment-1',
          'purchase_id': 'pc-p-desktop-purchase-restored',
          'local_path': 'invoice-original.jpg',
          'kind': 'invoice_original',
          'sync_status': 'failed',
          'synced_at': null,
          'last_error': 'previous upload failure',
          'created_at': '2026-09-01T09:01:00Z',
        });
        await repo.setSetting('lan_sync_host', 'pending');
        await queueMutation(
          db,
          'purchase_attachment',
          'pc-p-desktop-purchase-restored',
          {'attachment_id': 'original-attachment-1'},
        );
        await db.insert('purchases', {
          'id': 'local-pending-purchase',
          'purchase_no': 'PO-PENDING-1',
          'supplier_name': 'Local Supplier',
          'purchased_at': '2026-09-26T09:00:00Z',
          'total_cents': 100,
          'lines_json': '[]',
          'notes': 'pending mobile purchase',
          'source': 'ocr',
        });
        await queueMutation(db, 'purchase', 'local-pending-purchase', {
          'id': 'local-pending-purchase',
        });
        await repo.setSetting('lan_sync_host', 'pending');
        await repo.setSetting('lan_sync_purchases_cursor', '100');

        httpClient = MockClient((request) async {
          if (request.url.path != '/api/v1/purchases') {
            return http.Response('not found', HttpStatus.notFound);
          }
          final since = request.url.queryParameters['since'] ?? '';
          requestedSince.add(since);
          return http.Response(
            jsonEncode({
              'ok': true,
              'items': since.isEmpty ? [restoredPurchase()] : <Object?>[],
              'cursor': 20,
            }),
            HttpStatus.ok,
            headers: {'content-type': 'application/json'},
          );
        });
        await repo.setSetting('lan_sync_host', 'http://desktop.test');

        final sync = PurchaseHistorySync(
          repo,
          database: database,
          client: httpClient,
        );
        final corrected = await sync.pullFromSavedDesktop(
          capabilityKnown: true,
        );
        expect(corrected.changed, 1);
        expect(requestedSince, ['100', '']);
        expect(await repo.getSetting('lan_sync_purchases_cursor'), '20');
        var purchases = await db.query('purchases', orderBy: 'id');
        expect(purchases, hasLength(2));
        expect(
          (await db.query(
            'purchases',
            where: 'id=?',
            whereArgs: ['pc-p-desktop-purchase-restored'],
          )).single['notes'],
          'restored backup content',
        );
        expect((await repo.getProduct('local-product-1'))!.stock, 10);
        expect(await db.query('stock_moves'), isEmpty);

        final attachment = (await db.query('purchase_attachments')).single;
        expect(attachment['local_path'], 'invoice-original.jpg');
        expect(attachment['sync_status'], 'failed');
        expect(attachment['last_error'], 'previous upload failure');
        expect(
          await db.query('sync_outbox', where: "kind='purchase_attachment'"),
          hasLength(1),
        );
        expect(
          await db.query('sync_outbox', where: "kind='purchase'"),
          hasLength(1),
        );

        final repeated = await sync.pullFromSavedDesktop(capabilityKnown: true);
        expect(repeated.changed, 0);
        expect(await repo.getSetting('lan_sync_purchases_cursor'), '20');
        purchases = await db.query('purchases', orderBy: 'id');
        expect(purchases, hasLength(2));
        expect(
          (await db.query(
            'purchases',
            where: 'id=?',
            whereArgs: ['pc-p-desktop-purchase-restored'],
          )).single['notes'],
          'restored backup content',
        );
      } finally {
        httpClient.close();
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'cursor stays unchanged when a rollback correction fetch or write fails',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cnkh-purchase-cursor-retry-',
      );
      final database = AppDatabase.forTesting(
        '${temp.path}/pos.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      late MockClient httpClient;
      var failFullFetch = true;
      try {
        final db = await database.db;
        await ensureOcrPurchaseSchema(db);
        await repo.setSetting('lan_sync_purchases_cursor', '100');
        httpClient = MockClient((request) async {
          if (request.url.path != '/api/v1/purchases') {
            return http.Response('not found', HttpStatus.notFound);
          }
          if ((request.url.queryParameters['since'] ?? '').isNotEmpty) {
            return http.Response(
              jsonEncode({'ok': true, 'items': [], 'cursor': 20}),
              HttpStatus.ok,
              headers: {'content-type': 'application/json'},
            );
          }
          if (failFullFetch) {
            return http.Response(
              jsonEncode({'ok': false}),
              HttpStatus.serviceUnavailable,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'items': [restoredPurchase()],
              'cursor': 20,
            }),
            HttpStatus.ok,
            headers: {'content-type': 'application/json'},
          );
        });
        await repo.setSetting('lan_sync_host', 'http://desktop.test');
        final sync = PurchaseHistorySync(
          repo,
          database: database,
          client: httpClient,
        );

        await expectLater(
          sync.pullFromSavedDesktop(capabilityKnown: true),
          throwsA(isA<StateError>()),
        );
        expect(await repo.getSetting('lan_sync_purchases_cursor'), '100');

        failFullFetch = false;
        await db.execute('''
CREATE TRIGGER fail_purchase_history_insert
BEFORE INSERT ON purchases
BEGIN
  SELECT RAISE(ABORT, 'simulated history write failure');
END
''');
        await expectLater(
          sync.pullFromSavedDesktop(capabilityKnown: true),
          throwsA(anything),
        );
        expect(await repo.getSetting('lan_sync_purchases_cursor'), '100');
        expect(await db.query('purchases'), isEmpty);

        await db.execute('DROP TRIGGER fail_purchase_history_insert');
        final retried = await sync.pullFromSavedDesktop(capabilityKnown: true);
        expect(retried.changed, 1);
        expect(await repo.getSetting('lan_sync_purchases_cursor'), '20');
        expect(await db.query('purchases'), hasLength(1));
      } finally {
        httpClient.close();
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
