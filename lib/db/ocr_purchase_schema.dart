import 'package:sqflite/sqflite.dart';

Future<void> ensureOcrPurchaseSchema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(purchases)');
  final names = <String>{
    for (final row in columns) row['name']?.toString() ?? ''
  };

  Future<void> add(String name, String sql) async {
    if (!names.contains(name)) {
      await db.execute('ALTER TABLE purchases ADD COLUMN $name $sql');
      names.add(name);
    }
  }

  await add('invoice_no', "TEXT NOT NULL DEFAULT ''");
  await add('invoice_date', "TEXT NOT NULL DEFAULT ''");
  await add('discount_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('tax_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('delivery_fee_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('other_fee_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('source', "TEXT NOT NULL DEFAULT 'manual'");
  await add('draft_id', 'TEXT');
  // image_path is the compressed UI preview. The immutable original is kept as
  // a purchase attachment so Desktop transfer can be retried independently.
  await add('image_path', "TEXT NOT NULL DEFAULT ''");
  await add('ocr_raw_text', "TEXT NOT NULL DEFAULT ''");
  await add('reversed', 'INTEGER NOT NULL DEFAULT 0');
  await add('reversed_at', 'TEXT');
  await add('reversed_by', 'TEXT');
  await add('reversal_reason', "TEXT NOT NULL DEFAULT ''");
  await add('reversal_notes', "TEXT NOT NULL DEFAULT ''");

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_drafts (
  id TEXT PRIMARY KEY,
  supplier_id TEXT,
  supplier_name TEXT NOT NULL DEFAULT '',
  invoice_no TEXT NOT NULL DEFAULT '',
  invoice_date TEXT NOT NULL DEFAULT '',
  image_path TEXT NOT NULL DEFAULT '',
  original_image_path TEXT NOT NULL DEFAULT '',
  ocr_raw_text TEXT NOT NULL DEFAULT '',
  discount_cents INTEGER NOT NULL DEFAULT 0,
  tax_cents INTEGER NOT NULL DEFAULT 0,
  delivery_fee_cents INTEGER NOT NULL DEFAULT 0,
  other_fee_cents INTEGER NOT NULL DEFAULT 0,
  invoice_total_cents INTEGER,
  warnings_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft'
)''');

  // Defensive compatibility for databases where the OCR tables were created by
  // an earlier runtime ensure before formal version 8 migration landed.
  final draftColumns = await db.rawQuery('PRAGMA table_info(purchase_drafts)');
  final draftNames = <String>{
    for (final row in draftColumns) row['name']?.toString() ?? ''
  };
  if (!draftNames.contains('original_image_path')) {
    await db.execute(
      "ALTER TABLE purchase_drafts ADD COLUMN original_image_path TEXT NOT NULL DEFAULT ''",
    );
  }

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_draft_lines (
  id TEXT PRIMARY KEY,
  draft_id TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  raw_text TEXT NOT NULL DEFAULT '',
  raw_product_name TEXT NOT NULL DEFAULT '',
  matched_product_id TEXT,
  matched_product_name TEXT NOT NULL DEFAULT '',
  match_confidence REAL NOT NULL DEFAULT 0,
  quantity REAL NOT NULL DEFAULT 0,
  unit TEXT NOT NULL DEFAULT 'pcs',
  unit_cost_cents INTEGER NOT NULL DEFAULT 0,
  line_subtotal_cents INTEGER NOT NULL DEFAULT 0,
  original_quantity REAL,
  original_unit_cost_cents INTEGER,
  original_line_subtotal_cents INTEGER,
  conversion_factor REAL NOT NULL DEFAULT 1,
  warnings_json TEXT NOT NULL DEFAULT '[]',
  user_modified INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(draft_id) REFERENCES purchase_drafts(id) ON DELETE CASCADE
)''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS supplier_product_aliases (
  id TEXT PRIMARY KEY,
  supplier_id TEXT NOT NULL,
  raw_name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  product_id TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'pcs',
  conversion_factor REAL NOT NULL DEFAULT 1,
  use_count INTEGER NOT NULL DEFAULT 1,
  last_used_at TEXT NOT NULL,
  UNIQUE(supplier_id, normalized_name)
)''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_attachments (
  id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL,
  local_path TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'invoice_image',
  content_hash TEXT NOT NULL DEFAULT '',
  sync_status TEXT NOT NULL DEFAULT 'pending',
  synced_at TEXT,
  last_error TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY(purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
)''');

  final attachmentColumns =
      await db.rawQuery('PRAGMA table_info(purchase_attachments)');
  final attachmentNames = <String>{
    for (final row in attachmentColumns) row['name']?.toString() ?? ''
  };
  Future<void> addAttachmentColumn(String name, String sql) async {
    if (!attachmentNames.contains(name)) {
      await db.execute(
        'ALTER TABLE purchase_attachments ADD COLUMN $name $sql',
      );
      attachmentNames.add(name);
    }
  }

  await addAttachmentColumn('content_hash', "TEXT NOT NULL DEFAULT ''");
  await addAttachmentColumn('sync_status', "TEXT NOT NULL DEFAULT 'pending'");
  await addAttachmentColumn('synced_at', 'TEXT');
  await addAttachmentColumn('last_error', "TEXT NOT NULL DEFAULT ''");

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_audit_log (
  id TEXT PRIMARY KEY,
  purchase_id TEXT,
  draft_id TEXT,
  occurred_at TEXT NOT NULL,
  username TEXT NOT NULL,
  action TEXT NOT NULL,
  field_name TEXT NOT NULL DEFAULT '',
  original_value TEXT NOT NULL DEFAULT '',
  final_value TEXT NOT NULL DEFAULT '',
  details TEXT NOT NULL DEFAULT ''
)''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_reversals (
  id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL UNIQUE,
  reversed_at TEXT NOT NULL,
  reversed_by TEXT NOT NULL,
  reason TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  FOREIGN KEY(purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
)''');

  // A draft may be retried after a UI double tap, app restart, timeout or lost ACK.
  // Reserving the draft id in the same transaction as the stock mutation makes
  // the commit idempotent without relying on timing in the UI.
  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_commit_keys (
  draft_id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL,
  committed_at TEXT NOT NULL
)''');

  // Backfill keys for OCR purchases made before this table existed. Ignore
  // duplicate legacy rows rather than deleting or rewriting historical data.
  await db.execute('''
INSERT OR IGNORE INTO purchase_commit_keys(draft_id, purchase_id, committed_at)
SELECT draft_id, id, purchased_at
FROM purchases
WHERE draft_id IS NOT NULL AND trim(draft_id) <> ''
ORDER BY purchased_at ASC
''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_purchase_drafts_status ON purchase_drafts(status, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_purchase_alias_supplier ON supplier_product_aliases(supplier_id, normalized_name)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_purchase_audit_purchase ON purchase_audit_log(purchase_id, occurred_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_purchases_supplier_invoice ON purchases(supplier_id, invoice_no, reversed)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_purchase_attachment_sync ON purchase_attachments(sync_status, created_at)',
  );
}
