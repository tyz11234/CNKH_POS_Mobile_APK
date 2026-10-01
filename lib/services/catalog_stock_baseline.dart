import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Initial stock is not a later inventory event. Prove that the full Desktop
/// ledger contains the phone's own purchase quantities before classifying an
/// initial difference as a baseline. Real later Desktop moves are replayed and
/// still prevent reversal, even when their net change is zero.
Future<bool> isProvenInitialStockBaseline(DatabaseExecutor txn, {
  required String remoteProductId,
  required String localProductId,
  required List<dynamic> fullMoves,
}) async {
  final purchases = await txn.query('purchases',
      where: "source<>'desktop_sync' AND COALESCE(reversed,0)=0");
  final quantities = <String, double>{};
  for (final purchase in purchases) {
    var quantity = 0.0;
    for (final raw in jsonDecode(purchase['lines_json'] as String) as List) {
      final line = raw as Map;
      if (line['productId'] == localProductId) {
        quantity += (line['qty'] as num).toDouble();
      }
    }
    if (quantity > 0) quantities[purchase['id'] as String] = quantity;
  }
  if (quantities.isEmpty) return true;
  final confirmed = <String, double>{};
  for (final raw in fullMoves) {
    if (raw is! Map || raw['reason'] != 'purchase' ||
        raw['product_id']?.toString() != remoteProductId) continue;
    final id = raw['source_id']?.toString() ?? '';
    final change = raw['change'];
    if (!quantities.containsKey(id) || change is! num || !change.isFinite || change <= 0) continue;
    confirmed[id] = (confirmed[id] ?? 0) + change.toDouble();
  }
  return quantities.entries.every((e) =>
      confirmed.containsKey(e.key) && (confirmed[e.key]! - e.value).abs() < 0.0000001);
}
