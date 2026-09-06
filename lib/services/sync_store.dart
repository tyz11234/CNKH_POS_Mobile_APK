import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'sync_role.dart';

Future<String> readSetting(
  DatabaseExecutor db,
  String key, {
  String fallback = '',
}) async {
  final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
  return rows.isEmpty ? fallback : rows.first['value'] as String;
}

Future<String> remoteEntityId(
  DatabaseExecutor db,
  String entity,
  String id,
) async {
  final rows = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND local_id=?',
    whereArgs: [entity, id],
  );
  if (rows.isNotEmpty) return rows.first['remote_id'] as String;
  final prefix = switch (entity) {
    'customer' => 'pc-c-',
    'category' => 'pc-cat-',
    _ => 'pc-',
  };
  return id.startsWith(prefix) ? id.substring(prefix.length) : id;
}

Future<String?> mappedLocalId(
  DatabaseExecutor db,
  String entity,
  Object? id,
) async {
  if (id == null) return null;
  final rows = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND remote_id=?',
    whereArgs: [entity, '$id'],
  );
  return rows.isEmpty ? null : rows.first['local_id'] as String;
}

Future<void> rememberEntityId(
  DatabaseExecutor db,
  String entity,
  Object? remoteId,
  String localId,
) async {
  if (remoteId == null) return;
  final previous = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND local_id=?',
    whereArgs: [entity, localId],
  );
  if (previous.isNotEmpty && previous.first['remote_id'] != '$remoteId') {
    throw StateError('商品或客户关联冲突，请核对重复资料');
  }
  await db.insert('sync_entity_ids', {
    'entity': entity,
    'remote_id': '$remoteId',
    'local_id': localId,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<Map<String, Object?>> _annotateApprovedDuplicatePurchase(
  DatabaseExecutor db,
  Map<String, Object?> purchasePayload,
) async {
  final out = Map<String, Object?>.from(purchasePayload);
  if (out['source']?.toString() != 'ocr') return out;
  final draftId = out['draft_id']?.toString() ?? '';
  if (draftId.isEmpty) return out;

  // commitDraft performs the real duplicate gate before queueMutation. If this
  // transaction has reached the outbox while an older unreversed purchase with
  // the same local Supplier + Invoice already exists, the user has explicitly
  // taken the Admin Force Commit path. Mark the remote mutation so Desktop can
  // apply its own cross-device duplicate gate without rejecting that approved
  // exception. The exact user-entered reason remains in Mobile audit history.
  final draftRows = await db.query(
    'purchase_drafts',
    columns: const ['supplier_id', 'invoice_no'],
    where: 'id=?',
    whereArgs: [draftId],
    limit: 1,
  );
  if (draftRows.isEmpty) return out;
  final supplierId = draftRows.first['supplier_id']?.toString().trim() ?? '';
  final invoiceNo = draftRows.first['invoice_no']?.toString().trim() ?? '';
  if (supplierId.isEmpty || invoiceNo.isEmpty) return out;

  final duplicates = await db.rawQuery(
    '''SELECT id FROM purchases
       WHERE supplier_id=?
         AND lower(trim(invoice_no))=lower(trim(?))
         AND COALESCE(reversed,0)=0
       LIMIT 1''',
    [supplierId, invoiceNo],
  );
  if (duplicates.isEmpty) return out;

  out['duplicate_override'] = true;
  out['duplicate_override_reason'] =
      'Mobile Admin 已二次确认重复 Invoice；详细原因保存在 Mobile Audit。';
  return out;
}

Future<void> _queueOcrOriginalAttachment(
  DatabaseExecutor db,
  String purchaseId,
  Map<String, Object?> purchasePayload,
) async {
  if (purchasePayload['source']?.toString() != 'ocr') return;
  final draftId = purchasePayload['draft_id']?.toString() ?? '';
  if (draftId.isEmpty) return;

  final draftRows = await db.query(
    'purchase_drafts',
    columns: const ['original_image_path'],
    where: 'id=?',
    whereArgs: [draftId],
    limit: 1,
  );
  if (draftRows.isEmpty) return;
  final path = draftRows.first['original_image_path']?.toString() ?? '';
  if (path.isEmpty) return;

  try {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final digest = await Sha256().hash(bytes);
    final attachmentId = '$purchaseId-invoice-original';
    final operationId = AppDatabase.newId();
    await db.insert('sync_outbox', {
      'id': operationId,
      'kind': 'purchase_attachment',
      'entity_id': purchaseId,
      'payload_json': jsonEncode(<String, Object?>{
        'attachment_id': attachmentId,
        'purchase_id': purchaseId,
        'kind': 'invoice_original',
        'filename': file.uri.pathSegments.isEmpty
            ? 'invoice_original'
            : file.uri.pathSegments.last,
        'content_hash': _hex(digest.bytes),
        'base64': base64Encode(bytes),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (_) {
    // The Purchase stays committed. Network retry is handled by sync_outbox
    // once the attachment operation has been prepared successfully.
  }
}

Future<void> queueMutation(
  DatabaseExecutor db,
  String kind,
  String entityId,
  Map<String, Object?> payload,
) async {
  if (isDesktopHost || (await readSetting(db, 'lan_sync_host')).isEmpty) return;
  final effectivePayload = kind == 'purchase'
      ? await _annotateApprovedDuplicatePurchase(db, payload)
      : payload;
  await db.insert('sync_outbox', {
    'id': AppDatabase.newId(),
    'kind': kind,
    'entity_id': entityId,
    'payload_json': jsonEncode(effectivePayload),
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
  if (kind == 'purchase') {
    await _queueOcrOriginalAttachment(db, entityId, effectivePayload);
  }
}

class AsyncMutex {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
