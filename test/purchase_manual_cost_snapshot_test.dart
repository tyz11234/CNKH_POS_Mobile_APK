import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('manual duplicate lines atomically keep before-cost and restore it on reverse',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-manual-cost-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    try {
      await repo.upsertProduct(const Product(
        id: 'p1', nameZh: '商品', nameEn: 'Product', sku: 'P1', barcode: '1',
        priceCents: 1000, costCents: 100, stock: 10,
      ));
      await repo.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier',
        lines: const [
          {'productId': 'p1', 'qty': 2, 'unitCostCents': 200},
          {'productId': 'p1', 'qty': 3, 'unitCostCents': 300},
        ],
        totalCents: 1300,
        operator: 'admin',
      );
      final db = await database.db;
      final purchase = (await db.query('purchases')).single;
      final lines = jsonDecode(purchase['lines_json'] as String) as List;
      expect(lines.map((line) => (line as Map)['beforeCostCents']), [100, 100]);
      expect((await repo.getProduct('p1'))!.stock, 15);
      expect((await repo.getProduct('p1'))!.costCents, 300);

      await PurchaseOcrRepository(repo).reversePurchase(
        purchaseId: purchase['id'] as String,
        operator: 'admin',
        reason: 'manual correction',
      );
      expect((await repo.getProduct('p1'))!.stock, 10);
      expect((await repo.getProduct('p1'))!.costCents, 100);
      expect((await db.query('purchases')).single['reversed'], 1);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('later cost change and legacy rows without snapshots are never guessed over',
      () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-cost-legacy-');
    final database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    final repo = PosRepository(database: database);
    try {
      final db = await database.db;
      await repo.upsertProduct(const Product(
        id: 'changed-cost', nameZh: '新商品', nameEn: 'New Product', sku: 'P2',
        barcode: '2', priceCents: 1000, costCents: 100, stock: 10,
      ));
      await repo.createPurchase(
        supplierId: 's1', supplierName: 'Supplier',
        lines: const [{'productId': 'changed-cost', 'qty': 2, 'unitCostCents': 250}],
        totalCents: 500, operator: 'admin',
      );
      final changedPurchase = (await db.query('purchases')).single;
      await db.update('products', {'cost_cents': 400},
          where: 'id=?', whereArgs: const ['changed-cost']);
      await PurchaseOcrRepository(repo).reversePurchase(
        purchaseId: changedPurchase['id'] as String,
        operator: 'admin',
        reason: 'cost changed later',
      );
      expect((await repo.getProduct('changed-cost'))!.stock, 10);
      expect((await repo.getProduct('changed-cost'))!.costCents, 400);

      await repo.upsertProduct(const Product(
        id: 'legacy-cost', nameZh: '旧商品', nameEn: 'Legacy Product', sku: 'P3',
        barcode: '3', priceCents: 1000, costCents: 50, stock: 5,
      ));
      await repo.createPurchase(
        supplierId: 's1', supplierName: 'Supplier',
        lines: const [{'productId': 'legacy-cost', 'qty': 1, 'unitCostCents': 100}],
        totalCents: 100, operator: 'admin',
      );
      final legacyPurchase = (await db.query(
        'purchases', where: "lines_json LIKE '%legacy-cost%'",
      )).single;
      final oldLines = jsonDecode(legacyPurchase['lines_json'] as String) as List;
      final withoutSnapshot = <Map<String, Object?>>[
        for (final raw in oldLines)
          Map<String, Object?>.from(raw as Map)..remove('beforeCostCents'),
      ];
      await db.update('purchases', {'lines_json': jsonEncode(withoutSnapshot)},
          where: 'id=?', whereArgs: [legacyPurchase['id']]);
      await PurchaseOcrRepository(repo).reversePurchase(
        purchaseId: legacyPurchase['id'] as String,
        operator: 'admin',
        reason: 'legacy no snapshot',
      );
      expect((await repo.getProduct('legacy-cost'))!.stock, 5);
      // An old row cannot reveal its true pre-purchase cost. Preserve the
      // current value instead of inventing a snapshot from today's catalog.
      expect((await repo.getProduct('legacy-cost'))!.costCents, 100);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
