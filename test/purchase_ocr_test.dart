import 'dart:convert';
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
      expect(
        matcher.normalizeName('COCA C0LA'),
        matcher.normalizeName('Coca Cola'),
      );
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
          sku: 'CC500',
          barcode: '9550000000500',
          priceCents: 250,
        ),
        Product(
          id: '1500',
          nameZh: 'Coca Cola 1.5L',
          nameEn: 'Coca Cola 1.5L',
          sku: 'CC1500',
          barcode: '9550000001507',
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
        final invalid = warnings.where(
          (w) => w.code == 'invalid_conversion_factor',
        );
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
      String unit = 'PCS',
      String rawName = 'Coca Cola',
      String? matchedProductId = 'p1',
      bool userModified = false,
    }) {
      final subtotal = (qty * unitCostCents).round();
      return PurchaseDraft(
        draftId: draftId,
        supplierId: 's1',
        supplierName: 'ABC Trading',
        invoiceNo: invoiceNo,
        invoiceDate: '2026-09-06',
        ocrRawText: '$rawName $qty $unit',
        lines: [
          PurchaseDraftLine(
            id: 'line-$draftId',
            rawText: '$rawName $qty $unit',
            rawProductName: rawName,
            matchedProductId: matchedProductId,
            matchedProductName: matchedProductId == null ? '' : 'Coca Cola',
            matchConfidence: matchedProductId == null ? 0 : 1,
            quantity: qty,
            unit: unit,
            unitCostCents: unitCostCents,
            lineSubtotalCents: subtotal,
            originalQuantity: qty,
            originalUnitCostCents: unitCostCents,
            originalLineSubtotalCents: subtotal,
            conversionFactor: conversion,
            userModified: userModified,
          ),
        ],
        invoiceTotalCents: subtotal,
        createdAt: DateTime(2026, 9, 6).toIso8601String(),
        createdBy: 'admin',
      );
    }

    test(
      'reuses supplier unit conversion and cost in next OCR draft and outbox',
      () async {
        final first = draft(
          draftId: 'case-first',
          invoiceNo: 'INV-CASE-1',
          qty: 2,
          unit: 'Carton',
          conversion: 12,
          unitCostCents: 12000,
        );
        await ocrRepo.commitDraft(first, operator: 'admin');
        final nextOcr = draft(
          draftId: 'case-second',
          invoiceNo: 'INV-CASE-2',
          qty: 2,
          unit: 'carton',
          unitCostCents: 12000,
          matchedProductId: null,
        );
        final prepared = await ocrRepo.prepareDraft(nextOcr);
        expect(prepared.lines.single.matchedProductId, 'p1');
        expect(prepared.lines.single.conversionFactor, 12);
        expect(prepared.lines.single.stockQuantity, 24);
        expect(prepared.lines.single.baseUnitCostCents, 1000);
        expect(
          prepared.lines.single.warnings.any(
            (warning) => warning.code == 'supplier_memory_unit_conflict',
          ),
          isFalse,
        );

        final purchaseId = await ocrRepo.commitDraft(
          prepared,
          operator: 'admin',
        );
        expect((await posRepo.getProduct('p1'))!.stock, 58);
        expect((await posRepo.getProduct('p1'))!.costCents, 1000);
        final outbox = (await (await database.db).query(
          'sync_outbox',
          where: "kind='purchase' AND entity_id=?",
          whereArgs: [purchaseId],
        )).single;
        final payload = jsonDecode(outbox['payload_json'] as String) as Map;
        final remoteLine = (payload['lines'] as List).single as Map;
        expect(remoteLine['qty'], 24);
        expect(remoteLine['conversionFactor'], 12);
        expect(remoteLine['unitCostCents'], 1000);
      },
    );

    test(
      'edited alias is reused, unit conflict blocks commit, manual choice wins',
      () async {
        await ocrRepo.commitDraft(
          draft(
            draftId: 'alias-seed',
            invoiceNo: 'INV-ALIAS-SEED',
            qty: 1,
            unit: 'Carton',
            conversion: 12,
            unitCostCents: 12000,
          ),
          operator: 'admin',
        );
        final alias = (await ocrRepo.listAliases(supplierId: 's1')).single;
        await ocrRepo.updateAlias(
          aliasId: alias['id'] as String,
          productId: 'p1',
          unit: 'Case',
          conversionFactor: 24,
        );

        final editedAliasDraft = await ocrRepo.prepareDraft(
          draft(
            draftId: 'alias-edited',
            invoiceNo: 'INV-ALIAS-EDITED',
            qty: 2,
            unit: 'case',
            unitCostCents: 24000,
            matchedProductId: null,
          ),
        );
        expect(editedAliasDraft.lines.single.conversionFactor, 24);

        final conflict = await ocrRepo.prepareDraft(
          draft(
            draftId: 'alias-conflict',
            invoiceNo: 'INV-ALIAS-CONFLICT',
            qty: 2,
            unit: 'box',
            unitCostCents: 24000,
            matchedProductId: null,
          ),
        );
        expect(
          conflict.lines.single.warnings.any(
            (warning) => warning.code == 'supplier_memory_unit_conflict',
          ),
          isTrue,
        );
        await expectLater(
          ocrRepo.commitDraft(conflict, operator: 'admin'),
          throwsA(isA<StateError>()),
        );

        final manual = await ocrRepo.prepareDraft(
          draft(
            draftId: 'alias-manual',
            invoiceNo: 'INV-ALIAS-MANUAL',
            qty: 2,
            unit: 'box',
            conversion: 3,
            unitCostCents: 24000,
            matchedProductId: 'p1',
            userModified: true,
          ),
        );
        expect(manual.lines.single.conversionFactor, 3);
        expect(
          manual.lines.single.warnings.any(
            (warning) => warning.code == 'supplier_memory_unit_conflict',
          ),
          isFalse,
        );
        await ocrRepo.commitDraft(manual, operator: 'admin');
        expect((await posRepo.getProduct('p1'))!.stock, 28);
        expect((await posRepo.getProduct('p1'))!.costCents, 8000);
      },
    );

    test('commit is atomic and reversal restores stock once', () async {
      final input = await ocrRepo.validateDraft(draft(draftId: 'd1'));
      final purchaseId = await ocrRepo.commitDraft(input, operator: 'admin');

      final afterCommit = await posRepo.getProduct('p1');
      expect(afterCommit!.stock, 15);
      expect(afterCommit.costCents, 320);
      final committed = (await (await database.db).query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
      )).single;
      final committedLines =
          jsonDecode(committed['lines_json'] as String) as List;
      expect((committedLines.single as Map)['beforeCostCents'], 300);
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
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM purchase_reversals WHERE purchase_id=?',
            [purchaseId],
          ),
        ),
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
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM purchases WHERE draft_id=?', [
            'same-draft',
          ]),
        ),
        1,
      );
    });

    test('same supplier and invoice number is blocked by default', () async {
      await ocrRepo.commitDraft(
        await ocrRepo.validateDraft(
          draft(draftId: 'first', invoiceNo: 'INV-DUP'),
        ),
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
      final later = DateTime.now()
          .add(const Duration(seconds: 1))
          .toIso8601String();
      await db.rawUpdate('UPDATE products SET stock=stock-1 WHERE id=?', [
        'p1',
      ]);
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
