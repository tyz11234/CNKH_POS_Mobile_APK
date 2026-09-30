import 'package:sqflite/sqflite.dart';
Future<void> ensureReliabilitySchema(DatabaseExecutor db) async {
  for (final sql in <String>[
    "CREATE TABLE IF NOT EXISTS user_credentials (username TEXT PRIMARY KEY COLLATE NOCASE, salt TEXT NOT NULL, pin_hash TEXT NOT NULL, failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT NOT NULL DEFAULT '')",
    'CREATE TABLE IF NOT EXISTS sync_entity_ids (entity TEXT NOT NULL, remote_id TEXT NOT NULL, local_id TEXT NOT NULL, PRIMARY KEY(entity,remote_id), UNIQUE(entity,local_id))',
    "CREATE TABLE IF NOT EXISTS sync_outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,kind TEXT NOT NULL,entity_id TEXT NOT NULL,payload_json TEXT NOT NULL,created_at TEXT NOT NULL,last_error TEXT NOT NULL DEFAULT '')",
    'CREATE TABLE IF NOT EXISTS sync_applied_operations (id TEXT PRIMARY KEY,applied_at TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS stock_reversals (sale_id TEXT PRIMARY KEY,reversed_at TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sold_at,id)',
    'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id,voided)',
    'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    'CREATE INDEX IF NOT EXISTS idx_stock_moves_product ON stock_moves(product_id)',
  ]) { await db.execute(sql); }

  // v7 databases used a small Outbox shape with `entity_type` and no ordered
  // sequence/error columns. Upgrade it in place so unacknowledged rows survive
  // and continue to obey the current retry ordering.
  final outboxColumns = (await db.rawQuery('PRAGMA table_info(sync_outbox)'))
      .map((row) => row['name']?.toString() ?? '')
      .toSet();
  if (!outboxColumns.contains('kind')) {
    await db.execute("ALTER TABLE sync_outbox ADD COLUMN kind TEXT NOT NULL DEFAULT ''");
    if (outboxColumns.contains('entity_type')) {
      await db.execute('UPDATE sync_outbox SET kind=entity_type WHERE kind=\'\'');
    }
  }
  if (!outboxColumns.contains('seq')) {
    await db.execute('ALTER TABLE sync_outbox ADD COLUMN seq INTEGER NOT NULL DEFAULT 0');
  }
  if (!outboxColumns.contains('last_error')) {
    await db.execute("ALTER TABLE sync_outbox ADD COLUMN last_error TEXT NOT NULL DEFAULT ''");
  }
  if (!outboxColumns.contains('delivery_state')) {
    await db.execute("ALTER TABLE sync_outbox ADD COLUMN delivery_state TEXT NOT NULL DEFAULT 'pending'");
  }
  await db.execute('UPDATE sync_outbox SET seq=rowid WHERE seq=0');
  final legacyType = (await db.rawQuery('PRAGMA table_info(sync_outbox)'))
      .where((column) => column['name'] == 'entity_type').toList();
  if (legacyType.isNotEmpty && legacyType.single['notnull'] == 1 &&
      legacyType.single['dflt_value'] == null) {
    // SQLite cannot add a DEFAULT to the obsolete required column in place.
    // Copy every operation (including its identity/order/error) into the
    // compatible shape; retain entity_type for historical audit readability.
    // No DELETE is issued, so attachment ACK triggers are never fired.
    final triggers = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='trigger' AND tbl_name='sync_outbox'");
    await db.execute("""CREATE TABLE sync_outbox_v10 (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,entity_id TEXT NOT NULL,payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL,last_error TEXT NOT NULL DEFAULT '',
      delivery_state TEXT NOT NULL DEFAULT 'pending',entity_type TEXT NOT NULL DEFAULT '')""");
    await db.execute('''INSERT INTO sync_outbox_v10
      (seq,id,kind,entity_id,payload_json,created_at,last_error,delivery_state,entity_type)
      SELECT seq,id,kind,entity_id,payload_json,created_at,last_error,delivery_state,entity_type
      FROM sync_outbox ORDER BY seq''');
    await db.execute('DROP TABLE sync_outbox');
    await db.execute('ALTER TABLE sync_outbox_v10 RENAME TO sync_outbox');
    for (final trigger in triggers) {
      if (trigger['sql'] is String) await db.execute(trigger['sql'] as String);
    }
  }
  await db.execute('''CREATE TRIGGER IF NOT EXISTS sync_outbox_assign_seq
    AFTER INSERT ON sync_outbox WHEN NEW.seq=0 BEGIN
      UPDATE sync_outbox SET seq=NEW.rowid WHERE rowid=NEW.rowid;
    END''');
}
