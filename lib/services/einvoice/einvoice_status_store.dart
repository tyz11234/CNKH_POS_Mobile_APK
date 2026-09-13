import 'package:sqflite/sqflite.dart';

/// A read-only mirror. This module contains no MyInvois client or credentials.
class EInvoiceStatusStore {
  EInvoiceStatusStore(this.db);
  final Database db;
  Future<void> replaceSnapshot(String host, List<Map<String, dynamic>> rows) async {
    final accepted = <Map<String, Object?>>[];
    for (final row in rows) {
      for (final key in ['document_id','sale_id','receipt_no','environment','status','updated_at']) {
        if (row[key] is! String) throw const FormatException('Invalid e-Invoice status response');
      }
      if (!['sandbox','production'].contains(row['environment']) || !['pending','submitting','submitted','validated','rejected','cancelled','needs_review'].contains(row['status'])) throw const FormatException('Unknown e-Invoice status');
      accepted.add({'host': host, for (final key in ['document_id','sale_id','receipt_no','environment','status','updated_at']) key: row[key], 'client_sale_id': row['client_sale_id'] is String ? row['client_sale_id'] : ''});
    }
    await db.transaction((txn) async {
      await txn.delete('e_invoice_status', where: 'host=?', whereArgs: [host]);
      for (final row in accepted) { await txn.insert('e_invoice_status', row, conflictAlgorithm: ConflictAlgorithm.replace); }
    });
  }
  Future<List<Map<String, Object?>>> history(String host, String environment) => db.rawQuery('''
    SELECT s.receipt_no, s.voided, s.total_cents, COALESCE(e.status,'pending') AS status, e.updated_at
    FROM sales s LEFT JOIN e_invoice_status e ON e.host=? AND e.environment=?
      AND (e.client_sale_id=s.id OR ('pc-' || e.sale_id)=s.id OR e.sale_id=s.id)
    ORDER BY s.sold_at DESC LIMIT 500''', [host, environment]);
}
