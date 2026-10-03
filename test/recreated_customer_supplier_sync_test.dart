import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/sync_store.dart';

http.Response _json(Map<String, Object?> value) => http.Response(
  jsonEncode(value),
  HttpStatus.ok,
  headers: const {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recreated directory entities keep immutable mappings and history refs',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'cnkh-recreated-entities-',
      );
      final database = AppDatabase.forTesting(
        '${dir.path}/mobile.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      final remoteCustomers = <Map<String, Object?>>[
        {
          'pc_id': 'remote-c1',
          'name': 'Alice',
          'phone': '0111',
          'is_deleted': 0,
        },
      ];
      final remoteSuppliers = <Map<String, Object?>>[
        {
          'pc_id': 'remote-s1',
          'name': 'Supplier A',
          'phone': '03',
          'email': 'a@example.com',
          'is_deleted': 0,
        },
      ];
      final transport = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/health')) {
          return _json({
            'ok': true,
            'protocol': 1,
            'cursor': 7,
            'capabilities': ['mutations_v1'],
          });
        }
        if (request.method == 'POST' && path.endsWith('/mutations')) {
          final body = jsonDecode(request.body) as Map;
          final operations = body['operations'] as List;
          return _json({
            'ok': true,
            'acknowledged': [for (final op in operations) (op as Map)['id']],
          });
        }
        if (request.method == 'POST' && path.endsWith('/sales')) {
          final body = jsonDecode(request.body) as Map;
          return _json({
            'ok': true,
            'receipts': [
              for (final raw in body['sales'] as List)
                {
                  'client_sale_id': (raw as Map)['client_sale_id'],
                  'receipt_no': raw['receipt_no'],
                },
            ],
          });
        }
        if (path.endsWith('/customers')) {
          return _json({'ok': true, 'cursor': 7, 'items': remoteCustomers});
        }
        if (path.endsWith('/suppliers')) {
          return _json({'ok': true, 'cursor': 7, 'items': remoteSuppliers});
        }
        if (path.endsWith('/sales')) {
          return _json({'ok': true, 'cursor': 7, 'items': []});
        }
        return _json({'ok': true, 'cursor': 7, 'items': []});
      });

      const product = Product(
        id: 'p1',
        sku: 'P1',
        barcode: '10001',
        nameZh: '商品',
        nameEn: 'Product',
        priceCents: 100,
        costCents: 50,
        stock: 20,
      );
      const config = LanSyncConfig(
        baseUrl: 'http://127.0.0.1:8787',
        token: 'test',
      );

      try {
        final db = await database.db;
        await db.insert('products', product.toMap());
        final sync = LanSyncClient(
          repo,
          database: database,
          httpClient: transport,
        );
        await sync.synchronize(config, full: true);
        final originalCustomerId = await mappedLocalId(
          db,
          'customer',
          'remote-c1',
        );
        final originalSupplierId = await mappedLocalId(
          db,
          'supplier',
          'remote-s1',
        );
        expect(originalCustomerId, isNotNull);
        expect(originalSupplierId, isNotNull);

        final sale = await repo.createSale(
          cart: CartState(items: [CartItem(product: product)]),
          paymentMethod: 'CASH',
          paidCents: 100,
          cashier: 'admin',
          customer: Customer(
            id: originalCustomerId!,
            name: 'Alice',
            phone: '0111',
          ),
        );
        await repo.createPurchase(
          supplierId: originalSupplierId!,
          supplierName: 'Supplier A',
          lines: const [
            {'productId': 'p1', 'qty': 2, 'unitCostCents': 50},
          ],
          totalCents: 100,
          operator: 'admin',
        );
        final purchase = (await db.query('purchases')).single;

        remoteCustomers
          ..clear()
          ..addAll([
            {
              'pc_id': 'remote-c1',
              'name': 'Alice',
              'phone': '0111',
              'is_deleted': 1,
            },
            {
              'pc_id': 'remote-c2',
              'name': 'Alice',
              'phone': '0111',
              'is_deleted': 0,
            },
          ]);
        remoteSuppliers
          ..clear()
          ..addAll([
            {
              'pc_id': 'remote-s1',
              'name': 'Supplier A',
              'phone': '03',
              'email': 'a@example.com',
              'is_deleted': 1,
            },
            {
              'pc_id': 'remote-s2',
              'name': 'Supplier A',
              'phone': '03',
              'email': 'a@example.com',
              'is_deleted': 0,
            },
          ]);

        await sync.synchronize(config, full: true);
        await sync.synchronize(
          config,
        ); // repeated incremental delivery is idempotent
        await sync.synchronize(config, full: true);

        final recreatedCustomerId = await mappedLocalId(
          db,
          'customer',
          'remote-c2',
        );
        final recreatedSupplierId = await mappedLocalId(
          db,
          'supplier',
          'remote-s2',
        );
        expect(recreatedCustomerId, isNot(originalCustomerId));
        expect(recreatedSupplierId, isNot(originalSupplierId));
        expect(
          await mappedLocalId(db, 'customer', 'remote-c1'),
          originalCustomerId,
        );
        expect(
          await mappedLocalId(db, 'supplier', 'remote-s1'),
          originalSupplierId,
        );
        expect(
          (await db.query(
            'customers',
            where: 'id=?',
            whereArgs: [originalCustomerId],
          )).single['is_deleted'],
          1,
        );
        expect(
          (await db.query(
            'suppliers',
            where: 'id=?',
            whereArgs: [originalSupplierId],
          )).single['is_deleted'],
          1,
        );
        expect(
          (await db.query(
            'customers',
            where: 'id=?',
            whereArgs: [recreatedCustomerId],
          )).single['is_deleted'],
          0,
        );
        expect(
          (await db.query(
            'suppliers',
            where: 'id=?',
            whereArgs: [recreatedSupplierId],
          )).single['is_deleted'],
          0,
        );
        expect(
          (await db.query(
            'sales',
            where: 'id=?',
            whereArgs: [sale.id],
          )).single['customer_id'],
          originalCustomerId,
        );
        expect(
          (await db.query(
            'purchases',
            where: 'id=?',
            whereArgs: [purchase['id']],
          )).single['supplier_id'],
          originalSupplierId,
        );
      } finally {
        transport.close();
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
