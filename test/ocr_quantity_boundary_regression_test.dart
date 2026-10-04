import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/models/purchase_ocr.dart';
import 'package:cnkh_pos_mobile/screens/admin/purchase_ocr_screen.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_validation_service.dart';

const _line = PurchaseDraftLine(
  id: 'line',
  rawText: 'OCR product 1 PCS 1.00 1.00',
  rawProductName: 'OCR product',
  matchedProductId: 'ocr',
  matchedProductName: 'OCR product',
  matchConfidence: 1,
  quantity: 1,
  unitCostCents: 100,
  lineSubtotalCents: 100,
);

void main() {
  for (final invalidLine in [
    _line.copyWith(quantity: 1e308),
    _line.copyWith(quantity: 1e100),
    _line.copyWith(conversionFactor: 1e-308),
  ]) {
    test(
      'OCR validator blocks money outside supported cents: qty=${invalidLine.quantity} conversion=${invalidLine.conversionFactor}',
      () {
        final warnings = const PurchaseValidationService().validateLine(
          invalidLine,
          history: const PurchaseHistorySample(lastUnitCostCents: 100),
        );
        expect(
          warnings.any(
            (warning) => warning.level == PurchaseWarningLevel.error,
          ),
          isTrue,
        );
      },
    );
  }

  for (final scenario in [
    ('数量 / Qty', '1e308'),
    ('数量 / Qty', '1e100'),
    ('换算倍率 / Conversion', '1e-308'),
  ]) {
    testWidgets(
      'OCR line editor rejects ${scenario.$1}=${scenario.$2} before changing the saved draft or stock',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppDatabase.ensureFfi();
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('ocr-qty-'),
        ))!;
        final database = AppDatabase.forTesting(
          '${dir.path}/pos.db',
          seed: false,
        );
        final repo = PosRepository(database: database);
        final ocr = PurchaseOcrRepository(repo);
        const channel = MethodChannel('google_mlkit_text_recognizer');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          await database.close();
          await dir.delete(recursive: true);
        });
        await tester.runAsync(() async {
          await repo.upsertProduct(
            const Product(
              id: 'ocr',
              nameZh: 'OCR product',
              nameEn: 'OCR product',
              sku: 'OCR',
              barcode: 'OCR',
              priceCents: 100,
              costCents: 100,
              stock: 5,
            ),
          );
          await repo.upsertSupplier(
            const Supplier(id: 'supplier', name: 'Supplier'),
          );
          await ocr.saveDraft(
            PurchaseDraft(
              draftId: 'draft',
              supplierId: 'supplier',
              supplierName: 'Supplier',
              lines: const [_line],
              invoiceTotalCents: 100,
              createdAt: '2026-10-03T00:00:00',
              createdBy: 'admin',
            ),
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: PurchaseOcrScreen(
              repo: repo,
              user: const AppUser(username: 'admin', role: AppRole.admin),
              draftId: 'draft',
            ),
          ),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (find.byIcon(Icons.edit_outlined).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        final edit = find.byIcon(Icons.edit_outlined);
        expect(edit, findsOneWidget);
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final qty = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == scenario.$1,
        );
        await tester.ensureVisible(qty);
        await tester.enterText(qty, scenario.$2);
        await tester.tap(find.text('保存'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('核对商品 / Review line'), findsOneWidget);
        final saved = (await tester.runAsync(() => ocr.loadDraft('draft')))!;
        expect(saved.lines.single.quantity, 1);
        final invalidLine = scenario.$1 == '数量 / Qty'
            ? _line.copyWith(quantity: double.parse(scenario.$2))
            : _line.copyWith(conversionFactor: double.parse(scenario.$2));
        await tester.runAsync(
          () => expectLater(
            ocr.commitDraft(
              saved.copyWith(lines: [invalidLine]),
              operator: 'admin',
            ),
            throwsStateError,
          ),
        );
        expect(await tester.runAsync(() => repo.listPurchases()), isEmpty);
        expect((await tester.runAsync(() => repo.getProduct('ocr')))!.stock, 5);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
