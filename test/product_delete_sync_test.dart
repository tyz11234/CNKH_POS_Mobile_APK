import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('product soft delete hides sale lookup and queues tombstone without deleting history row', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-product-delete-');
    final database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);

    try {
      final db = await database.db;
      await db.insert(
        'settings',
        {'key': 'lan_sync_host', 'value': 'http://127.0.0.1:8765'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      const product = Product(
        id: 'product-delete-1',
        nameZh: '历史商品',
        nameEn: 'History Product',
        sku: 'DEL-001',
        barcode: '1234567890128',
        priceCents: 1290,
        costCents: 900,
        stock: 7,
      );
      await repo.upsertProduct(product);
      expect(await repo.findByBarcodeOrSku(product.barcode), isNotNull);

      await repo.softDeleteProduct(product.id);

      expect(await repo.findByBarcodeOrSku(product.barcode), isNull);
      expect(
        (await repo.searchProducts('')).where((p) => p.id == product.id),
        isEmpty,
      );

      final stored = await db.query(
        'products',
        where: 'id=?',
        whereArgs: [product.id],
      );
      expect(stored, hasLength(1));
      expect(stored.single['is_deleted'], 1);
      expect(stored.single['stock'], 7.0);
      expect(stored.single['barcode'], product.barcode);

      final queued = await db.query(
        'sync_outbox',
        where: 'kind=? AND entity_id=?',
        whereArgs: ['product_upsert', product.id],
        orderBy: 'seq ASC',
      );
      expect(queued.length, 2);
      final payload = jsonDecode(queued.last['payload_json'] as String) as Map;
      final row = Map<String, dynamic>.from(payload['row'] as Map);
      expect(row['id'], product.id);
      expect(row['is_deleted'], 1);
      expect(row['barcode'], product.barcode);
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
