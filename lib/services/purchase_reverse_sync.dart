import 'stock_numeric_validation.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

Map<String, double> _quantities(Map<String, Object?> purchase) {
  final lines = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
  if (lines is! List || lines.isEmpty) throw const FormatException('invalid reversal lines');
  final result = <String, double>{};
  for (final raw in lines) {
    if (raw is! Map) throw const FormatException('invalid reversal line');
    final id = raw['productId']?.toString() ?? '';
    final qty = raw['qty'];
    if (id.isEmpty || qty is! num || !qty.isFinite || qty <= 0) {
      throw const FormatException('invalid reversal quantity');
    }
    result[id] = (result[id] ?? 0) + qty.toDouble();
  }
  return result;
}

/// Finalize a paired request only after its stable operation ID is ACKed.
/// Inventory deltas and Outbox deletion share the caller's transaction.
Future<void> acknowledgePurchaseReverse(
  DatabaseExecutor txn,
  Map<String, Object?> operation,
) async {
  final payload = Map<String, dynamic>.from(jsonDecode(operation['payload_json'] as String) as Map);
  if (payload['local_applied'] != false) return;
  final purchaseId = payload['purchase_id']?.toString() ?? '';
  final rows = await txn.query('purchases', where: 'id=?', whereArgs: [purchaseId], limit: 1);
  if (rows.isEmpty) throw StateError('已确认的撤销缺少本地进货记录，请核对');
  final purchase = rows.single;
  // Pre-v10 and unpaired reversals already changed local stock atomically.
  if (purchase['reversed'] == 1) return;
  final now = DateTime.now().toIso8601String();
  for (final entry in _quantities(purchase).entries) {
    await validateStockAddition(txn, entry.key, -entry.value);
    if (await txn.rawUpdate('UPDATE products SET stock=stock-? WHERE id=?', [entry.value, entry.key]) != 1) {
      throw StateError('已确认的撤销缺少本地商品，请核对');
    }
    // Desktop determines the restoration cost. The next authoritative
    // catalog pull applies it; never send a Mobile cached cost to Desktop.
    await txn.insert('stock_moves', {
      'id': 'purchase-reverse-ack:${operation['id']}:${entry.key}',
      'product_id': entry.key, 'change': -entry.value,
      'reason': 'purchase_reversal', 'created_at': now,
      'operator': payload['operator'] ?? 'mobile-sync',
      'notes': '${purchase['purchase_no']} · ${payload['reason']}',
    });
  }
  await txn.insert('purchase_reversals', {
    'id': 'purchase-reverse-ack:${operation['id']}', 'purchase_id': purchaseId,
    'reversed_at': now, 'reversed_by': payload['operator'] ?? 'mobile-sync',
    'reason': payload['reason'] ?? '', 'notes': payload['notes'] ?? '',
  });
  await txn.update('purchases', {
    'reversed': 1, 'reversed_at': now,
    'reversed_by': payload['operator'] ?? 'mobile-sync',
    'reversal_reason': payload['reason'] ?? '', 'reversal_notes': payload['notes'] ?? '',
  }, where: 'id=?', whereArgs: [purchaseId]);
  await txn.insert('purchase_audit_log', {
    'id': AppDatabase.newId(), 'purchase_id': purchaseId, 'occurred_at': now,
    'username': payload['operator'] ?? 'mobile-sync', 'action': 'purchase_reverse_acknowledged',
    'field_name': 'status', 'original_value': 'committed', 'final_value': 'reversed',
    'details': 'operation=${operation['id']}; ${payload['reason']}',
  });
}

/// A structured business rejection proves the Desktop transaction did not
/// commit. Retain the same request, compensate a legacy local reversal once,
/// and allow unrelated operations and authoritative reconciliation to continue.
/// Network errors and unstructured responses must never enter this path.
Future<bool> rejectPurchaseReverse(
  DatabaseExecutor txn,
  Map<String, Object?> operation,
  String error,
) async {
  final payload = Map<String, dynamic>.from(jsonDecode(operation['payload_json'] as String) as Map);
  final purchaseId = payload['purchase_id']?.toString() ?? '';
  final rows = await txn.query('purchases', where: 'id=?', whereArgs: [purchaseId], limit: 1);
  if (rows.isEmpty) return false;
  final purchase = rows.single;
  final now = DateTime.now().toIso8601String();
  Map<String, Object?>? archivedReversal;
  if (payload['local_applied'] != false && purchase['reversed'] == 1) {
    final reversals = await txn.query('purchase_reversals', where: 'purchase_id=?', whereArgs: [purchaseId], limit: 1);
    if (reversals.isEmpty) return false;
    final quantities = _quantities(purchase);
    for (final entry in quantities.entries) {
      final moves = await txn.query('stock_moves',
        where: "product_id=? AND reason='purchase_reversal' AND instr(notes,?)=1",
        whereArgs: [entry.key, '${purchase['purchase_no']} · ']);
      final reversedQty = moves.fold<double>(0, (sum, move) => sum - (move['change'] as num).toDouble());
      if ((reversedQty - entry.value).abs() > 0.0000001) return false;
      if ((await txn.query('products', columns: ['id'], where: 'id=?', whereArgs: [entry.key], limit: 1)).isEmpty) return false;
    }
    for (final entry in quantities.entries) {
      await validateStockAddition(txn, entry.key, entry.value);
      await txn.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [entry.value, entry.key]);
      final plans = payload['local_reverse_plan'];
      if (plans is List) {
        final match = plans.where((p) => p is Map && p['product_id'] == entry.key).toList();
        if (match.length == 1) {
          final plan = match.single as Map;
          if (plan['before_cost'] is int && plan['after_cost'] is int) {
            await txn.update('products', {'cost_cents': plan['before_cost']},
              where: 'id=? AND cost_cents=?', whereArgs: [entry.key, plan['after_cost']]);
          }
        }
      }
      await txn.insert('stock_moves', {
        'id': 'purchase-reverse-rejected:${operation['id']}:${entry.key}',
        'product_id': entry.key, 'change': entry.value,
        'reason': 'purchase_reversal_rejected', 'created_at': now,
        'operator': 'desktop-sync', 'notes': '${purchase['purchase_no']} · $error',
      });
    }
    archivedReversal = reversals.single;
    await txn.delete('purchase_reversals', where: 'purchase_id=?', whereArgs: [purchaseId]);
    await txn.update('purchases', {
      'reversed': 0, 'reversed_at': null, 'reversed_by': null,
      'reversal_reason': '', 'reversal_notes': '',
    }, where: 'id=?', whereArgs: [purchaseId]);
  } else if (purchase['reversed'] == 1) {
    return false;
  }
  if (operation['delivery_state'] != 'rejected') {
    await txn.insert('purchase_audit_log', {
      'id': AppDatabase.newId(), 'purchase_id': purchaseId, 'occurred_at': now,
      'username': payload['operator'] ?? 'mobile-sync', 'action': 'purchase_reverse_rejected',
      'field_name': 'status', 'original_value': '${purchase['reversed']}', 'final_value': 'committed',
      'details': jsonEncode({'operation_id': operation['id'], 'error': error,
        if (archivedReversal != null) 'local_reversal': archivedReversal}),
    });
  }
  await txn.update('sync_outbox', {
    'delivery_state': 'rejected', 'last_error': error,
    'payload_json': jsonEncode({...payload, 'local_applied': false}),
  }, where: 'id=?', whereArgs: [operation['id']]);
  return true;
}
