import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/models/purchase_ocr.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ACK-lost OCR purchase and invoice attachment block transactional cleanup',
    () async {
      final dir = await Directory.systemTemp.createTemp('cnkh-clear-purchase-');
      final database = AppDatabase.forTesting(
        '${dir.path}/mobile.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      final ocr = PurchaseOcrRepository(repo);
      final invoice = File('${dir.path}/发票-original.jpg');
      await invoice.writeAsBytes([1, 2, 3, 4]);
      try {
        final db = await database.db;
        await db.insert('suppliers', {
          'id': 's1',
          'name': '供应商',
          'phone': '',
          'email': '',
          'notes': '',
          'is_deleted': 0,
        });
        await db.insert(
          'products',
          const Product(
            id: 'p1',
            nameZh: '商品',
            nameEn: 'Product',
            sku: 'P1',
            barcode: '10001',
            priceCents: 100,
            costCents: 50,
            stock: 1,
          ).toMap(),
        );
        final purchaseId = await ocr.commitDraft(
          PurchaseDraft(
            draftId: 'ocr-draft-1',
            supplierId: 's1',
            supplierName: '供应商',
            invoiceNo: 'INV-1',
            originalImagePath: invoice.path,
            lines: const [
              PurchaseDraftLine(
                id: 'line-1',
                rawText: '商品 2 件',
                rawProductName: '商品',
                matchedProductId: 'p1',
                matchedProductName: '商品',
                matchConfidence: 1,
                quantity: 2,
                unit: 'pcs',
                unitCostCents: 50,
                lineSubtotalCents: 100,
                conversionFactor: 1,
              ),
            ],
            invoiceTotalCents: 100,
            createdAt: DateTime.utc(2026, 10, 3).toIso8601String(),
            createdBy: 'admin',
          ),
          operator: 'admin',
        );
        final purchaseOp = (await db.query(
          'sync_outbox',
          where: "kind='purchase'",
        )).single;
        final attachmentOp = (await db.query(
          'sync_outbox',
          where: "kind='purchase_attachment'",
        )).single;
        expect(await db.query('purchase_attachments'), hasLength(1));

        // The request may have reached Desktop while its ACK was lost. It stays
        // queued as an uncertain result and must prevent erasing local history.
        await db.update(
          'sync_outbox',
          {'delivery_state': 'sent'},
          where: 'id=?',
          whereArgs: [purchaseOp['id']],
        );
        await expectLater(
          database.clearDemoTransactionalData(),
          throwsA(isA<StateError>()),
        );
        expect(
          (await db.query(
            'sync_outbox',
            where: 'id=?',
            whereArgs: [purchaseOp['id']],
          )).single['delivery_state'],
          'sent',
        );
        expect(
          await db.query(
            'sync_outbox',
            where: 'id=?',
            whereArgs: [attachmentOp['id']],
          ),
          hasLength(1),
        );
        expect(
          await db.query('purchases', where: 'id=?', whereArgs: [purchaseId]),
          hasLength(1),
        );
        expect(await db.query('purchase_attachments'), hasLength(1));
        expect((await repo.getProduct('p1'))!.stock, 3);
      } finally {
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );

  for (final blockedKind in [
    'sale_upload',
    'sale_void',
    'stocktake',
    'purchase',
    'purchase_attachment',
    'purchase_reverse',
    'credit_payment',
    'future_transaction',
  ]) {
    test(
      'pending $blockedKind alone blocks clear and preserves unrelated operations',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'cnkh-clear-$blockedKind-',
        );
        final database = AppDatabase.forTesting(
          '${dir.path}/mobile.db',
          seed: false,
        );
        try {
          final db = await database.db;
          await queueMutation(db, 'product_upsert', 'keep-product', {
            'row': {'id': 'p1'},
          });
          await queueMutation(db, 'customer_upsert', 'keep-customer', {
            'row': {'id': 'c1'},
          });
          await queueMutation(db, blockedKind, 'uncertain-op', {
            'purchase_id': 'purchase-1',
          });
          final before = await db.query('sync_outbox', orderBy: 'seq ASC');
          await expectLater(
            database.clearDemoTransactionalData(),
            throwsA(isA<StateError>()),
          );
          expect(await db.query('sync_outbox', orderBy: 'seq ASC'), before);
        } finally {
          await database.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }

  for (final hasOutbox in [true, false]) {
    test(
      'offline sale ${hasOutbox ? "with" : "without"} outbox survives clear until acknowledged',
      () async {
        final dir = await Directory.systemTemp.createTemp('cnkh-clear-sale-');
        final database = AppDatabase.forTesting(
          '${dir.path}/mobile.db',
          seed: false,
        );
        final repo = PosRepository(database: database);
        try {
          final db = await database.db;
          const product = Product(
            id: 'p1',
            nameZh: '商品',
            nameEn: 'Product',
            sku: 'P1',
            barcode: '10001',
            priceCents: 100,
            stock: 10,
          );
          await db.insert('products', product.toMap());
          final sale = await repo.createSale(
            cart: CartState(items: [CartItem(product: product, qty: 2)]),
            paymentMethod: 'CASH',
            paidCents: 200,
            cashier: 'staff',
          );
          if (!hasOutbox) {
            // Pre-outbox versions can leave an empty sync timestamp and no op.
            await db.delete('sync_outbox');
            await db.update('sales', {'synced_at': ''});
          }
          final before = {
            for (final table in ['sales', 'stock_moves', 'sync_outbox'])
              table: await db.query(table),
          };
          await expectLater(
            database.clearDemoTransactionalData(),
            throwsA(isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('销售尚未获电脑确认'),
            )),
          );
          for (final entry in before.entries) {
            expect(await db.query(entry.key), entry.value);
          }
          expect((await repo.getProduct('p1'))!.stock, 8);

          // Once Desktop acknowledges both the sale and its operation, the
          // explicit maintenance action is allowed again.
          await db.update(
            'sales',
            {'synced_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id=?',
            whereArgs: [sale.id],
          );
          await db.delete('sync_outbox');
          await database.clearDemoTransactionalData();
          expect(await db.query('sales'), isEmpty);
          expect(await db.query('stock_moves'), isEmpty);
        } finally {
          await database.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }

  for (final state in ['sent', 'needs_review', 'rejected']) {
    test('unresolved sale void in $state state still blocks clear', () async {
      final dir = await Directory.systemTemp.createTemp('cnkh-clear-void-');
      final database = AppDatabase.forTesting('${dir.path}/mobile.db');
      try {
        final db = await database.db;
        await queueMutation(db, 'sale_void', 'sale-1', {
          'client_sale_id': 'sale-1',
        });
        await db.update('sync_outbox', {'delivery_state': state});
        final before = await db.query('sync_outbox');
        await expectLater(
          database.clearDemoTransactionalData(),
          throwsA(isA<StateError>()),
        );
        expect(await db.query('sync_outbox'), before);
      } finally {
        await database.close();
        await dir.delete(recursive: true);
      }
    });
  }

  test(
    'successful clear leaves unrelated product/customer outbox operations intact',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'cnkh-clear-unrelated-',
      );
      final database = AppDatabase.forTesting(
        '${dir.path}/mobile.db',
        seed: false,
      );
      try {
        final db = await database.db;
        await queueMutation(db, 'product_upsert', 'p1', {
          'row': {'id': 'p1'},
        });
        await queueMutation(db, 'customer_upsert', 'c1', {
          'row': {'id': 'c1'},
        });
        final original = await db.query('sync_outbox', orderBy: 'seq ASC');
        await database.clearDemoTransactionalData();
        expect(await db.query('sync_outbox', orderBy: 'seq ASC'), original);
      } finally {
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
