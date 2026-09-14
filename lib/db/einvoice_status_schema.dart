import 'package:sqflite/sqflite.dart';
Future<void> ensureEInvoiceStatusSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS e_invoice_status (
    host TEXT NOT NULL, document_id TEXT NOT NULL, sale_id TEXT NOT NULL,
    client_sale_id TEXT NOT NULL DEFAULT '', receipt_no TEXT NOT NULL,
    environment TEXT NOT NULL, status TEXT NOT NULL, updated_at TEXT NOT NULL,
    PRIMARY KEY(host, document_id))''');
}
