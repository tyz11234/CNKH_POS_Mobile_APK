import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/models/purchase_ocr.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/product_match_service.dart';
import 'package:cnkh_pos_mobile/services/purchase_invoice_parser.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_validation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OCR invoice parser', () {
    const parser = PurchaseInvoiceParser();

    test('parses product rows and keeps fees out of products', () {
      final draft = parser.parse(
        '''ABC Trading Sdn Bhd
Invoice No: INV-2026-0906
Date: 06/09/2026
Coca Cola 12 CTN 3.20 38.40
Discount 2.00
SST 2.18
Delivery 5.00
Grand Total 43.58''',
        draftId: 'd1',
        createdBy: 'admin',
      );
      expect(draft.supplierName, 'ABC Trading Sdn Bhd');
      expect(draft.invoiceNo, 'INV-2026-0906');
      expect(draft.invoiceDate, '2026-09-06');
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.rawProductName, 'Coca Cola');
      expect(draft.lines.single.quantity, 12);
      expect(draft.lines.single.unitCostCents, 320);
      expect(draft.lines.single.lineSubtotalCents, 3840);
      expect(draft.discountCents, 200);
      expect(draft.taxCents, 218);
      expect(draft.deliveryFeeCents, 500);
      expect(draft.invoiceTotalCents, 4358);
      expect(draft.calculatedTotalCents, 4358);
    });
  });

  group('Product matching', () {
    const matcher = ProductMatchService();

    test('normalizes common OCR letter-number confusion', () {
      expect(matcher.normalizeName('COCA C0LA'), matcher.normalizeName('Coca Cola'));
    });

    test('ranks normalized product as high confidence', () {
      const product = Product(
        id: 'p1',
        nameZh: 'Coca Cola',
        nameEn: 'Coca Cola',
        sku: 'CC15',
        barcode: '9551234567890',
        priceCents: 450,
      );
      final result = matcher.rank('COCA C0LA', const [product]);
      expect(result, isNotEmpty);
      expect(result.first.product.id, 'p1');
      expect(result.first.confidence, greaterThanOrEqualTo(0.9));
    });
  });

  group('OCR validation', () {
    const validator = PurchaseValidationService();

    PurchaseDraftLine line({
      double qty = 12,
      int cost = 320,
      int subtotal = 3840,
    }) => PurchaseDraftLine(
          id: 'l1',
          rawText: 'Coca Cola $qty 3.20',
          rawProductName: 'Coca Cola',
          matchedProductId: 'p1',
          matchedProductName: 'Coca Cola',
          matchConfidence: 1,
          quantity: qty,
          unitCostCents: cost,
          lineSubtotalCents: subtotal,
        );

    test('flags quantity and line math anomalies without changing numbers', () {
      final input = line(qty: 72, subtotal: 3840);
      final warnings = validator.validateLine(
        input,
        history: const PurchaseHistorySample(
          typicalQuantity: 12,
          lastUnitCostCents: 320,
        ),
      );
      expect(warnings.any((w) => w.code == 'quantity_anomaly'), isTrue);
      expect(warnings.any((w) => w.code == 'line_math_mismatch'), isTrue);
      expect(input.quantity, 72);
      expect(input.lineSubtotalCents, 3840);
    });

    test('flags 30 percent plus cost change', () {
      final warnings = validator.validateLine(
        line(cost: 820, subtotal: 9840),
        history: const PurchaseHistorySample(
          typicalQuantity: 12,
          lastUnitCostCents: 320,
        ),
      );
      expect(warnings.any((w) => w.code == 'cost_anomaly'), isTrue);
    });

    test('flags invoice total mismatch above RM0.10', () {
      final draft = PurchaseDraft(
        draftId: 'd1',
        supplierId: 's1',
        supplierName: 'Supplier',
        lines: [line()],
        invoiceTotalCents: 4000,
        createdAt: DateTime(2026, 9, 6).toIso8601String(),
        createdBy: 'admin',
      );
      final warnings = validator.validateDraft(draft);
      expect(warnings.any((w) => w.code == 'invoice_total_mismatch'), isTrue);
    });
  });

  group('OCR purchase transaction', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository posRepo;
    late PurchaseOcrRepository ocrRepo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_ocr_test_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      posRepo = PosRepository(database: database);
      ocrRepo = PurchaseOcrRepository(posRepo);
      final db = await database.db;
      await db.insert('suppliers', {
        'id': 's1',
        'name': 'ABC Trading',
        'phone': '',
        'email': '',
        'notes': '',
        'is_deleted': 0,
      });
      await db.insert(
        'products',
        const Product(
          id: 'p1',
          nameZh: 'Coca Cola',
          nameEn: 'Coca Cola',
          sku: 'CC',
          barcode: '955000000001',
          priceCents: 450,
          costCents: 300,
          stock: 10,
          unit: 'pcs',
          category: 'Drink',
        ).toMap(),
      );
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    test('commit is atomic and reversal restores stock once', () async {
      var draft = PurchaseDraft(
        draftId: 'd1',
        supplierId: 's1',
        supplierName: 'ABC Trading',
        invoiceNo: 'INV-1',
        invoiceDate: '2026-09-06',
        ocrRawText: 'Coca Cola 5 PCS 3.20 16.00',
        lines: const [
          PurchaseDraftLine(
            id: 'l1',
            rawText: 'Coca Cola 5 PCS 3.20 16.00',
            rawProductName: 'Coca Cola',
            matchedProductId: 'p1',
            matchedProductName: 'Coca Cola',
            matchConfidence: 1,
            quantity: 5,
            unit: 'PCS',
            unitCostCents: 320,
            lineSubtotalCents: 1600,
            originalQuantity: 5,
            originalUnitCostCents: 320,
            originalLineSubtotalCents: 1600,
          ),
        ],
        invoiceTotalCents: 1600,
        createdAt: DateTime(2026, 9, 6).toIso8601String(),
        createdBy: 'admin',
      );
      draft = await ocrRepo.validateDraft(draft);
      final purchaseId = await ocrRepo.commitDraft(draft, operator: 'admin');

      final afterCommit = await posRepo.getProduct('p1');
      expect(afterCommit!.stock, 15);
      expect(afterCommit.costCents, 320);
      final alias = await ocrRepo.lookupAlias('s1', 'Coca Cola');
      expect(alias?['product_id'], 'p1');

      await ocrRepo.reversePurchase(
        purchaseId: purchaseId,
        operator: 'admin',
        reason: 'OCR error',
      );
      final afterReverse = await posRepo.getProduct('p1');
      expect(afterReverse!.stock, 10);
      expect(afterReverse.costCents, 300);

      await ocrRepo.reversePurchase(
        purchaseId: purchaseId,
        operator: 'admin',
        reason: 'OCR error',
      );
      final afterSecond = await posRepo.getProduct('p1');
      expect(afterSecond!.stock, 10);

      final db = await database.db;
      expect(
        Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM purchase_reversals WHERE purchase_id=?',
          [purchaseId],
        )),
        1,
      );
    });
  });
}
