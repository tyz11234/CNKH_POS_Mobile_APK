import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('approved local duplicate is marked for Desktop cross-device guard', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-dup-outbox-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await db.insert(
        'settings',
        {'key': 'lan_sync_host', 'value': 'http://127.0.0.1:8787'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert('purchase_drafts', {
        'id': 'draft-2',
        'supplier_id': 'supplier-local',
        'supplier_name': 'ABC Trading',
        'invoice_no': 'INV-001',
        'invoice_date': '2026-09-06',
        'created_at': '2026-09-06T10:00:00Z',
        'created_by': 'admin',
      });
      await db.insert('purchases', {
        'id': 'purchase-1',
        'purchase_no': 'PO-1',
        'supplier_id': 'supplier-local',
        'supplier_name': 'ABC Trading',
        'purchased_at': '2026-09-06T09:00:00Z',
        'total_cents': 1000,
        'lines_json': '[]',
        'notes': '',
        'invoice_no': 'INV-001',
        'invoice_date': '2026-09-06',
        'reversed': 0,
      });

      await queueMutation(db, 'purchase', 'purchase-2', {
        'id': 'purchase-2',
        'supplier_id': 'supplier-remote',
        'supplier_name': 'ABC Trading',
        'invoice_no': 'INV-001',
        'source': 'ocr',
        'draft_id': 'draft-2',
      });

      final rows = await db.query(
        'sync_outbox',
        where: "kind='purchase' AND entity_id=?",
        whereArgs: ['purchase-2'],
        limit: 1,
      );
      expect(rows, hasLength(1));
      final payload = jsonDecode(rows.single['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload['duplicate_override'], isTrue);
      expect(payload['duplicate_override_reason'], isNotEmpty);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('normal purchase is not marked as duplicate override', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-normal-outbox-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await db.insert(
        'settings',
        {'key': 'lan_sync_host', 'value': 'http://127.0.0.1:8787'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert('purchase_drafts', {
        'id': 'draft-new',
        'supplier_id': 'supplier-local',
        'supplier_name': 'ABC Trading',
        'invoice_no': 'INV-NEW',
        'invoice_date': '2026-09-06',
        'created_at': '2026-09-06T10:00:00Z',
        'created_by': 'staff',
      });

      await queueMutation(db, 'purchase', 'purchase-new', {
        'id': 'purchase-new',
        'supplier_id': 'supplier-remote',
        'supplier_name': 'ABC Trading',
        'invoice_no': 'INV-NEW',
        'source': 'ocr',
        'draft_id': 'draft-new',
      });

      final rows = await db.query(
        'sync_outbox',
        where: "kind='purchase' AND entity_id=?",
        whereArgs: ['purchase-new'],
        limit: 1,
      );
      final payload = jsonDecode(rows.single['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload.containsKey('duplicate_override'), isFalse);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
