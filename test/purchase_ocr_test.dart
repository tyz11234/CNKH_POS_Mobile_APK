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

    test('parses thousands separators consistently', () {
      final draft = parser.parse(
        '''ABC Trading Sdn Bhd
Invoice No: BIG-1
Industrial Valve 2 PCS RM 1,234.56 RM 2,469.12
Discount RM 1,000.00
SST RM 123.45
Grand Total RM 1,592.57''',
        draftId: 'money-1',
        createdBy: 'admin',
      );
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.unitCostCents, 123456);
      expect(draft.lines.single.lineSubtotalCents, 246912);
      expect(draft.discountCents, 100000);
      expect(draft.taxCents, 12345);
      expect(draft.invoiceTotalCents, 159257);
      expect(parser.parseMoneyCents('RM12,345.67'), 1234567);
      expect(parser.parseMoneyCents('1,234.56'), 123456);
      expect(parser.parseMoneyCents('1.234,56'), 123456);
      expect(parser.parseMoneyCents('RM 10,999.99'), 1099999);
      expect(parser.parseMoneyCents('12..50'), isNull);
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

    test('does not auto-trust conflicting size specifications', () {
      const products = [
        Product(
          id: '500',
          nameZh: 'Coca Cola 500ML',
          nameEn: 'Coca Cola 500ML',
          priceCents: 250,
        ),
        Product(
          id: '1500',
          nameZh: 'Coca Cola 1.5L',
          nameEn: 'Coca Cola 1.5L',
          priceCents: 450,
        ),
      ];
      final result = matcher.rank('Coca Cola 500ML', products);
      expect(result.first.product.id, '500');
      final wrong = result.where((c) => c.product.id == '1500');
      expect(wrong.every((c) => c.confidence < 0.82), isTrue);
    });
  });

  group('OCR validation', () {
    const validator = PurchaseValidationService();

    PurchaseDraftLine line({
      double qty = 12,
      int cost = 320,
      int subtotal = 3840,
      double conversion = 1,
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
          conversionFactor: conversion,
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

    test('rejects zero, negative, NaN and infinite conversion factors', () {
      for (final conversion in [0.0, -24.0, double.nan, double.infinity]) {
        final warnings = validator.validateLine(line(conversion: conversion));
        final invalid = warnings.where((w) => w.code == 'invalid_conversion_factor');
        expect(invalid, isNotEmpty);
        expect(invalid.first.level, PurchaseWarningLevel.error);
      }
    });

    test('uses converted base units for history anomalies', () {
      final warnings = validator.validateLine(
        line(qty: 5, cost: 4800, subtotal: 24000, conversion: 24),
        history: const PurchaseHistorySample(
          typicalQuantity: 120,
          lastUnitCostCents: 200,
        ),
      );
      expect(warnings.any((w) => w.code == 'quantity_anomaly'), isFalse);
      expect(warnings.any((w) => w.code == 'cost_anomaly'), isFalse);
    });

    test('flags 30 percent plus base-unit cost change', () {
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

    PurchaseDraft draft({
      required String draftId,
      String invoiceNo = 'INV-1',
      double qty = 5,
      double conversion = 1,
      int unitCostCents = 320,
    }) {
      final subtotal = (qty * unitCostCents).round();
      return PurchaseDraft(
        draftId: draftId,
        supplierId: 's1',
        supplierName: 'ABC Trading',
        invoiceNo: invoiceNo,
        invoiceDate: '2026-09-06',
        ocrRawText: 'Coca Cola $qty PCS',
        lines: [
          PurchaseDraftLine(
            id: 'line-$draftId',
            rawText: 'Coca Cola $qty PCS',
            rawProductName: 'Coca Cola',
            matchedProductId: 'p1',
            matchedProductName: 'Coca Cola',
            matchConfidence: 1,
            quantity: qty,
            unit: 'PCS',
            unitCostCents: unitCostCents,
            lineSubtotalCents: subtotal,
            originalQuantity: qty,
            originalUnitCostCents: unitCostCents,
            originalLineSubtotalCents: subtotal,
            conversionFactor: conversion,
          ),
        ],
        invoiceTotalCents: subtotal,
        createdAt: DateTime(2026, 9, 6).toIso8601String(),
        createdBy: 'admin',
      );
    }

    test('commit is atomic and reversal restores stock once', () async {
      final input = await ocrRepo.validateDraft(draft(draftId: 'd1'));
      final purchaseId = await ocrRepo.commitDraft(input, operator: 'admin');

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

    test('same draft commit twice changes stock only once', () async {
      final input = await ocrRepo.validateDraft(draft(draftId: 'same-draft'));
      final first = await ocrRepo.commitDraft(input, operator: 'admin');
      final second = await ocrRepo.commitDraft(input, operator: 'admin');
      expect(second, first);
      expect((await posRepo.getProduct('p1'))!.stock, 15);
      final db = await database.db;
      expect(
        Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM purchases WHERE draft_id=?',
          ['same-draft'],
        )),
        1,
      );
    });

    test('same supplier and invoice number is blocked by default', () async {
      await ocrRepo.commitDraft(
        await ocrRepo.validateDraft(draft(draftId: 'first', invoiceNo: 'INV-DUP')),
        operator: 'admin',
      );
      expect(
        () => ocrRepo.commitDraft(
          draft(draftId: 'second', invoiceNo: 'inv-dup'),
          operator: 'admin',
        ),
        throwsA(isA<StateError>()),
      );
      expect((await posRepo.getProduct('p1'))!.stock, 15);
    });

    test('commit rejects invalid conversion at repository boundary', () async {
      expect(
        () => ocrRepo.commitDraft(
          draft(draftId: 'bad-conversion', conversion: 0),
          operator: 'admin',
        ),
        throwsA(isA<StateError>()),
      );
      expect((await posRepo.getProduct('p1'))!.stock, 10);
    });

    test('reverse is blocked after a later stock movement', () async {
      final purchaseId = await ocrRepo.commitDraft(
        await ocrRepo.validateDraft(draft(draftId: 'later-move')),
        operator: 'admin',
      );
      final db = await database.db;
      final later = DateTime.now().add(const Duration(seconds: 1)).toIso8601String();
      await db.rawUpdate('UPDATE products SET stock=stock-1 WHERE id=?', ['p1']);
      await db.insert('stock_moves', {
        'id': AppDatabase.newId(),
        'product_id': 'p1',
        'change': -1,
        'reason': 'sale',
        'created_at': later,
        'operator': 'admin',
        'notes': 'later sale',
      });

      expect(
        () => ocrRepo.reversePurchase(
          purchaseId: purchaseId,
          operator: 'admin',
          reason: 'OCR error',
        ),
        throwsA(isA<StateError>()),
      );
      expect((await posRepo.getProduct('p1'))!.stock, 14);
      final purchase = await ocrRepo.getPurchase(purchaseId);
      expect(purchase?['reversed'], 0);
    });
  });
}
