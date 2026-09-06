import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/models/purchase_ocr.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OCR invoice image lifecycle', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository posRepo;
    late PurchaseOcrRepository ocrRepo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_ocr_images_');
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
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<PurchaseDraft> draft(String id) async {
      final original = File('${dir.path}/$id-original.jpg');
      final preview = File('${dir.path}/$id-preview.jpg');
      await original.writeAsBytes([1, 2, 3, 4], flush: true);
      await preview.writeAsBytes([9, 8, 7], flush: true);
      return PurchaseDraft(
        draftId: id,
        supplierId: 's1',
        supplierName: 'ABC Trading',
        invoiceNo: 'INV-$id',
        invoiceDate: '2026-09-06',
        imagePath: preview.path,
        originalImagePath: original.path,
        ocrRawText: 'Coca Cola 5 PCS',
        lines: [
          PurchaseDraftLine(
            id: 'line-$id',
            rawText: 'Coca Cola 5 PCS',
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
            conversionFactor: 1,
          ),
        ],
        invoiceTotalCents: 1600,
        createdAt: DateTime.now().toIso8601String(),
        createdBy: 'admin',
      );
    }

    test('save/load keeps original and preview as separate paths', () async {
      final input = await draft('save-load');
      await ocrRepo.saveDraft(input);
      final loaded = await ocrRepo.loadDraft(input.draftId);
      expect(loaded, isNotNull);
      expect(loaded!.originalImagePath, input.originalImagePath);
      expect(loaded.imagePath, input.imagePath);
      expect(loaded.originalImagePath, isNot(loaded.imagePath));
      expect(await File(loaded.originalImagePath).exists(), isTrue);
      expect(await File(loaded.imagePath).exists(), isTrue);
    });

    test('deleting uncommitted draft removes both owned image files', () async {
      final input = await draft('delete-draft');
      await ocrRepo.saveDraft(input);
      await ocrRepo.deleteDraft(input.draftId);

      expect(await File(input.originalImagePath).exists(), isFalse);
      expect(await File(input.imagePath).exists(), isFalse);
      expect(await ocrRepo.loadDraft(input.draftId), isNull);
    });

    test('commit retains original and preview and registers attachments', () async {
      final input = await draft('commit-images');
      final checked = await ocrRepo.validateDraft(input);
      final purchaseId = await ocrRepo.commitDraft(checked, operator: 'admin');

      expect(await File(input.originalImagePath).exists(), isTrue);
      expect(await File(input.imagePath).exists(), isTrue);
      final db = await database.db;
      final attachments = await db.query(
        'purchase_attachments',
        where: 'purchase_id=?',
        whereArgs: [purchaseId],
        orderBy: 'kind ASC',
      );
      expect(attachments, hasLength(2));
      expect(
        attachments.map((r) => r['kind']).toSet(),
        {'invoice_original', 'invoice_preview'},
      );
      final original = attachments.firstWhere(
        (r) => r['kind'] == 'invoice_original',
      );
      expect(original['sync_status'], 'pending');
      final preview = attachments.firstWhere(
        (r) => r['kind'] == 'invoice_preview',
      );
      expect(preview['sync_status'], 'local_only');
    });

    test('committed draft cannot be deleted as an uncommitted draft', () async {
      final input = await draft('commit-protect');
      await ocrRepo.commitDraft(
        await ocrRepo.validateDraft(input),
        operator: 'admin',
      );
      expect(
        () => ocrRepo.deleteDraft(input.draftId),
        throwsA(isA<StateError>()),
      );
      expect(await File(input.originalImagePath).exists(), isTrue);
      expect(await File(input.imagePath).exists(), isTrue);
    });
  });
}
