import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/screens/admin/admin_hub_legacy.dart';
import 'package:cnkh_pos_mobile/screens/admin/enhanced_purchases_page.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_invoice_parser.dart';

class _Repository extends PosRepository {
  int closingSaves = 0;
  @override
  Future<Map<String, int>> dashboardToday({String? businessDate}) async => {
    'cash': 0,
  };
  @override
  Future<List<Map<String, Object?>>> listClosings({
    int? limit,
    int offset = 0,
  }) async => [];
  @override
  Future<void> saveDailyClosing({
    String? businessDate,
    required int openingCashCents,
    required int countedCashCents,
    int? systemCashCents,
    required String closedBy,
    String notes = '',
  }) async {
    closingSaves++;
  }
}

class _PurchaseRepository extends PosRepository {
  _PurchaseRepository({required super.database});
  bool purchaseCompleted = false;

  @override
  Future<void> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<Map<String, Object?>> lines,
    required int totalCents,
    required String operator,
    String notes = '',
  }) async {
    await super.createPurchase(
      supplierId: supplierId,
      supplierName: supplierName,
      lines: lines,
      totalCents: totalCents,
      operator: operator,
      notes: notes,
    );
    purchaseCompleted = true;
  }
}

void main() {
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  test(
    'invoice amounts outside exact supported cents are rejected, not saturated',
    () {
      final huge = '1${'0' * 100}';
      expect(const PurchaseInvoiceParser().parseMoneyCents(huge), isNull);
      expect(const PurchaseInvoiceParser().parseMoneyCents('1,234.56'), 123456);
    },
  );
  testWidgets('daily close rejects finite huge amounts before persistence', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: DailyClosePage(
          repo: repo,
          user: const AppUser(username: 'admin', role: AppRole.admin),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final opening = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '开档现金 RM',
    );
    await tester.enterText(opening, '1e100');
    await tester.tap(find.text('保存日结'));
    await tester.pumpAndSettle();
    expect(repo.closingSaves, 0);
    expect(tester.takeException(), isNull);
  });
  for (final scenario in [
    ('1e100', '保存', false),
    ('1', '保存', true),
    ('1', '取消', false),
  ]) {
    testWidgets(
      'manual purchase quantity=${scenario.$1} action=${scenario.$2} keeps correct data and lifecycle',
      (tester) async {
        AppDatabase.ensureFfi();
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('purchase-boundary-'),
        ))!;
        final database = AppDatabase.forTesting(
          '${dir.path}/pos.db',
          seed: false,
        );
        final repo = _PurchaseRepository(database: database);
        addTearDown(() async {
          await database.close();
          await dir.delete(recursive: true);
        });
        await tester.runAsync(() async {
          await repo.upsertProduct(
            const Product(
              id: 'purchase',
              nameZh: 'Purchase product',
              nameEn: 'Purchase',
              sku: 'PURCHASE',
              barcode: 'PURCHASE',
              priceCents: 100,
              costCents: 100,
              stock: 5,
            ),
          );
          await repo.upsertSupplier(
            const Supplier(id: 'supplier', name: 'Supplier'),
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: EnhancedPurchasesPage(
              repo: repo,
              user: const AppUser(username: 'admin', role: AppRole.admin),
            ),
          ),
        );
        await flush(tester);
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动进货'));
        await flush(tester);
        final quantity = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '数量',
        );
        await tester.enterText(quantity, scenario.$1);
        await tester.tap(find.text(scenario.$2));
        await tester.pumpAndSettle();
        if (scenario.$3) {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (!repo.purchaseCompleted && DateTime.now().isBefore(deadline)) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(
            repo.purchaseCompleted,
            isTrue,
            reason:
                'the real purchase transaction must finish before reading its data',
          );
        }
        await flush(tester);
        expect(
          await tester.runAsync(() => repo.listPurchases()),
          scenario.$3 ? hasLength(1) : isEmpty,
        );
        expect(
          (await tester.runAsync(() => repo.getProduct('purchase')))!.stock,
          scenario.$3 ? 6 : 5,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('reorder NaN never commits a partial product update', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('reorder-boundary-');
    final db = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: db);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    const product = Product(
      id: 'finite',
      nameZh: 'Finite',
      nameEn: 'Finite',
      sku: 'FINITE',
      barcode: 'FINITE',
      priceCents: 100,
      stock: 5,
      reorderLevel: 2,
    );
    await repo.upsertProduct(product);
    await expectLater(
      repo.upsertProduct(
        product.copyWith(reorderLevel: double.nan),
        original: product,
      ),
      throwsA(anything),
    );
    expect((await repo.getProduct(product.id))!.reorderLevel, 2);
  });
}
