import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer and supplier CRUD sync', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_entity_crud_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
      final db = await database.db;
      await db.insert(
        'settings',
        {'key': 'lan_sync_host', 'value': 'http://127.0.0.1:8765'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    Future<List<Map<String, Object?>>> outbox(String kind, String id) async {
      final db = await database.db;
      return db.query(
        'sync_outbox',
        where: 'kind=? AND entity_id=?',
        whereArgs: [kind, id],
        orderBy: 'seq ASC',
      );
    }

    test('customer edit preserves ID and queues updated business data', () async {
      const id = 'customer-1';
      await repo.upsertCustomer(
        const Customer(id: id, name: 'Alice', phone: '011', notes: 'old'),
      );
      await repo.upsertCustomer(
        const Customer(id: id, name: 'Alice Tan', phone: '012', notes: 'VIP'),
      );

      final active = await repo.listCustomers();
      expect(active, hasLength(1));
      expect(active.single.id, id);
      expect(active.single.name, 'Alice Tan');
      expect(active.single.phone, '012');
      expect(active.single.notes, 'VIP');

      final queued = await outbox('customer_upsert', id);
      expect(queued.length, 2);
      final payload = jsonDecode(queued.last['payload_json'] as String) as Map;
      final row = Map<String, dynamic>.from(payload['row'] as Map);
      expect(row['id'], id);
      expect(row['name'], 'Alice Tan');
      expect(row['phone'], '012');
      expect(row['is_deleted'], 0);
    });

    test('customer soft delete hides active row but preserves history row and syncs tombstone',
        () async {
      const id = 'customer-delete';
      await repo.upsertCustomer(
        const Customer(id: id, name: 'Keep History', phone: '013'),
      );
      await repo.softDeleteCustomer(id);

      expect((await repo.listCustomers()).where((c) => c.id == id), isEmpty);
      final db = await database.db;
      final stored = await db.query('customers', where: 'id=?', whereArgs: [id]);
      expect(stored, hasLength(1));
      expect(stored.single['is_deleted'], 1);

      final queued = await outbox('customer_upsert', id);
      final payload = jsonDecode(queued.last['payload_json'] as String) as Map;
      final row = Map<String, dynamic>.from(payload['row'] as Map);
      expect(row['is_deleted'], 1);
    });

    test('supplier edit preserves ID and includes email/notes in sync payload', () async {
      const id = 'supplier-1';
      await repo.upsertSupplier(
        const Supplier(
          id: id,
          name: 'ABC Trading',
          phone: '03',
          email: 'old@example.com',
          notes: 'old',
        ),
      );
      await repo.upsertSupplier(
        const Supplier(
          id: id,
          name: 'ABC Trading Sdn Bhd',
          phone: '04',
          email: 'sales@example.com',
          notes: 'preferred',
        ),
      );

      final active = await repo.listSuppliers();
      expect(active, hasLength(1));
      expect(active.single.id, id);
      expect(active.single.name, 'ABC Trading Sdn Bhd');
      expect(active.single.email, 'sales@example.com');
      expect(active.single.notes, 'preferred');

      final queued = await outbox('supplier_upsert', id);
      expect(queued.length, 2);
      final payload = jsonDecode(queued.last['payload_json'] as String) as Map;
      final row = Map<String, dynamic>.from(payload['row'] as Map);
      expect(row['id'], id);
      expect(row['email'], 'sales@example.com');
      expect(row['notes'], 'preferred');
      expect(row['is_deleted'], 0);
    });

    test('batch supplier soft delete preserves rows and queues one tombstone per supplier',
        () async {
      const ids = ['supplier-a', 'supplier-b', 'supplier-c'];
      for (final id in ids) {
        await repo.upsertSupplier(Supplier(id: id, name: id));
      }
      for (final id in ids) {
        await repo.softDeleteSupplier(id);
      }

      expect(await repo.listSuppliers(), isEmpty);
      final db = await database.db;
      for (final id in ids) {
        final stored = await db.query('suppliers', where: 'id=?', whereArgs: [id]);
        expect(stored.single['is_deleted'], 1);
        final queued = await outbox('supplier_upsert', id);
        expect(queued.length, 2);
        final payload = jsonDecode(queued.last['payload_json'] as String) as Map;
        final row = Map<String, dynamic>.from(payload['row'] as Map);
        expect(row['is_deleted'], 1);
      }
    });
  });
}
