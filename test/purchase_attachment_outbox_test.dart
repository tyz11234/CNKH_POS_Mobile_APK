import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('OCR original uses an independent durable attachment outbox', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-attachment-outbox-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await db.insert(
        'settings',
        {'key': 'lan_sync_host', 'value': 'http://127.0.0.1:8787'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final original = File('${temp.path}/invoice-original.jpg');
      final bytes = List<int>.generate(4096, (i) => (i * 31) & 0xff);
      await original.writeAsBytes(bytes, flush: true);
      final expectedHash = hex((await Sha256().hash(bytes)).bytes);

      await db.insert('purchase_drafts', {
        'id': 'draft-attach-1',
        'original_image_path': original.path,
        'created_at': '2026-09-06T10:00:00Z',
        'created_by': 'staff',
      });

      await queueMutation(db, 'purchase', 'purchase-attach-1', {
        'id': 'purchase-attach-1',
        'source': 'ocr',
        'draft_id': 'draft-attach-1',
      });

      final outbox = await db.query('sync_outbox', orderBy: 'seq ASC');
      expect(outbox, hasLength(2));
      expect(outbox.first['kind'], 'purchase');
      expect(outbox.last['kind'], 'purchase_attachment');
      expect(outbox.last['entity_id'], 'purchase-attach-1');

      final payload = jsonDecode(outbox.last['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload['attachment_id'], 'purchase-attach-1-invoice-original');
      expect(payload['purchase_id'], 'purchase-attach-1');
      expect(payload['kind'], 'invoice_original');
      expect(payload['content_hash'], expectedHash);
      expect(base64Decode(payload['base64'] as String), bytes);

      await db.insert('purchases', {
        'id': 'purchase-attach-1',
        'purchase_no': 'PO-ATTACH-1',
        'supplier_name': 'ABC',
        'purchased_at': '2026-09-06T10:00:00Z',
        'total_cents': 100,
        'lines_json': '[]',
        'notes': '',
      });
      await db.insert('purchase_attachments', {
        'id': 'local-attachment-row',
        'purchase_id': 'purchase-attach-1',
        'local_path': original.path,
        'kind': 'invoice_original',
        'created_at': '2026-09-06T10:00:00Z',
      });

      final attachmentOutboxId = outbox.last['id'] as String;
      await db.update(
        'sync_outbox',
        {'last_error': 'network timeout'},
        where: 'id=?',
        whereArgs: [attachmentOutboxId],
      );
      var attachment = (await db.query(
        'purchase_attachments',
        where: 'id=?',
        whereArgs: ['local-attachment-row'],
      ))
          .single;
      expect(attachment['sync_status'], 'failed');
      expect(attachment['last_error'], 'network timeout');

      await db.delete(
        'sync_outbox',
        where: 'id=?',
        whereArgs: [attachmentOutboxId],
      );
      attachment = (await db.query(
        'purchase_attachments',
        where: 'id=?',
        whereArgs: ['local-attachment-row'],
      ))
          .single;
      expect(attachment['sync_status'], 'synced');
      expect(attachment['synced_at'], isNotNull);
      expect(attachment['last_error'], '');

      final remaining = await db.query('sync_outbox');
      expect(remaining, hasLength(1));
      expect(remaining.single['kind'], 'purchase');
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
