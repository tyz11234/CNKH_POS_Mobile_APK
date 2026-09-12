import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository pagination', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_paging_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    test('101 products page as 50 / 50 / 1 without duplicates', () async {
      final db = await database.db;
      for (var i = 0; i < 101; i++) {
        final id = 'p-${i.toString().padLeft(3, '0')}';
        await db.insert('products', Product(
          id: id,
          nameZh: '商品 ${i.toString().padLeft(3, '0')}',
          nameEn: '',
          sku: 'SKU$i',
          barcode: 'B$i',
          priceCents: 100,
          costCents: 50,
          stock: 1,
          unit: 'pcs',
          category: '测试',
        ).toMap());
      }

      final a = await repo.searchProducts('', limit: 50, offset: 0);
      final b = await repo.searchProducts('', limit: 50, offset: 50);
      final c = await repo.searchProducts('', limit: 50, offset: 100);
      expect([a.length, b.length, c.length], [50, 50, 1]);
      final ids = [...a, ...b, ...c].map((p) => p.id).toList();
      expect(ids.toSet().length, 101);
      expect(await repo.countProducts(''), 101);
    });

    test('customer and supplier page boundaries reach row 51', () async {
      final db = await database.db;
      for (var i = 0; i < 51; i++) {
        final n = i.toString().padLeft(3, '0');
        await db.insert('customers', {
          'id': 'c$n', 'name': 'Customer $n', 'phone': '', 'notes': '', 'is_deleted': 0,
        });
        await db.insert('suppliers', {
          'id': 's$n', 'name': 'Supplier $n', 'phone': '', 'email': '', 'notes': '', 'is_deleted': 0,
        });
      }
      expect((await repo.listCustomers(limit: 50)).length, 50);
      expect((await repo.listCustomers(limit: 50, offset: 50)).single.id, 'c050');
      expect((await repo.listSuppliers(limit: 50)).length, 50);
      expect((await repo.listSuppliers(limit: 50, offset: 50)).single.id, 's050');
    });
  });
}
