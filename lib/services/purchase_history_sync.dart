import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import 'pos_repository.dart';
import 'sync_store.dart';

class PurchaseHistoryPullResult {
  const PurchaseHistoryPullResult({
    required this.supported,
    required this.changed,
    this.message = '',
  });

  final bool supported;
  final int changed;
  final String message;
}

/// Mirrors Desktop purchase history to Mobile without touching product stock.
///
/// Catalog stock remains authoritative. This sync only writes purchase history,
/// maps Desktop supplier/product IDs to the Mobile IDs, and mirrors reversal
/// metadata. It deliberately creates no stock movement and never updates product
/// stock/cost, so reconnect/retry cannot add stock a second time.
class PurchaseHistorySync {
  PurchaseHistorySync(
    this.repo, {
    AppDatabase? database,
    http.Client? client,
  })  : _db = database ?? repo.database,
        _client = client ?? http.Client();

  final PosRepository repo;
  final AppDatabase _db;
  final http.Client _client;

  Future<PurchaseHistoryPullResult> pullFromSavedDesktop({
    bool capabilityKnown = false,
  }) async {
    final base = (await repo.getSetting('lan_sync_host')).trim();
    if (base.isEmpty) {
      return const PurchaseHistoryPullResult(
        supported: false,
        changed: 0,
        message: 'not paired',
      );
    }
    final token = (await repo.getSetting('lan_sync_token')).trim();
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token.isNotEmpty) headers['X-CNKH-Token'] = token;

    if (!capabilityKnown) {
      final health = await _client
          .get(Uri.parse('$normalized/api/v1/health'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (health.statusCode < 200 || health.statusCode >= 300) {
        throw StateError('Purchase History health ${health.statusCode}');
      }
      final healthBody = jsonDecode(utf8.decode(health.bodyBytes));
      if (healthBody is! Map) {
        throw StateError('Desktop health response invalid');
      }
      final capabilities = healthBody['capabilities'] as List? ?? const [];
      if (!capabilities.contains('purchases_v1')) {
        return const PurchaseHistoryPullResult(
          supported: false,
          changed: 0,
          message: 'Desktop does not advertise purchases_v1',
        );
      }
    }

    final since = await repo.getSetting('lan_sync_purchases_cursor');
    final uri = Uri.parse(
      '$normalized/api/v1/purchases'
      '${since.isEmpty ? '' : '?since=${Uri.encodeQueryComponent(since)}'}',
    );
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Purchase History HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['ok'] != true || body['items'] is! List) {
      throw StateError('Desktop Purchase History response invalid');
    }

    final db = await _db.db;
    await ensureOcrPurchaseSchema(db);
    var changed = 0;
    await db.transaction((txn) async {
      for (final raw in body['items'] as List) {
        if (raw is! Map) continue;
        final remote = Map<String, dynamic>.from(raw);
        final remoteId = remote['pc_id']?.toString().trim() ?? '';
        if (remoteId.isEmpty) continue;

        // Purchases are historical records. A physical delete on Desktop must
        // never make Mobile erase history that may already be referenced by
        // audit/report data.
        if ((remote['is_deleted'] as num?)?.toInt() == 1) continue;

        var localId = await mappedLocalId(txn, 'purchase', remoteId);
        Map<String, Object?>? existing;
        if (localId != null) {
          final rows = await txn.query(
            'purchases',
            where: 'id=?',
            whereArgs: <Object?>[localId],
            limit: 1,
          );
          if (rows.isNotEmpty) existing = rows.first;
        }
        if (existing == null) {
          final sameId = await txn.query(
            'purchases',
            where: 'id=?',
            whereArgs: <Object?>[remoteId],
            limit: 1,
          );
          if (sameId.isNotEmpty) {
            existing = sameId.first;
            localId = remoteId;
          }
        }

        // Mobile-origin purchases keep their original local ID/purchase number
        // when Desktop echoes them back. New Desktop-origin purchases get a
        // namespaced local ID and are marked desktop_sync so local reverse code
        // can reject unsafe inventory mutation on a history-only record.
        final isLocalOrigin = existing != null &&
            existing['id']?.toString() == remoteId &&
            existing['source']?.toString() != 'desktop_sync';
        localId ??= 'pc-p-$remoteId';
        await rememberEntityId(txn, 'purchase', remoteId, localId);

        final supplierId = await _localEntityId(
          txn,
          'supplier',
          remote['supplier_id'],
          'suppliers',
        );
        final lines = <Map<String, Object?>>[];
        for (final lineRaw in (remote['lines'] as List? ?? const [])) {
          if (lineRaw is! Map) continue;
          final line = Map<String, Object?>.from(lineRaw);
          final remoteProductId =
              (line['productId'] ?? line['product_id'])?.toString();
          final localProductId = await _localEntityId(
            txn,
            'product',
            remoteProductId,
            'products',
          );
          lines.add(<String, Object?>{
            ...line,
            if (localProductId != null) 'productId': localProductId,
          });
        }

        final row = <String, Object?>{
          'id': localId,
          'purchase_no': isLocalOrigin
              ? existing!['purchase_no']
              : (remote['purchase_no']?.toString().trim().isNotEmpty == true
                  ? remote['purchase_no'].toString()
                  : 'PC-${remoteId.substring(0, remoteId.length > 8 ? 8 : remoteId.length)}'),
          'supplier_id': supplierId,
          'supplier_name': remote['supplier_name']?.toString() ?? '',
          'purchased_at': remote['purchased_at']?.toString() ?? '',
          'total_cents': (remote['total_cents'] as num?)?.toInt() ?? 0,
          'lines_json': jsonEncode(lines),
          'notes': remote['notes']?.toString() ?? '',
          'invoice_no': remote['invoice_no']?.toString() ?? '',
          'invoice_date': remote['invoice_date']?.toString() ?? '',
          'discount_cents':
              (remote['discount_cents'] as num?)?.toInt() ?? 0,
          'tax_cents': (remote['tax_cents'] as num?)?.toInt() ?? 0,
          'delivery_fee_cents':
              (remote['delivery_fee_cents'] as num?)?.toInt() ?? 0,
          'other_fee_cents':
              (remote['other_fee_cents'] as num?)?.toInt() ?? 0,
          'source': isLocalOrigin
              ? (existing!['source']?.toString() ?? 'manual')
              : 'desktop_sync',
          'draft_id': isLocalOrigin ? existing!['draft_id'] : null,
          // Desktop file paths are intentionally never copied to Android.
          'image_path': existing == null
              ? ''
              : existing['image_path']?.toString() ?? '',
          'ocr_raw_text': remote['ocr_raw_text']?.toString() ?? '',
          'reversed': (remote['reversed'] as num?)?.toInt() ?? 0,
          'reversed_at': remote['reversed_at']?.toString(),
          'reversed_by': remote['reversed_by']?.toString(),
          'reversal_reason': remote['reversal_reason']?.toString() ?? '',
          'reversal_notes': remote['reversal_notes']?.toString() ?? '',
        };

        await txn.insert(
          'purchases',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final draftId = row['draft_id']?.toString() ?? '';
        if (draftId.isNotEmpty) {
          await txn.insert(
            'purchase_commit_keys',
            <String, Object?>{
              'draft_id': draftId,
              'purchase_id': localId,
              'committed_at': row['purchased_at'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        if (row['reversed'] == 1) {
          final reversalRows = await txn.query(
            'purchase_reversals',
            where: 'purchase_id=?',
            whereArgs: <Object?>[localId],
            limit: 1,
          );
          final reversal = <String, Object?>{
            'purchase_id': localId,
            'reversed_at': row['reversed_at']?.toString().isNotEmpty == true
                ? row['reversed_at']
                : DateTime.now().toUtc().toIso8601String(),
            'reversed_by': row['reversed_by']?.toString() ?? 'desktop-sync',
            'reason': row['reversal_reason']?.toString() ?? '',
            'notes': row['reversal_notes']?.toString() ?? '',
          };
          if (reversalRows.isEmpty) {
            await txn.insert('purchase_reversals', <String, Object?>{
              'id': '$localId-remote-reversal',
              ...reversal,
            });
          } else {
            await txn.update(
              'purchase_reversals',
              reversal,
              where: 'purchase_id=?',
              whereArgs: <Object?>[localId],
            );
          }
        }
        changed++;
      }
    });

    final cursor = body['cursor'];
    if (cursor != null) {
      await repo.setSetting('lan_sync_purchases_cursor', '$cursor');
    }
    await repo.setSetting(
      'lan_sync_last_purchase_pull',
      DateTime.now().toUtc().toIso8601String(),
    );
    return PurchaseHistoryPullResult(
      supported: true,
      changed: changed,
      message: 'Pulled $changed purchases',
    );
  }

  Future<String?> _localEntityId(
    DatabaseExecutor txn,
    String entity,
    Object? remoteId,
    String table,
  ) async {
    if (remoteId == null || '$remoteId'.trim().isEmpty) return null;
    final mapped = await mappedLocalId(txn, entity, remoteId);
    if (mapped != null) return mapped;
    final same = await txn.query(
      table,
      columns: const ['id'],
      where: 'id=?',
      whereArgs: <Object?>['$remoteId'],
      limit: 1,
    );
    if (same.isNotEmpty) {
      final id = same.first['id'] as String;
      await rememberEntityId(txn, entity, remoteId, id);
      return id;
    }
    return null;
  }
}
