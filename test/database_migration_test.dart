import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v7 database upgrades to v8 OCR schema without losing business data',
      () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh_migration_test_');
    final path = '${dir.path}/legacy_v7.db';

    final legacy = await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL,
  sku TEXT,
  barcode TEXT,
  price_cents INTEGER NOT NULL,
  cost_cents INTEGER NOT NULL DEFAULT 0,
  stock REAL NOT NULL DEFAULT 0,
  unit TEXT NOT NULL DEFAULT 'pcs',
  category TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0,
  image_path TEXT NOT NULL DEFAULT '',
  reorder_level REAL NOT NULL DEFAULT 0
)''');
        await db.execute('''
CREATE TABLE sales (
  id TEXT PRIMARY KEY,
  receipt_no TEXT NOT NULL,
  sold_at TEXT NOT NULL,
  cashier TEXT NOT NULL,
  payment_method TEXT NOT NULL,
  subtotal_cents INTEGER NOT NULL,
  total_cents INTEGER NOT NULL,
  paid_cents INTEGER NOT NULL,
  lines_json TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0
)''');
        await db.execute('''
CREATE TABLE suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0
)''');
        await db.execute('''
CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  purchase_no TEXT NOT NULL,
  supplier_id TEXT,
  supplier_name TEXT NOT NULL,
  purchased_at TEXT NOT NULL,
  total_cents INTEGER NOT NULL,
  lines_json TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)''');
        await db.execute('''
CREATE TABLE sync_outbox (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
      },
    );

    await legacy.insert('products', {
      'id': 'p1',
      'name_zh': '旧商品',
      'name_en': 'Legacy Product',
      'sku': 'OLD-1',
      'barcode': '123',
      'price_cents': 500,
      'cost_cents': 300,
      'stock': 8,
      'unit': 'pcs',
      'category': 'Legacy',
      'is_deleted': 0,
      'image_path': '',
      'reorder_level': 1,
    });
    await legacy.insert('sales', {
      'id': 'sale1',
      'receipt_no': 'R-OLD-1',
      'sold_at': '2026-09-01T10:00:00',
      'cashier': 'admin',
      'payment_method': 'cash',
      'subtotal_cents': 500,
      'total_cents': 500,
      'paid_cents': 500,
      'lines_json': '[]',
    });
    await legacy.insert('customers', {
      'id': 'c1',
      'name': '旧客户',
      'phone': '012',
      'notes': '',
      'is_deleted': 0,
    });
    await legacy.insert('suppliers', {
      'id': 's1',
      'name': '旧供应商',
      'phone': '',
      'email': '',
      'notes': '',
      'is_deleted': 0,
    });
    await legacy.insert('purchases', {
      'id': 'po1',
      'purchase_no': 'PO-OLD-1',
      'supplier_id': 's1',
      'supplier_name': '旧供应商',
      'purchased_at': '2026-09-01T09:00:00',
      'total_cents': 300,
      'lines_json': '[]',
      'notes': 'legacy',
    });
    await legacy.insert('sync_outbox', {
      'id': 'out1',
      'entity_type': 'sale',
      'entity_id': 'sale1',
      'payload_json': '{}',
      'created_at': '2026-09-01T10:00:00',
    });
    await legacy.close();

    final app = AppDatabase.forTesting(path, seed: false);
    final db = await app.db;

    expect(await db.getVersion(), 8);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM suppliers')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM purchases')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_outbox')), 1);

    final purchaseColumns = await db.rawQuery('PRAGMA table_info(purchases)');
    final names = purchaseColumns.map((row) => row['name']).toSet();
    expect(names, containsAll(['invoice_no', 'draft_id', 'ocr_raw_text', 'reversed']));

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'purchase_%'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(
      tableNames,
      containsAll([
        'purchase_drafts',
        'purchase_draft_lines',
        'purchase_attachments',
        'purchase_audit_log',
        'purchase_reversals',
        'purchase_commit_keys',
      ]),
    );

    await app.close();
    await dir.delete(recursive: true);
  });
}
