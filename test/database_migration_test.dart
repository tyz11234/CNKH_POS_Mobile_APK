import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v7 database upgrades through v10 without losing business/outbox data',
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
  lines_json TEXT NOT NULL,
  customer_id TEXT,
  voided INTEGER NOT NULL DEFAULT 0,
  void_note TEXT NOT NULL DEFAULT '',
  synced_at TEXT
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
        await db.execute('''CREATE TABLE stock_moves (
          id TEXT PRIMARY KEY,product_id TEXT NOT NULL,change REAL NOT NULL,
          reason TEXT NOT NULL,created_at TEXT NOT NULL,operator TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '')''');
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT NOT NULL)');
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

    expect(await db.getVersion(), 10);
    expect(await db.query('e_invoice_status'), isEmpty);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM suppliers')), 1);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM purchases')), 1);
    final recoveredOutbox = await db.query('sync_outbox', orderBy: 'seq ASC');
    expect(recoveredOutbox.map((row) => row['kind']), ['supplier_upsert', 'purchase', 'sale_upload']);
    expect(recoveredOutbox.last['id'], 'out1');
    expect(recoveredOutbox.map((row) => row['delivery_state']), ['pending','needs_review','pending']);
    expect(
      jsonDecode(recoveredOutbox.last['payload_json'] as String),
      {'sale_id': 'sale1'},
    );
    await queueMutation(db, 'stocktake', 'p1', {'product_id': 'p1', 'before_stock': 8, 'stock': 9});
    final appended = (await db.query('sync_outbox', orderBy: 'seq DESC', limit: 1)).single;
    expect(appended['kind'], 'stocktake');
    expect(appended['seq'], greaterThan(recoveredOutbox.length));
    expect((await db.query('sync_outbox', where: 'id=?', whereArgs: ['out1'])).single['entity_type'], 'sale');

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

  test('unpaired legacy purchase is queued once during v9 to v10 migration', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh_legacy_purchase_');
    final path = '${dir.path}/legacy_v9.db';
    var app = AppDatabase.forTesting(path, seed: false);
    var db = await app.db;
    await db.insert('products', {
      'id': 'phone-product',
      'name_zh': '商品',
      'name_en': 'Product',
      'sku': 'SKU-1',
      'barcode': '10001',
      'price_cents': 500,
      'cost_cents': 200,
      'stock': 15,
      'unit': 'pcs',
      'category': '',
      'is_deleted': 0,
      'image_path': '',
      'reorder_level': 0,
    });
    await db.insert('purchases', {
      'id': 'offline-purchase',
      'purchase_no': 'PO-OFFLINE-1',
      'supplier_id': 'phone-supplier',
      'supplier_name': 'Supplier',
      'purchased_at': '2026-09-26T10:00:00Z',
      'total_cents': 1250,
      'lines_json': jsonEncode([
        {'productId': 'phone-product', 'qty': 5, 'unitCostCents': 250},
      ]),
      'notes': 'created before pairing',
    });
    await db.insert('sales', {
      'id': 'offline-sale',
      'receipt_no': 'R-OFFLINE-1',
      'sold_at': '2026-09-26T09:59:00Z',
      'cashier': 'admin',
      'payment_method': 'cash',
      'subtotal_cents': 100,
      'total_cents': 100,
      'paid_cents': 100,
      'lines_json': jsonEncode([
        {'productId': 'phone-product', 'qty': 1},
      ]),
      'voided': 1,
      'void_note': 'voided offline',
    });
    await db.update('products', {'stock': 16}, where: 'id=?', whereArgs: ['phone-product']);
    for (final move in [
      {'id':'move-purchase','change':5.0,'reason':'purchase','notes':'PO-OFFLINE-1','created_at':'2026-09-26T10:00:00Z'},
      // A device clock rollback must not move this sale before its purchase.
      {'id':'move-sale','change':-1.0,'reason':'sale','notes':'R-OFFLINE-1','created_at':'2026-09-26T09:59:00Z'},
      {'id':'move-sale-void','change':1.0,'reason':'sale_void','notes':'R-OFFLINE-1','created_at':'2026-09-26T10:02:00Z'},
      {'id':'move-stocktake','change':1.0,'reason':'stocktake','notes':'counted','created_at':'2026-09-26T10:03:00Z'},
    ]) {
      await db.insert('stock_moves', {
        'id': move['id'], 'product_id':'phone-product', 'change':move['change'],
        'reason':move['reason'], 'created_at':move['created_at'], 'operator':'admin',
        'notes':move['notes'],
      });
    }
    await db.setVersion(9);
    await app.close();

    app = AppDatabase.forTesting(path, seed: false);
    db = await app.db;
    expect(await db.getVersion(), 10);
    var pending = await db.query(
      'sync_outbox',
      orderBy: 'seq ASC',
    );
    expect(pending.map((row)=>row['kind']), ['product_upsert','purchase','sale_upload','sale_void','stocktake']);
    final baseline=jsonDecode(pending.first['payload_json'] as String) as Map;
    expect(baseline['row']['stock'],10);
    final purchaseOp=pending.firstWhere((row)=>row['kind']=='purchase');
    final payload = jsonDecode(purchaseOp['payload_json'] as String) as Map;
    final line = (payload['lines'] as List).single as Map;
    expect(line['productSku'], 'SKU-1');
    expect(line['productBarcode'], '10001');
    expect(line['productId'], 'phone-product');
    final stocktake=jsonDecode(pending.last['payload_json'] as String) as Map;
    expect(stocktake['before_stock'],15);
    expect(stocktake['stock'],16);

    await db.setVersion(9);
    await app.close();
    app = AppDatabase.forTesting(path, seed: false);
    db = await app.db;
    pending = await db.query('sync_outbox', orderBy:'seq ASC');
    expect(pending.map((row)=>row['kind']), ['product_upsert','purchase','sale_upload','sale_void','stocktake']);
    await app.close();
    await dir.delete(recursive: true);
  });
}
