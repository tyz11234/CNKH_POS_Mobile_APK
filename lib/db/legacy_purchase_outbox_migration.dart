import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class _LegacyOutboxItem {
  const _LegacyOutboxItem({
    required this.id,
    required this.kind,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    required this.rank,
  });

  final String id;
  final String kind;
  final String entityId;
  final Map<String, Object?> payload;
  final String createdAt;
  final int rank;
}

bool _wasQueued(List<Map<String, Object?>> rows, String kind, String entityId) =>
    rows.any((row) => row['kind'] == kind && row['entity_id'] == entityId);

Future<List<Map<String, Object?>>> _normalizeLegacySaleOutbox(
  DatabaseExecutor db,
) async {
  final rows = await db.query('sync_outbox', orderBy: 'seq ASC');
  for (final row in rows.where((row) => row['kind'] == 'sale')) {
    final entityId = row['entity_id']?.toString() ?? '';
    var sales = await db.query(
      'sales',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [entityId],
      limit: 1,
    );
    if (sales.isEmpty) {
      sales = await db.query(
        'sales',
        columns: const ['id'],
        where: 'receipt_no=?',
        whereArgs: [entityId],
        limit: 1,
      );
    }
    if (sales.isEmpty) {
      await db.update(
        'sync_outbox',
        {'last_error': '旧版销售操作缺少本地销售记录，已保留待人工核对'},
        where: 'id=?',
        whereArgs: [row['id']],
      );
      continue;
    }
    final saleId = sales.single['id'] as String;
    await db.update(
      'sync_outbox',
      {
        'kind': 'sale_upload',
        'entity_id': saleId,
        'payload_json': jsonEncode({'sale_id': saleId}),
      },
      where: 'id=?',
      whereArgs: [row['id']],
    );
  }
  return db.query('sync_outbox', orderBy: 'seq ASC');
}

Future<void> _sortOutboxChronologically(
  DatabaseExecutor db,
  List<Map<String, Object?>> originalOrder,
) async {
  final rows = await db.query('sync_outbox', orderBy: 'seq ASC');
  if (rows.length < 2) return;
  DateTime instant(Object? raw, int fallback) =>
      DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(fallback, isUtc: true);
  int compare(Map<String, Object?> a, Map<String, Object?> b) {
    final byTime = instant(a['created_at'], 0).compareTo(instant(b['created_at'], 0));
    if (byTime != 0) return byTime;
    return ((a['seq'] as num?)?.toInt() ?? 0)
        .compareTo((b['seq'] as num?)?.toInt() ?? 0);
  }
  final byId = {for (final row in rows) '${row['id']}': row};
  final edges = <String, Set<String>>{};
  final incoming = {for (final id in byId.keys) id: 0};
  void link(String from, String to) {
    if (from == to || !byId.containsKey(from) || !byId.containsKey(to)) return;
    if ((edges[from] ??= {}).add(to)) incoming[to] = incoming[to]! + 1;
  }
  // Preserve the order of every operation that was already durable.
  for (var i = 1; i < originalOrder.length; i++) {
    link('${originalOrder[i - 1]['id']}', '${originalOrder[i]['id']}');
  }
  final catalog = rows.where((r) => '${r['id']}'.startsWith('legacy-catalog:')).toList()..sort(compare);
  for (var i = 1; i < catalog.length; i++) link('${catalog[i - 1]['id']}', '${catalog[i]['id']}');
  if (catalog.isNotEmpty) {
    for (final row in rows.where((r) => !'${r['id']}'.startsWith('legacy-catalog:'))) {
      link('${catalog.last['id']}', '${row['id']}');
    }
  }
  final ledgerOrder = <String, int>{};
  final purchases = {for (final row in await db.query('purchases')) '${row['id']}': row};
  final sales = {for (final row in await db.query('sales')) '${row['id']}': row};
  final moves = await db.rawQuery('SELECT rowid AS ledger_order,* FROM stock_moves ORDER BY rowid');
  final movePositions = <String, int>{};
  final moveIds = <String, int>{};
  for (final move in moves) {
    final position = (move['ledger_order'] as num).toInt();
    var notes = '${move['notes']}';
    if (move['reason'] == 'purchase_reversal' && notes.contains(' · ')) notes = notes.split(' · ').first;
    movePositions.putIfAbsent('${move['reason']}:$notes', () => position);
    moveIds['${move['id']}'] = position;
  }
  for (final row in rows) {
    final id = '${row['id']}';
    final entityId = '${row['entity_id']}';
    final kind = row['kind'];
    final position = switch (kind) {
      'purchase' => movePositions['purchase:${purchases[entityId]?['purchase_no']}'],
      'purchase_reverse' => movePositions['purchase_reversal:${purchases[entityId]?['purchase_no']}'],
      'sale_upload' => movePositions['sale:${sales[entityId]?['receipt_no']}'],
      'sale_void' => movePositions['sale_void:${sales[entityId]?['receipt_no']}'],
      'stocktake' => id.startsWith('legacy-stocktake:') ? moveIds[id.substring('legacy-stocktake:'.length)] : null,
      _ => null,
    };
    if (position != null) ledgerOrder[id] = position;
    if (kind == 'purchase_reverse' || kind == 'purchase_attachment') {
      for (final dependency in rows.where((r) => r['kind'] == 'purchase' && r['entity_id'] == entityId)) {
        link('${dependency['id']}', id);
      }
    } else if (kind == 'sale_void') {
      for (final dependency in rows.where((r) => r['kind'] == 'sale_upload' && r['entity_id'] == entityId)) {
        link('${dependency['id']}', id);
      }
    }
  }
  final inventory = ledgerOrder.keys.toList()..sort((a, b) => ledgerOrder[a]!.compareTo(ledgerOrder[b]!));
  for (var i = 1; i < inventory.length; i++) link(inventory[i - 1], inventory[i]);
  final ready = rows.where((r) => incoming['${r['id']}'] == 0).toList();
  final ordered = <Map<String, Object?>>[];
  while (ready.isNotEmpty) {
    ready.sort(compare);
    final next = ready.removeAt(0);
    ordered.add(next);
    for (final id in edges['${next['id']}'] ?? const <String>{}) {
      incoming[id] = incoming[id]! - 1;
      if (incoming[id] == 0) ready.add(byId[id]!);
    }
  }
  if (ordered.length != rows.length) {
    await db.update('sync_outbox', {
      'delivery_state': 'needs_review',
      'last_error': '旧版队列与库存流水顺序冲突；操作已保留，请人工核对后同步',
    }, where: 'id=?', whereArgs: [rows.first['id']]);
    return;
  }
  final maxSeq = rows.fold<int>(0, (max, row) {
    final value = (row['seq'] as num?)?.toInt() ?? 0;
    return value > max ? value : max;
  });
  final offset = maxSeq + rows.length + 1;
  await db.rawUpdate('UPDATE sync_outbox SET seq=seq+?', [offset]);
  for (var i = 0; i < ordered.length; i++) {
    await db.update(
      'sync_outbox',
      {'seq': i + 1},
      where: 'id=?',
      whereArgs: [ordered[i]['id']],
    );
  }
  final definition = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='sync_outbox'",
  );
  if (definition.isNotEmpty &&
      '${definition.single['sql']}'.toUpperCase().contains('AUTOINCREMENT')) {
    final sequenceTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'",
    );
    if (sequenceTable.isNotEmpty) {
      final updated = await db.rawUpdate(
        "UPDATE sqlite_sequence SET seq=? WHERE name='sync_outbox'",
        [ordered.length],
      );
      if (updated == 0) {
        await db.insert('sqlite_sequence', {
          'name': 'sync_outbox',
          'seq': ordered.length,
        });
      }
    }
  }
}

/// Recover purchases and sales created by pre-v10 builds while the phone had
/// never been paired. Those builds skipped queueMutation without a Desktop
/// address. Stable operation IDs and one chronological Outbox preserve local
/// purchase/sale/reversal order across first pairing and migration retries.
Future<void> enqueueLegacyUnpairedPurchases(DatabaseExecutor db) async {
  final existingOutbox = await _normalizeLegacySaleOutbox(db);
  final host = await db.query(
    'settings',
    columns: const ['value'],
    where: 'key=?',
    whereArgs: const ['lan_sync_host'],
    limit: 1,
  );
  if (host.isNotEmpty && '${host.single['value']}'.trim().isNotEmpty) return;
  final pairedBefore = await db.query('settings', where: 'key=? AND value<>?',
    whereArgs: ['lan_sync_last_pull', ''], limit: 1);
  final mappings = await db.query('sync_entity_ids', columns: ['entity'], limit: 1);
  if (pairedBefore.isNotEmpty || mappings.isNotEmpty) return;

  final existingIds = existingOutbox.map((row) => '${row['id']}').toSet();
  final recovered = <_LegacyOutboxItem>[];
  final purchases = await db.query('purchases', orderBy: 'rowid ASC');
  for (final purchase in purchases) {
    final id = purchase['id']?.toString() ?? '';
    if (id.isEmpty || purchase['source'] == 'desktop_sync') continue;
    final purchaseQueued = _wasQueued(existingOutbox, 'purchase', id);
    if (!purchaseQueued) {
      Object? decoded;
      try {
        decoded = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
      } catch (_) {
        decoded = null;
      }
      final lines = <Map<String, Object?>>[];
      var invalidLines = decoded is! List || decoded.isEmpty;
      if (decoded is List) {
        for (final raw in decoded) {
          if (raw is! Map) {
            invalidLines = true;
            continue;
          }
          final line = Map<String, Object?>.from(raw);
          final localProductId =
              (line['productId'] ?? line['product_id'])?.toString() ?? '';
          if (localProductId.isEmpty) {
            invalidLines = true;
            continue;
          }
          final product = await db.query(
            'products',
            columns: const ['sku', 'barcode'],
            where: 'id=?',
            whereArgs: [localProductId],
            limit: 1,
          );
          final mapping = await db.query(
            'sync_entity_ids',
            columns: const ['remote_id'],
            where: "entity='product' AND local_id=?",
            whereArgs: [localProductId],
            limit: 1,
          );
          lines.add({
            ...line,
            'productId': mapping.isEmpty
                ? localProductId
                : mapping.single['remote_id'],
            'qty': line['qty'] ?? line['quantity'],
            if (product.isNotEmpty) 'productSku': product.single['sku'],
            if (product.isNotEmpty) 'productBarcode': product.single['barcode'],
          });
        }
      }
      // Never upload a partial invoice. Keep a visible, rejected Outbox entry
      // so staff can recover malformed legacy history without losing it.
      if (invalidLines) lines.clear();
      final supplierId = purchase['supplier_id']?.toString() ?? '';
      final supplierMap = await db.query(
        'sync_entity_ids',
        columns: const ['remote_id'],
        where: "entity='supplier' AND local_id=?",
        whereArgs: [supplierId],
        limit: 1,
      );
      final supplier = supplierId.isEmpty
          ? <Map<String, Object?>>[]
          : await db.query(
              'suppliers',
              columns: const ['phone'],
              where: 'id=?',
              whereArgs: [supplierId],
              limit: 1,
            );
      final payload = <String, Object?>{
        'id': id,
        'purchase_no': purchase['purchase_no'],
        'purchased_at': purchase['purchased_at'],
        'supplier_id': supplierMap.isEmpty
            ? supplierId
            : supplierMap.single['remote_id'],
        'supplier_name': purchase['supplier_name'],
        'supplier_phone': supplier.isEmpty ? '' : supplier.single['phone'],
        'lines': lines,
        'total_cents': purchase['total_cents'],
        'operator': 'mobile-legacy-migration',
        'notes': purchase['notes'] ?? '',
        'invoice_no': purchase['invoice_no'] ?? '',
        'invoice_date': purchase['invoice_date'] ?? '',
        'discount_cents': purchase['discount_cents'] ?? 0,
        'tax_cents': purchase['tax_cents'] ?? 0,
        'delivery_fee_cents': purchase['delivery_fee_cents'] ?? 0,
        'other_fee_cents': purchase['other_fee_cents'] ?? 0,
        'source': purchase['source'] ?? 'manual',
        'draft_id': purchase['draft_id'],
        'ocr_raw_text': purchase['ocr_raw_text'] ?? '',
      };
      if (purchase['source'] == 'ocr') {
        final overrides = await db.query(
          'purchase_audit_log',
          columns: const ['details'],
          where: "purchase_id=? AND action='duplicate_invoice_override'",
          whereArgs: [id],
          orderBy: 'occurred_at DESC',
          limit: 1,
        );
        if (overrides.isNotEmpty) {
          payload['duplicate_override'] = true;
          payload['duplicate_override_reason'] =
              '${overrides.single['details'] ?? ''}'.trim();
        }
      }
      recovered.add(_LegacyOutboxItem(
        id: 'legacy-purchase:$id',
        kind: 'purchase',
        entityId: id,
        payload: payload,
        createdAt: purchase['purchased_at']?.toString() ?? '',
        rank: 0,
      ));
    }

    if ((purchase['reversed'] as num?)?.toInt() == 1 &&
        !_wasQueued(existingOutbox, 'purchase_reverse', id)) {
      recovered.add(_LegacyOutboxItem(
        id: 'legacy-purchase-reverse:$id',
        kind: 'purchase_reverse',
        entityId: id,
        payload: {
          'purchase_id': id,
          'operator': purchase['reversed_by'] ?? 'mobile-legacy-migration',
          'reason': purchase['reversal_reason'] ?? 'legacy offline reversal',
          'notes': purchase['reversal_notes'] ?? '',
        },
        createdAt: purchase['reversed_at']?.toString() ??
            purchase['purchased_at']?.toString() ?? '',
        rank: 3,
      ));
    }
  }

  final sales = await db.query(
    'sales',
    where: "synced_at IS NULL OR synced_at=''",
    orderBy: 'sold_at ASC,rowid ASC',
  );
  for (final sale in sales) {
    final id = sale['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    if (!_wasQueued(existingOutbox, 'sale_upload', id)) {
      recovered.add(_LegacyOutboxItem(
        id: 'legacy-sale-upload:$id',
        kind: 'sale_upload',
        entityId: id,
        payload: {'sale_id': id},
        createdAt: sale['sold_at']?.toString() ?? '',
        rank: 1,
      ));
    }
    if ((sale['voided'] as num?)?.toInt() == 1 &&
        !_wasQueued(existingOutbox, 'sale_void', id)) {
      final voidMoves = await db.query(
        'stock_moves',
        columns: const ['created_at'],
        where: "reason='sale_void' AND notes=?",
        whereArgs: [sale['receipt_no']],
        orderBy: 'rowid ASC',
        limit: 1,
      );
      recovered.add(_LegacyOutboxItem(
        id: 'legacy-sale-void:$id',
        kind: 'sale_void',
        entityId: id,
        payload: {
          'client_sale_id': id,
          'receipt_no': sale['receipt_no'],
          'note': sale['void_note'] ?? 'legacy offline void',
        },
        createdAt: voidMoves.isEmpty
            ? sale['sold_at']?.toString() ?? ''
            : voidMoves.single['created_at']?.toString() ?? '',
        rank: 2,
      ));
    }
  }

  // Legacy stocktake operations were also skipped before pairing. Rebuild
  // their before/after values by walking the append-only stock ledger
  // backwards from each product's current stock, then queue them in ledger
  // order with the purchases and sales above.
  final moves = await db.query('stock_moves', orderBy: 'rowid ASC');
  final movesByProduct = <String, List<Map<String, Object?>>>{};
  for (final move in moves) {
    final productId = move['product_id']?.toString() ?? '';
    if (productId.isNotEmpty) (movesByProduct[productId] ??= []).add(move);
  }
  for (final entry in movesByProduct.entries) {
    final products = await db.query(
      'products',
      columns: const ['stock', 'sku', 'barcode'],
      where: 'id=?',
      whereArgs: [entry.key],
      limit: 1,
    );
    if (products.isEmpty) continue;
    var after = (products.single['stock'] as num?)?.toDouble() ?? 0;
    for (final move in entry.value.reversed) {
      final change = move['change'];
      if (change is! num || !change.isFinite) continue;
      final before = after - change.toDouble();
      if (move['reason'] == 'stocktake' || move['reason'] == 'product_edit') {
        final moveId = move['id']?.toString() ?? '';
        final operationId = 'legacy-stocktake:$moveId';
        if (moveId.isNotEmpty && !existingIds.contains(operationId)) {
          final mappings = await db.query(
            'sync_entity_ids',
            columns: const ['remote_id'],
            where: "entity='product' AND local_id=?",
            whereArgs: [entry.key],
            limit: 1,
          );
          recovered.add(_LegacyOutboxItem(
            id: operationId,
            kind: 'stocktake',
            entityId: entry.key,
            payload: {
              'product_id': mappings.isEmpty
                  ? entry.key
                  : mappings.single['remote_id'],
              'productSku': products.single['sku'],
              'productBarcode': products.single['barcode'],
              'before_stock': before,
              'stock': after,
              'operator': move['operator'] ?? 'mobile-legacy-migration',
              'reason': move['reason'] ?? 'stocktake',
              'notes': move['notes'] ?? '',
            },
            createdAt: move['created_at']?.toString() ?? '',
            rank: 1,
          ));
        }
      }
      after = before;
    }
  }

  // A never-paired phone may also have products absent from Desktop. Upload
  // their pre-operation baseline, not today's stock (which already includes
  // the purchases/sales that will be replayed next).
  final productIds = <String>{};
  final unverifiedPurchases = <String>{};
  final unverifiedProducts = <String>{};
  void collectLines(Object? raw) {
    try {
      final lines = jsonDecode(raw?.toString() ?? '[]');
      if (lines is List) {
        for (final line in lines.whereType<Map>()) {
          final id = (line['productId'] ?? line['product_id'])?.toString() ?? '';
          if (id.isNotEmpty) productIds.add(id);
        }
      }
    } catch (_) { /* The malformed business operation remains queued. */ }
  }
  for (final purchase in purchases) {
    collectLines(purchase['lines_json']);
    try {
      final quantities = <String, double>{};
      for (final line in (jsonDecode(purchase['lines_json'] as String) as List).whereType<Map>()) {
        final id = (line['productId'] ?? line['product_id'])?.toString() ?? '';
        final qty = line['qty'] ?? line['quantity'];
        if (id.isEmpty || qty is! num || !qty.isFinite || qty <= 0) {
          if (id.isNotEmpty) unverifiedProducts.add(id);
          throw const FormatException('invalid legacy line');
        }
        quantities[id] = (quantities[id] ?? 0) + qty.toDouble();
      }
      if (quantities.isEmpty) throw const FormatException('empty legacy purchase');
      for (final entry in quantities.entries) {
        final recorded = moves.where((m) => m['product_id'] == entry.key &&
          m['reason'] == 'purchase' && m['notes'] == purchase['purchase_no'])
          .fold<double>(0, (sum, m) => sum + (m['change'] as num).toDouble());
        if (!recorded.isFinite || (recorded - entry.value).abs() > 0.0000001) {
          unverifiedPurchases.add('${purchase['id']}');
          unverifiedProducts.add(entry.key);
        }
      }
    } catch (_) {
      unverifiedPurchases.add('${purchase['id']}');
    }
  }
  for (final sale in sales) collectLines(sale['lines_json']);
  for (final move in moves.where((r) => ['stocktake','product_edit'].contains(r['reason']))) {
    productIds.add('${move['product_id']}');
  }
  for (final id in productIds) {
    if (_wasQueued(existingOutbox, 'product_upsert', id)) continue;
    final products = await db.query('products', where: 'id=?', whereArgs: [id], limit: 1);
    if (products.isEmpty) continue;
    final product = products.single;
    final delta = moves.where((r) => r['product_id'] == id).fold<double>(0,
      (sum, move) => sum + (move['change'] as num).toDouble());
    final initialStock = (product['stock'] as num).toDouble() - delta;
    if (!initialStock.isFinite) continue;
    int? initialCost;
    for (final purchase in purchases) {
      try {
        for (final line in (jsonDecode(purchase['lines_json'] as String) as List).whereType<Map>()) {
          if (line['productId'] == id && line['beforeCostCents'] is num) {
            initialCost ??= (line['beforeCostCents'] as num).toInt();
          }
        }
      } catch (_) { /* Old missing cost snapshots are not invented. */ }
    }
    recovered.add(_LegacyOutboxItem(
      id: 'legacy-catalog:product:$id', kind: 'product_upsert', entityId: id,
      payload: {'row': {...product, 'stock': initialStock,
        if (initialCost != null) 'cost_cents': initialCost, 'image_path': ''}, 'before': null},
      createdAt: '1970-01-01T00:00:00Z', rank: -1,
    ));
  }
  for (final entry in <String, List<Map<String, Object?>>>{'supplier': purchases, 'customer': sales}.entries) {
    final table = entry.key == 'supplier' ? 'suppliers' : 'customers';
    final ids = entry.value.map((r) => r['${entry.key}_id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    for (final id in ids) {
      if (_wasQueued(existingOutbox, '${entry.key}_upsert', id)) continue;
      final rows = await db.query(table, where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) continue;
      recovered.add(_LegacyOutboxItem(
        id: 'legacy-catalog:${entry.key}:$id', kind: '${entry.key}_upsert', entityId: id,
        payload: {'row': rows.single, 'before': null}, createdAt: '1970-01-01T00:00:00Z', rank: -1,
      ));
    }
  }

  DateTime instant(String value) => DateTime.tryParse(value)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  recovered.sort((a, b) {
    final byTime = instant(a.createdAt).compareTo(instant(b.createdAt));
    if (byTime != 0) return byTime;
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return a.id.compareTo(b.id);
  });
  for (final item in recovered) {
    await db.insert(
      'sync_outbox',
      {
        'id': item.id,
        'kind': item.kind,
        'entity_id': item.entityId,
        'payload_json': jsonEncode(item.payload),
        'created_at': item.createdAt.isEmpty
            ? DateTime.now().toUtc().toIso8601String()
            : item.createdAt,
        if (item.kind == 'purchase' && unverifiedPurchases.contains(item.entityId))
          'delivery_state': 'needs_review',
        if (item.kind == 'purchase' && unverifiedPurchases.contains(item.entityId))
          'last_error': '旧进货的数量与库存流水无法核实，原记录和操作已保留；请人工核对，不能自动重放库存',
        if (item.kind == 'product_upsert' && unverifiedProducts.contains(item.entityId))
          'delivery_state': 'needs_review',
        if (item.kind == 'product_upsert' && unverifiedProducts.contains(item.entityId))
          'last_error': '旧商品库存基线无法核实，原记录和操作已保留；请人工核对后同步',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  await _sortOutboxChronologically(db, existingOutbox);
}
