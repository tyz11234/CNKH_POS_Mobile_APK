import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/einvoice/einvoice_status_store.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Map<String, Object?> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _remoteSale(String receipt, {int total = 100}) => {
  'pc_id': 'desktop-$receipt',
  'receipt_no': receipt,
  'sold_at': '2026-10-01T10:00:00',
  'payment_method': 'CASH',
  'total_cents': total,
  'paid_cents': total,
  'lines': [],
  'is_deleted': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  const cfg = LanSyncConfig(baseUrl: 'http://desktop', token: 't');
  const product = Product(
    id: 'p1',
    sku: 'P1',
    barcode: 'P1',
    nameZh: '商品',
    nameEn: 'Product',
    priceCents: 100,
    stock: 100,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-sales-reconcile-');
    database = AppDatabase.forTesting('${temp.path}/phone.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
    await (await database.db).delete('sync_outbox');
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<SaleRecord> makeSale({bool synced = true}) async {
    final sale = await repo.createSale(
      cart: CartState(items: [CartItem(product: product)]),
      paymentMethod: 'CASH',
      paidCents: 100,
      cashier: 'test',
    );
    if (synced) {
      final db = await database.db;
      await db.update(
        'sales',
        {'synced_at': '2026-10-01T10:01:00'},
        where: 'id=?',
        whereArgs: [sale.id],
      );
      await db.delete(
        'sync_outbox',
        where: 'entity_id=?',
        whereArgs: [sale.id],
      );
    }
    return sale;
  }

  test('restored host snapshot voids missing cached sales and preserves a new offline sale', () async {
    final missing = await makeSale();
    final kept = await makeSale();
    SaleRecord? concurrent;
    await repo.setSetting('lan_sync_products_cursor', '100');
    await repo.setSetting('lan_sync_sales_cursor', '100');
    final transport = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 2,
          'capabilities': ['mutations_v1'],
        });
      }
      if (request.url.path == '/api/v1/sales') {
        expect(request.url.queryParameters, isEmpty);
        // A cashier can sell while the HTTP snapshot is in flight.
        concurrent = await makeSale(synced: false);
        return _json({
          'ok': true,
          'cursor': 2,
          'items': [_remoteSale(kept.receiptNo)],
        });
      }
      return _json({'ok': true, 'cursor': 2, 'items': []});
    });
    addTearDown(transport.close);
    await LanSyncClient(repo, httpClient: transport).synchronize(cfg);
    final db = await database.db;
    final sales = {for (final s in await db.query('sales')) s['id']: s};
    expect(sales[missing.id]!['voided'], 1);
    expect(sales[kept.id]!['voided'], 0);
    expect(sales[concurrent!.id]!['voided'], 0);
    expect(sales[concurrent!.id]!['synced_at'], anyOf(isNull, ''));
    expect(
      await db.query(
        'sync_outbox',
        where: 'entity_id=?',
        whereArgs: [concurrent!.id],
      ),
      hasLength(1),
    );
    expect(await repo.getSetting('lan_sync_sales_cursor'), '2');
  });

  for (final invalid in <Map<String, Object?>>[
    {'ok': true, 'cursor': 2},
    {'ok': true, 'cursor': 2, 'items': [], 'has_more': true, 'next': 'page2'},
    {
      'ok': true,
      'cursor': 2,
      'items': [
        {'pc_id': 'missing-receipt'},
      ],
    },
    {
      'ok': true,
      'cursor': 2,
      'items': [_remoteSale('R1'), _remoteSale('R1')],
    },
    {
      'ok': true,
      'cursor': 2,
      'items': [
        _remoteSale('R1'),
        {..._remoteSale('R2'), 'total_cents': 'malformed'},
      ],
    },
  ]) {
    test(
      'incomplete or invalid snapshot cannot partially update or void sales: $invalid',
      () async {
        await makeSale();
        final db = await database.db;
        final before = await db.query('sales');
        final transport = MockClient((request) async {
          if (request.url.path == '/api/v1/health') {
            return _json({
              'ok': true,
              'protocol': 1,
              'cursor': 2,
              'capabilities': ['mutations_v1'],
            });
          }
          if (request.url.path == '/api/v1/sales') return _json(invalid);
          return _json({'ok': true, 'cursor': 2, 'items': []});
        });
        addTearDown(transport.close);
        await expectLater(
          LanSyncClient(
            repo,
            httpClient: transport,
          ).synchronize(cfg, full: true),
          throwsA(anything),
        );
        expect(await db.query('sales'), before);
        expect(await repo.getSetting('lan_sync_sales_cursor'), '');
      },
    );
  }

  test('incremental responses do not reconcile absent sales', () async {
    final existing = await makeSale();
    await repo.setSetting('lan_sync_sales_cursor', '1');
    final transport = MockClient((request) async {
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 2,
          'capabilities': ['mutations_v1'],
        });
      }
      if (request.url.path == '/api/v1/sales') {
        expect(request.url.queryParameters['since'], '1');
      }
      return _json({'ok': true, 'cursor': 2, 'items': []});
    });
    addTearDown(transport.close);
    await LanSyncClient(repo, httpClient: transport).synchronize(cfg);
    expect(
      (await (await database.db).query(
        'sales',
        where: 'id=?',
        whereArgs: [existing.id],
      )).single['voided'],
      0,
    );
  });

  test('sale review retains inventory, sales and queued work while tax status refreshes', () async {
    final review = await makeSale();
    await repo.voidSale(review.id, 'local void awaiting tax review');
    final db = await database.db;
    await db.update('sync_outbox', {
      'delivery_state': 'needs_review',
      'last_error': 'tax review',
    }, where: "kind='sale_void'");
    final pending = await makeSale(synced: false);
    await queueMutation(db, 'stocktake', 'p1', {
      'product_id': 'p1',
      'stock': 99,
    });
    await rememberEntityId(db, 'product', 'desktop-p1', 'p1');
    final beforeStock = (await repo.getProduct('p1'))!.stock;
    final beforeQueue = await db.query('sync_outbox', orderBy: 'seq');
    final transport = MockClient((request) async {
      expect(
        request.method,
        'GET',
        reason: 'review must retain later stock/sale uploads',
      );
      if (request.url.path == '/api/v1/health') {
        return _json({
          'ok': true,
          'protocol': 1,
          'cursor': 10,
          'capabilities': ['mutations_v1', 'einvoice_status_v1'],
        });
      }
      if (request.url.path == '/api/v1/products') {
        return _json({
          'ok': true,
          'cursor': 10,
          'items': [
            {
              'pc_id': 'desktop-p1',
              'sku': 'P1',
              'barcode': 'P1',
              'name_zh': '商品',
              'name_en': 'Product',
              'stock': 0,
              'price_cents': 100,
              'is_deleted': 0,
            },
          ],
        });
      }
      if (request.url.path == '/api/v1/sales') {
        fail('sales must wait for the catalog customer/product mappings');
      }
      if (request.url.path == '/api/v1/einvoices') {
        return _json({
          'items': [
            {
              'document_id': 'tax-review',
              'sale_id': 'desktop-review',
              'client_sale_id': review.id,
              'receipt_no': review.receiptNo,
              'environment': 'sandbox',
              'status': 'cancelled',
              'updated_at': '2026-10-01T11:00:00',
            },
          ],
          'has_more': false,
        });
      }
      return _json({'ok': true, 'cursor': 10, 'items': []});
    });
    addTearDown(transport.close);
    final result = await LanSyncClient(
      repo,
      httpClient: transport,
    ).synchronize(cfg);
    expect(result, contains('库存暂缓'));
    expect((await repo.getProduct('p1'))!.stock, beforeStock);
    expect(await db.query('sync_outbox', orderBy: 'seq'), beforeQueue);
    final sales = {for (final s in await db.query('sales')) s['receipt_no']: s};
    expect(
      sales[review.receiptNo]!['void_note'],
      'local void awaiting tax review',
    );
    expect(sales[pending.receiptNo]!['total_cents'], 100);
    expect(sales.containsKey('PC-NEW'), isFalse);
    final tax = await EInvoiceStatusStore(db)
        .history(cfg.normalizedBase, 'sandbox');
    expect(
      tax.firstWhere((row) => row['receipt_no'] == review.receiptNo)['status'],
      'cancelled',
    );
    expect(await repo.getSetting('lan_sync_products_cursor'), '');
    expect(await repo.getSetting('lan_sync_sales_cursor'), '');
  });

  test('new credit sales wait for catalog mappings during tax review and load after review', () async {
    final review = await makeSale();
    await repo.voidSale(review.id, 'awaiting tax review');
    final db = await database.db;
    await db.update('sync_outbox', {
      'delivery_state': 'needs_review',
      'last_error': 'tax review',
    }, where: "kind='sale_void'");
    await repo.setSetting('lan_sync_products_cursor', '7');
    await repo.setSetting('lan_sync_sales_cursor', '7');
    var salesRequests = 0;
    var taxRequests = 0;
    final transport = MockClient((request) async {
      expect(request.method, 'GET');
      switch (request.url.path) {
        case '/api/v1/health':
          return _json({
            'ok': true,
            'protocol': 1,
            'cursor': 10,
            'capabilities': ['mutations_v1', 'einvoice_status_v1'],
          });
        case '/api/v1/products':
          return _json({
            'ok': true,
            'cursor': 10,
            'items': [
              {
                'pc_id': 'new-product',
                'sku': 'NEW',
                'barcode': 'NEW',
                'name_zh': '新商品',
                'name_en': 'New product',
                'price_cents': 500,
                'stock': 9,
                'is_deleted': 0,
              },
            ],
          });
        case '/api/v1/customers':
          return _json({
            'ok': true,
            'cursor': 10,
            'items': [
              {
                'pc_id': 'new-customer',
                'name': 'New customer',
                'phone': '0123456789',
                'is_deleted': 0,
              },
            ],
          });
        case '/api/v1/sales':
          salesRequests++;
          expect(request.url.queryParameters['since'], '7');
          return _json({
            'ok': true,
            'cursor': 10,
            'items': [
              {
                ..._remoteSale('NEW-CREDIT', total: 500),
                'payment_method': 'CREDIT',
                'paid_cents': 0,
                'customer_id': 'new-customer',
                'customer_name': 'New customer',
                'lines': [
                  {'productId': 'new-product', 'qty': 1, 'unitPriceCents': 500},
                ],
              },
            ],
          });
        case '/api/v1/einvoices':
          taxRequests++;
          return _json({'items': [], 'has_more': false});
      }
      return _json({'ok': true, 'cursor': 10, 'items': []});
    });
    addTearDown(transport.close);
    final client = LanSyncClient(repo, httpClient: transport);
    await client.synchronize(cfg);
    expect(salesRequests, 0);
    expect(taxRequests, 1);
    expect(await repo.getSetting('lan_sync_sales_cursor'), '7');
    expect(await repo.getSetting('lan_sync_products_cursor'), '7');
    expect(await db.query('sales', where: "receipt_no='NEW-CREDIT'"), isEmpty);

    // Simulate Desktop acknowledging the reviewed void. The next normal
    // incremental sync must still fetch the deferred sale after its catalog.
    await db.delete('sync_outbox', where: "kind='sale_void'");
    await client.synchronize(cfg);
    expect(salesRequests, 1);
    expect(taxRequests, 2);
    final sale = (await db.query(
      'sales',
      where: "receipt_no='NEW-CREDIT'",
    )).single;
    final customer = (await db.query('customers')).single;
    final newProduct = (await db.query(
      'products',
      where: "sku='NEW'",
    )).single;
    expect(sale['customer_id'], customer['id']);
    expect(sale['credit_outstanding_cents'], 500);
    final lines = jsonDecode(sale['lines_json'] as String) as List;
    expect(lines.single['productId'], newProduct['id']);
    expect(await repo.getSetting('lan_sync_sales_cursor'), '10');
  });
}
