import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../db/app_database.dart';
import '../models/product.dart';
import 'pos_repository.dart';
import 'sync_store.dart';
import 'product_images.dart';

const String kPairingPrefix = 'cnkh-sync:v1|';

enum SyncLinkState { offline, connected, pending }

class LanSyncConfig {
  final String baseUrl;
  final String token;
  final String name;
  const LanSyncConfig({
    required this.baseUrl,
    this.token = '',
    this.name = 'CNKH-PC',
  });

  String get normalizedBase {
    var u = baseUrl.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri get wsUri {
    final base = Uri.parse(normalizedBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final qp = <String, String>{};
    if (token.trim().isNotEmpty) qp['token'] = token.trim();
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/v1/ws',
      queryParameters: qp.isEmpty ? null : qp,
    );
  }
}

class PairingExpiredException implements Exception {
  final String message;
  PairingExpiredException([this.message = 'pairing QR expired']);
  @override
  String toString() => message;
}

/// Parse pairing QR: `cnkh-sync:v1|{json}` or raw JSON with baseUrl.
LanSyncConfig? parsePairingQr(String raw) {
  var text = raw.trim();
  if (text.startsWith(kPairingPrefix)) {
    text = text.substring(kPairingPrefix.length);
  } else if (text.startsWith('cnkh-sync:')) {
    final pipe = text.indexOf('|');
    if (pipe < 0) return null;
    text = text.substring(pipe + 1);
  }
  try {
    final data = jsonDecode(text);
    if (data is! Map) return null;
    final base = (data['baseUrl'] ?? data['base_url'] ?? '').toString().trim();
    if (base.isEmpty) return null;
    final exp = data['exp'];
    if (exp != null) {
      final expSec = exp is int ? exp : int.tryParse('$exp');
      if (expSec != null &&
          expSec < DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        throw PairingExpiredException(
          '配对码已过期 / Pairing QR expired — ask PC to refresh',
        );
      }
    }
    return LanSyncConfig(
      baseUrl: base,
      token: (data['token'] ?? '').toString(),
      name: (data['name'] ?? 'CNKH-PC').toString(),
    );
  } on PairingExpiredException {
    rethrow;
  } catch (_) {
    return null;
  }
}

bool looksLikePairingPayload(String raw) {
  final t = raw.trim();
  if (t.startsWith(kPairingPrefix) || t.startsWith('cnkh-sync:')) return true;
  if (t.startsWith('{') && t.contains('baseUrl')) {
    return parsePairingQr(t) != null;
  }
  return false;
}

class LanSyncClient {
  LanSyncClient(this.repo, {AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final PosRepository repo;
  final AppDatabase _db;
  String? lastError;
  static final Expando<AsyncMutex> _mutexes = Expando<AsyncMutex>();
  AsyncMutex get _mutex => _mutexes[_db] ??= AsyncMutex();
  Future<String> pullCatalog(LanSyncConfig cfg) => synchronize(cfg);
  Future<String> pullSales(LanSyncConfig cfg) => synchronize(cfg);
  Future<String> pushSales(LanSyncConfig cfg) => _mutex.run(() async {
    await _drainPending(cfg);
    return '待同步操作已上传';
  });
  Future<String> synchronize(
    LanSyncConfig cfg, {
    bool full = false,
  }) => _mutex.run(() async {
    final h = await health(cfg);
    if (h['ok'] != true || h['protocol'] != 1) throw StateError('不兼容的电脑同步协议');
    if (h['stock_policy'] != null)
      await repo.setSetting('stock_policy', '${h['stock_policy']}');
    final d = await _db.db;
    final pending =
        Sqflite.firstIntValue(
          await d.rawQuery('SELECT COUNT(*) FROM sync_outbox'),
        ) ??
        0;
    if (pending > 0 &&
        !(h['capabilities'] as List? ?? []).contains('mutations_v1'))
      throw StateError('请先更新电脑端，手机待同步数据已保留');
    await _drainPending(cfg);
    final cursor = (h['cursor'] as num?)?.toInt();
    for (final key in ['lan_sync_products_cursor', 'lan_sync_sales_cursor']) {
      if (full ||
          (cursor != null &&
              (int.tryParse(await repo.getSetting(key)) ?? 0) > cursor))
        await repo.setSetting(key, '');
    }
    final a = await _pullCatalog(cfg);
    final b = await _pullSales(cfg);
    await pushBarcodeQueue(cfg);
    await repo.setSetting('lan_sync_last_error', '');
    return '$a\n$b';
  });
  Future<void> _drainPending(LanSyncConfig cfg) async {
    final d = await _db.db;
    while ((Sqflite.firstIntValue(
              await d.rawQuery(
                "SELECT COUNT(*) FROM sales s WHERE (s.synced_at IS NULL OR s.synced_at='') AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.kind='sale_upload' AND o.entity_id=s.id)",
              ),
            ) ??
            0) >
        0) {
      await _pushSales(cfg, legacyOnly: true);
    }
    while (true) {
      final rows = await d.query('sync_outbox', orderBy: 'seq ASC', limit: 1);
      if (rows.isEmpty) break;
      final op = rows.first;
      try {
        if (op['kind'] == 'sale_upload') {
          await _pushSales(
            cfg,
            onlyId: op['entity_id'] as String,
            originalState: true,
          );
        } else {
          final res = await http
              .post(
                Uri.parse('${cfg.normalizedBase}/api/v1/mutations'),
                headers: _headers(cfg),
                body: jsonEncode({
                  'operations': [
                    {
                      'id': op['id'],
                      'kind': op['kind'],
                      'payload': jsonDecode(op['payload_json'] as String),
                    },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 45));
          final body =
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          if (body['ok'] != true ||
              !(body['acknowledged'] as List? ?? []).contains(op['id']))
            throw StateError('${body['error'] ?? '操作未获电脑确认'}');
        }
        await d.delete('sync_outbox', where: 'id=?', whereArgs: [op['id']]);
      } catch (e) {
        await d.update(
          'sync_outbox',
          {'last_error': '$e'},
          where: 'id=?',
          whereArgs: [op['id']],
        );
        lastError = '$e';
        await repo.setSetting('lan_sync_last_error', '$e');
        rethrow;
      }
    }
  }

  Map<String, String> _headers(LanSyncConfig cfg) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (cfg.token.trim().isNotEmpty) {
      h['X-CNKH-Token'] = cfg.token.trim();
    }
    return h;
  }

  Future<Map<String, dynamic>> health(LanSyncConfig cfg) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/health');
    final res = await http
        .get(uri, headers: _headers(cfg))
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('${body['error'] ?? 'health ${res.statusCode}'}');
    }
    return body;
  }

  Future<void> saveConfig(LanSyncConfig cfg) async {
    final old = await repo.getSetting('lan_sync_token');
    if (old.isNotEmpty && old != cfg.token)
      throw StateError('已有门店数据，请先同步并备份后再切换门店');
    await repo.setSetting('lan_sync_host', cfg.normalizedBase);
    await repo.setSetting('lan_sync_token', cfg.token);
    await repo.setSetting('lan_sync_name', cfg.name);
  }

  Future<LanSyncConfig?> loadConfig() async {
    final host = await repo.getSetting('lan_sync_host');
    if (host.trim().isEmpty) return null;
    return LanSyncConfig(
      baseUrl: host,
      token: await repo.getSetting('lan_sync_token'),
      name: await repo.getSetting('lan_sync_name', fallback: 'CNKH-PC'),
    );
  }

  Future<int> countUnsyncedSales() async {
    final d = await _db.db;
    final n =
        Sqflite.firstIntValue(
          await d.rawQuery(
            "SELECT (SELECT COUNT(*) FROM sales WHERE synced_at IS NULL OR synced_at='')+(SELECT COUNT(*) FROM sync_outbox WHERE kind<>'sale_upload')",
          ),
        ) ??
        0;
    return n;
  }

  Future<String> _pullCatalog(LanSyncConfig cfg) async {
    lastError = null;
    try {
      final since = await repo.getSetting('lan_sync_products_cursor');
      final q = since.isEmpty
          ? ''
          : '?since=${Uri.encodeQueryComponent(since)}';
      final productsUri = Uri.parse('${cfg.normalizedBase}/api/v1/products$q');
      final customersUri = Uri.parse(
        '${cfg.normalizedBase}/api/v1/customers$q',
      );
      final categoriesUri = Uri.parse(
        '${cfg.normalizedBase}/api/v1/categories$q',
      );

      final responses = await Future.wait<http.Response>([
        http
            .get(productsUri, headers: _headers(cfg))
            .timeout(const Duration(seconds: 30)),
        http
            .get(customersUri, headers: _headers(cfg))
            .timeout(const Duration(seconds: 30)),
        http
            .get(categoriesUri, headers: _headers(cfg))
            .timeout(const Duration(seconds: 30)),
      ]);

      final pBody =
          jsonDecode(utf8.decode(responses[0].bodyBytes))
              as Map<String, dynamic>;
      final cBody =
          jsonDecode(utf8.decode(responses[1].bodyBytes))
              as Map<String, dynamic>;
      final catBody =
          jsonDecode(utf8.decode(responses[2].bodyBytes))
              as Map<String, dynamic>;
      if (pBody['ok'] != true) throw StateError('products: ${pBody['error']}');
      if (cBody['ok'] != true) throw StateError('customers: ${cBody['error']}');
      if (catBody['ok'] != true)
        throw StateError('categories: ${catBody['error']}');

      final products = (pBody['items'] as List?) ?? [];
      final customers = (cBody['items'] as List?) ?? [];
      final categories = (catBody['items'] as List?) ?? [];
      final d = await _db.db;
      await d.transaction((txn) async {
        if ((Sqflite.firstIntValue(
                      await txn.rawQuery('SELECT COUNT(*) FROM sync_outbox'),
                    ) ??
                    0) >
                0 ||
            (Sqflite.firstIntValue(
                      await txn.rawQuery(
                        "SELECT COUNT(*) FROM sales WHERE synced_at IS NULL OR synced_at=''",
                      ),
                    ) ??
                    0) >
                0)
          throw StateError('本地有新操作，将在下一轮同步');
        for (final raw in categories) {
          await _upsertCategory(txn, Map<String, dynamic>.from(raw as Map));
        }
        for (final raw in products) {
          await _upsertProduct(txn, Map<String, dynamic>.from(raw as Map));
        }
        for (final raw in customers) {
          await _upsertCustomer(txn, Map<String, dynamic>.from(raw as Map));
        }
      });

      final imagesOn = await repo.productImagesEnabled();
      if (imagesOn) {
        for (final raw in products) {
          final m = Map<String, dynamic>.from(raw as Map);
          if (m['has_image'] == true && m['pc_id'] is num) {
            try {
              await pullProductImage(
                cfg,
                pcId: (m['pc_id'] as num).toInt(),
                localProductId: 'pc-${m['pc_id']}',
              );
            } catch (_) {}
          }
        }
      }

      final nextCursor = _safeCatalogCursor(
        since,
        <Map<String, dynamic>>[pBody, cBody, catBody],
        <Object?>[...products, ...customers, ...categories],
      );
      await repo.setSetting('lan_sync_products_cursor', nextCursor);
      await repo.setSetting(
        'lan_sync_last_pull',
        DateTime.now().toIso8601String(),
      );
      return 'Pulled ${products.length} products, ${customers.length} customers, ${categories.length} categories';
    } catch (e) {
      lastError = '$e';
      await repo.setSetting('lan_sync_last_error', lastError!);
      rethrow;
    }
  }

  String _safeCatalogCursor(
    String current,
    List<Map<String, dynamic>> bodies,
    Iterable<Object?> rawItems,
  ) {
    final currentNumeric = int.tryParse(current);
    final cursors = <int>[];
    for (final body in bodies) {
      final value = body['cursor'];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null) cursors.add(parsed);
    }
    if (cursors.length == bodies.length && cursors.isNotEmpty) {
      final safe = cursors.reduce(min);
      if (currentNumeric != null && safe < currentNumeric) {
        return '$currentNumeric';
      }
      return '$safe';
    }
    return _nextCursor(current, bodies, rawItems);
  }

  String _nextCursor(
    String current,
    List<Map<String, dynamic>> bodies,
    Iterable<Object?> rawItems,
  ) {
    var maxNumeric = int.tryParse(current) ?? 0;
    for (final body in bodies) {
      final value = body['cursor'];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed > maxNumeric) maxNumeric = parsed;
    }
    if (maxNumeric > 0) return '$maxNumeric';

    var maxLegacy = current;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final updated = raw['updated_at']?.toString() ?? '';
      if (updated.compareTo(maxLegacy) > 0) maxLegacy = updated;
    }
    return maxLegacy;
  }

  Future<void> _upsertProduct(
    DatabaseExecutor txn,
    Map<String, dynamic> m,
  ) async {
    final sku = (m['sku'] as String?) ?? '';
    final barcode = (m['barcode'] as String?) ?? '';
    final pcId = m['pc_id'];
    Map<String, Object?>? existing;
    final mapped = await mappedLocalId(txn, 'product', pcId);
    if (mapped != null) {
      final rows = await txn.query(
        'products',
        where: 'id=?',
        whereArgs: [mapped],
      );
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && barcode.isNotEmpty) {
      final rows = await txn.query(
        'products',
        where: 'barcode=?',
        whereArgs: [barcode],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && sku.isNotEmpty) {
      final rows = await txn.query(
        'products',
        where: 'sku=?',
        whereArgs: [sku],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && pcId != null) {
      final rows = await txn.query(
        'products',
        where: 'id IN (?,?)',
        whereArgs: ['pc-$pcId', '$pcId'],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }

    final deleted = (m['is_deleted'] as num?)?.toInt() ?? 0;
    if (deleted != 0) {
      if (existing != null) {
        await txn.update(
          'products',
          {'is_deleted': 1},
          where: 'id=?',
          whereArgs: [existing['id']],
        );
      }
      return;
    }

    final id = (existing?['id'] as String?) ?? 'pc-$pcId';
    await rememberEntityId(txn, 'product', pcId, id);
    final existingImg = (existing?['image_path'] as String?) ?? '';
    final product = Product(
      id: id,
      nameZh: (m['name_zh'] as String?) ?? (m['name'] as String?) ?? '',
      nameEn: (m['name_en'] as String?) ?? (m['name'] as String?) ?? '',
      sku: sku,
      barcode: barcode,
      priceCents: (m['price_cents'] as num?)?.toInt() ?? 0,
      costCents: (m['cost_cents'] as num?)?.toInt() ?? 0,
      stock: (m['stock'] as num?)?.toDouble() ?? 0,
      unit: (m['unit'] as String?) ?? 'pcs',
      category: (m['category'] as String?) ?? '',
      isDeleted: 0,
      imagePath: existingImg,
      reorderLevel: (m['reorder_level'] as num?)?.toDouble() ?? 0,
    );
    await txn.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertCustomer(
    DatabaseExecutor txn,
    Map<String, dynamic> m,
  ) async {
    final pcId = m['pc_id'];
    final phone = (m['phone'] as String?) ?? '';
    final name = (m['name'] as String?) ?? '';
    Map<String, Object?>? existing;
    final mapped = await mappedLocalId(txn, 'customer', pcId);
    if (mapped != null) {
      final rows = await txn.query(
        'customers',
        where: 'id=?',
        whereArgs: [mapped],
      );
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && phone.isNotEmpty) {
      final rows = await txn.query(
        'customers',
        where: 'phone=? AND name=?',
        whereArgs: [phone, name],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && name.isNotEmpty) {
      final rows = await txn.query(
        'customers',
        where: 'name=? AND phone=?',
        whereArgs: [name, phone],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && pcId != null) {
      final rows = await txn.query(
        'customers',
        where: 'id IN (?,?)',
        whereArgs: ['pc-c-$pcId', '$pcId'],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }

    final deleted = (m['is_deleted'] as num?)?.toInt() ?? 0;
    if (deleted != 0) {
      if (existing != null) {
        await txn.update(
          'customers',
          {'is_deleted': 1},
          where: 'id=?',
          whereArgs: [existing['id']],
        );
      }
      return;
    }

    final id = (existing?['id'] as String?) ?? 'pc-c-$pcId';
    await rememberEntityId(txn, 'customer', pcId, id);
    await txn.insert('customers', {
      'id': id,
      'name': name,
      'phone': phone,
      'notes': (m['notes'] as String?) ?? '',
      'is_deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertCategory(
    DatabaseExecutor txn,
    Map<String, dynamic> m,
  ) async {
    final name = ((m['name'] as String?) ?? '').trim();
    final pcId = m['pc_id'];
    Map<String, Object?>? existing;
    final mapped = await mappedLocalId(txn, 'category', pcId);
    if (mapped != null) {
      final rows = await txn.query(
        'categories',
        where: 'id=?',
        whereArgs: [mapped],
      );
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && name.isNotEmpty) {
      final rows = await txn.query(
        'categories',
        where: 'name=? COLLATE NOCASE',
        whereArgs: [name],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && pcId != null) {
      final rows = await txn.query(
        'categories',
        where: 'id IN (?,?)',
        whereArgs: ['pc-cat-$pcId', '$pcId'],
        limit: 2,
      );
      if (rows.length > 1) throw StateError('同步匹配存在重复资料');
      if (rows.isNotEmpty) existing = rows.first;
    }

    final deleted = (m['is_deleted'] as num?)?.toInt() ?? 0;
    if (deleted != 0) {
      if (existing != null) {
        await txn.update(
          'categories',
          {
            'is_deleted': 1,
            'updated_at':
                (m['updated_at'] as String?) ??
                DateTime.now().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [existing['id']],
        );
      }
      return;
    }
    if (name.isEmpty) return;

    final id = (existing?['id'] as String?) ?? 'pc-cat-$pcId';
    await rememberEntityId(txn, 'category', pcId, id);
    await txn.insert('categories', {
      'id': id,
      'name': name,
      'is_deleted': 0,
      'updated_at':
          (m['updated_at'] as String?) ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> pullProductImage(
    LanSyncConfig cfg, {
    required int pcId,
    required String localProductId,
  }) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/product_images/$pcId');
    final res = await http
        .get(uri, headers: _headers(cfg))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) return;
    final b64 = body['base64'] as String?;
    if (b64 == null || b64.isEmpty) return;
    final store = ProductImageStore();
    final saved = await store.saveBase64(
      localProductId,
      b64,
      ext: (body['ext'] as String?) ?? 'jpg',
    );
    if (saved != null) {
      final d = await _db.db;
      await d.update(
        'products',
        {'image_path': saved},
        where: 'id=?',
        whereArgs: [localProductId],
      );
    }
  }

  Future<String> pushCategories(LanSyncConfig cfg) async {
    final cats = await repo.listCategories();
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/categories');
    final res = await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'items': [
              for (final c in cats) {'name': c.name},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) throw StateError('${body['error']}');
    return 'Pushed ${body['saved'] ?? cats.length} categories';
  }

  Future<String> pushBarcodeQueue(LanSyncConfig cfg) async {
    final rows = await repo.listBarcodeQueue(status: 'pending');
    if (rows.isEmpty) return 'No pending barcode queue';
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/barcode_queue');
    final res = await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'items': [
              for (final m in rows)
                {
                  'product_id': m['product_id'],
                  'barcode': m['barcode'],
                  'product_name': m['product_name'],
                  'sku': m['sku'],
                  'price_cents': m['price_cents'],
                  'copies': m['copies'],
                  'created_at': m['created_at'],
                  'source': 'phone',
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) throw StateError('${body['error']}');
    for (final m in rows) {
      await repo.clearBarcodeQueueItem(m['id'] as String, status: 'synced');
    }
    return 'Pushed barcode queue ${body['saved'] ?? rows.length}';
  }

  Future<String> _pushSales(
    LanSyncConfig cfg, {
    String? onlyId,
    bool legacyOnly = false,
    bool originalState = false,
  }) async {
    lastError = null;
    try {
      final d = await _db.db;
      final rows = await d.query(
        'sales',
        where: onlyId != null
            ? 'id=?'
            : "(synced_at IS NULL OR synced_at='')${legacyOnly ? " AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.kind='sale_upload' AND o.entity_id=sales.id)" : ''}",
        whereArgs: onlyId == null ? null : [onlyId],
        orderBy: 'sold_at ASC',
        limit: 200,
      );
      final sales = <Map<String, Object?>>[];
      for (final m in rows) {
        final remoteLines = <Map<String, Object?>>[];
        for (final raw in jsonDecode(m['lines_json'] as String) as List) {
          final line = Map<String, Object?>.from(raw as Map);
          remoteLines.add({
            ...line,
            'productId': await remoteEntityId(
              d,
              'product',
              line['productId'] as String,
            ),
          });
        }
        final customerId = m['customer_id'] as String?;
        sales.add({
          'client_sale_id': m['id'],
          'receipt_no': m['receipt_no'],
          'sold_at': m['sold_at'],
          'cashier': m['cashier'],
          'payment_method': m['payment_method'],
          'deposit_method': m['deposit_method'],
          'customer_id': customerId == null
              ? null
              : await remoteEntityId(d, 'customer', customerId),
          'rounding_cents': m['rounding_cents'],
          'voided': originalState ? 0 : m['voided'],
          'void_note': m['void_note'],
          'customer_name': m['customer_name'],
          'customer_phone': m['customer_phone'],
          'subtotal_cents': m['subtotal_cents'],
          'discount_cents':
              (m['item_discount_cents'] as int? ?? 0) +
              (m['order_discount_cents'] as int? ?? 0),
          'order_discount_cents': m['order_discount_cents'],
          'total_cents': m['total_cents'],
          'paid_cents': m['paid_cents'],
          'change_cents': m['change_cents'],
          'lines': remoteLines,
        });
      }
      if (sales.isEmpty) {
        await repo.setSetting(
          'lan_sync_last_push',
          DateTime.now().toIso8601String(),
        );
        return 'No unsynced sales';
      }

      final uri = Uri.parse('${cfg.normalizedBase}/api/v1/sales');
      final res = await http
          .post(uri, headers: _headers(cfg), body: jsonEncode({'sales': sales}))
          .timeout(const Duration(seconds: 45));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (body['ok'] != true) {
        throw StateError('${body['error'] ?? body}');
      }

      final mappings = (body['receipts'] as List?) ?? const [];
      final mappedById = <String, String>{};
      for (final raw in mappings) {
        if (raw is! Map) continue;
        final id = raw['client_sale_id']?.toString() ?? '';
        final receipt = raw['receipt_no']?.toString() ?? '';
        if (id.isNotEmpty && receipt.isNotEmpty) mappedById[id] = receipt;
      }

      final now = DateTime.now().toIso8601String();
      await d.transaction((txn) async {
        for (final m in rows) {
          final id = m['id'] as String;
          final canonicalReceipt = mappedById[id];
          if (canonicalReceipt == null) throw StateError('销售未获逐单确认：$id');
          if (canonicalReceipt != null &&
              canonicalReceipt != m['receipt_no']?.toString()) {
            // A WebSocket/poll may have already pulled the same server sale
            // under its canonical receipt while this push was in flight.
            // Remove that synced duplicate before renaming the local outbox row.
            await txn.delete(
              'sales',
              where:
                  "receipt_no=? AND id<>? AND synced_at IS NOT NULL AND synced_at<>''",
              whereArgs: [canonicalReceipt, id],
            );
          }
          await txn.update(
            'sales',
            <String, Object?>{
              if (canonicalReceipt != null) 'receipt_no': canonicalReceipt,
              'synced_at': now,
            },
            where: 'id=?',
            whereArgs: [id],
          );
        }
      });
      await repo.setSetting('lan_sync_last_push', now);
      await repo.setSetting('lan_sync_last_error', '');
      return 'Pushed ${body['imported'] ?? sales.length} '
          '(skipped ${body['skipped'] ?? 0})';
    } catch (e) {
      lastError = '$e';
      await repo.setSetting('lan_sync_last_error', lastError!);
      rethrow;
    }
  }

  Future<String> _pullSales(LanSyncConfig cfg) async {
    lastError = null;
    try {
      final since = await repo.getSetting('lan_sync_sales_cursor');
      final uri = Uri.parse(
        '${cfg.normalizedBase}/api/v1/sales${since.isEmpty ? '' : '?since=${Uri.encodeQueryComponent(since)}'}',
      );
      final res = await http
          .get(uri, headers: _headers(cfg))
          .timeout(const Duration(seconds: 30));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (body['ok'] != true) throw StateError('${body['error']}');
      final items = (body['items'] as List?) ?? [];
      final d = await _db.db;
      var changed = 0;

      await d.transaction((txn) async {
        for (final raw in items) {
          final m = Map<String, dynamic>.from(raw as Map);
          final receipt = (m['receipt_no'] as String?) ?? '';
          if (receipt.isEmpty) continue;
          final existing = await txn.query(
            'sales',
            where: 'receipt_no=?',
            whereArgs: [receipt],
            limit: 1,
          );
          final deleted = (m['is_deleted'] as num?)?.toInt() ?? 0;
          final isTombstone =
              m['sold_at'] == null || m['sold_at'].toString().isEmpty;
          if (isTombstone) {
            if (existing.isNotEmpty) {
              await txn.update(
                'sales',
                {
                  'voided': deleted == 0 ? 1 : deleted,
                  'void_note': m['void_note']?.toString() ?? 'remote deleted',
                  'synced_at': DateTime.now().toIso8601String(),
                },
                where: 'id=?',
                whereArgs: [existing.first['id']],
              );
              changed++;
            }
            continue;
          }

          if (existing.isNotEmpty &&
              (existing.first['synced_at'] as String? ?? '').isEmpty)
            continue;
          if (existing.isNotEmpty &&
              (await txn.query(
                'sync_outbox',
                where: "kind='sale_void' AND entity_id=?",
                whereArgs: [existing.first['id']],
              )).isNotEmpty)
            continue;
          final remoteCustomer = m['customer_id'];
          var customerId = await mappedLocalId(txn, 'customer', remoteCustomer);
          if (customerId == null && remoteCustomer != null) {
            final cs = await txn.query(
              'customers',
              where: 'id=?',
              whereArgs: ['$remoteCustomer'],
            );
            if (cs.length == 1) customerId = cs.first['id'] as String;
          }
          customerId ??= existing.isEmpty
              ? null
              : existing.first['customer_id'] as String?;
          final lines = m['lines'] ?? [];
          final total = (m['total_cents'] as num?)?.toInt() ?? 0;
          final paid = (m['paid_cents'] as num?)?.toInt() ?? total;
          final payment = m['payment_method']?.toString() ?? 'CASH';
          final totalDiscount = (m['discount_cents'] as num?)?.toInt() ?? 0;
          final orderDiscount =
              (m['order_discount_cents'] as num?)?.toInt() ?? 0;
          final row = <String, Object?>{
            'receipt_no': receipt,
            'sold_at':
                m['sold_at']?.toString() ?? DateTime.now().toIso8601String(),
            'cashier': m['cashier']?.toString() ?? 'pc-sync',
            'payment_method': payment,
            'deposit_method': m['deposit_method'],
            'customer_id': customerId,
            'customer_name': m['customer_name'],
            'customer_phone': m['customer_phone'],
            'subtotal_cents': (m['subtotal_cents'] as num?)?.toInt() ?? total,
            'item_discount_cents': max(0, totalDiscount - orderDiscount),
            'order_discount_cents': orderDiscount,
            'rounding_cents': (m['rounding_cents'] as num?)?.toInt() ?? 0,
            'total_cents': total,
            'paid_cents': paid,
            'change_cents': (m['change_cents'] as num?)?.toInt() ?? 0,
            'credit_outstanding_cents': payment.toUpperCase() == 'CREDIT'
                ? max(0, total - paid)
                : 0,
            'lines_json': jsonEncode(lines),
            'voided': deleted,
            'void_note': m['void_note']?.toString() ?? '',
            'synced_at': DateTime.now().toIso8601String(),
          };

          if (existing.isEmpty) {
            await txn.insert('sales', <String, Object?>{
              'id': AppDatabase.newId(),
              ...row,
            });
          } else {
            await txn.update(
              'sales',
              row,
              where: 'id=?',
              whereArgs: [existing.first['id']],
            );
          }
          changed++;
        }
      });

      final nextCursor = _nextCursor(since, <Map<String, dynamic>>[
        body,
      ], items);
      await repo.setSetting('lan_sync_sales_cursor', nextCursor);
      await repo.setSetting('lan_sync_last_error', '');
      return 'Pulled $changed sales';
    } catch (e) {
      lastError = '$e';
      await repo.setSetting('lan_sync_last_error', lastError!);
      rethrow;
    }
  }

  Future<void> notifyPcSale(
    LanSyncConfig cfg, {
    required String receiptNo,
  }) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/notify');
    await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'type': 'sale',
            'source': 'phone',
            'receipt_no': receiptNo,
          }),
        )
        .timeout(const Duration(seconds: 5));
  }

  /// True full reconcile: push pending local sales, reset cursors, then pull the
  /// authoritative Desktop catalog/sales snapshot.
  Future<String> forceReconcile(LanSyncConfig cfg) async {
    final r = await synchronize(cfg, full: true);
    await repo.setSetting(
      'lan_sync_last_full',
      DateTime.now().toIso8601String(),
    );
    return r;
  }

  Future<String> fullSync(LanSyncConfig cfg) => forceReconcile(cfg);
}

/// Near-real-time listener: WebSocket hints + incremental HTTP reconciliation.
/// HTTP success defines connectivity; WebSocket can reconnect independently.
class LanLiveSync {
  LanLiveSync(this.client);
  final LanSyncClient client;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _poll;
  LanSyncConfig? _cfg;
  bool connected = false;
  int pendingCount = 0;
  bool _syncing = false;
  bool _rerun = false;
  int _generation = 0;
  void Function()? onRemoteChange;
  void Function(Map<String, dynamic> event)? onLowStock;
  void Function(SyncLinkState state, int pending)? onStatusChanged;
  SyncLinkState get linkState => !connected
      ? SyncLinkState.offline
      : pendingCount > 0
      ? SyncLinkState.pending
      : SyncLinkState.connected;
  Future<void> _emitStatus() async {
    pendingCount = await client.countUnsyncedSales();
    onStatusChanged?.call(linkState, pendingCount);
  }

  Future<void> connect(LanSyncConfig cfg) async {
    await disconnect();
    await client.saveConfig(cfg);
    _cfg = cfg;
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollOnce()),
    );
    await _pollOnce();
    if (!connected) throw StateError(client.lastError ?? '电脑暂未连接，后台将自动重试');
  }

  Future<void> _openWebSocket() async {
    final c = _cfg;
    if (c == null || _ws != null) return;
    final generation = _generation;
    try {
      final ws = WebSocketChannel.connect(c.wsUri);
      _ws = ws;
      _wsSub = ws.stream.listen(
        (msg) {
          if (generation != _generation) return;
          try {
            final data = msg is String ? jsonDecode(msg) : null;
            if (data is! Map) return;
            final type = data['type'];
            if (type == 'low_stock')
              onLowStock?.call(Map<String, dynamic>.from(data));
            else if (type != 'ready' && type != 'pong')
              unawaited(type == 'reconcile' ? forceReconcile() : _pollOnce());
          } catch (_) {}
        },
        onError: (_) {
          if (identical(_ws, ws)) _ws = null;
        },
        onDone: () {
          if (identical(_ws, ws)) _ws = null;
        },
        cancelOnError: true,
      );
    } catch (_) {
      _ws = null;
    }
  }

  Future<void> _pollOnce() async {
    final c = _cfg;
    if (c == null) return;
    if (_syncing) {
      _rerun = true;
      return;
    }
    _syncing = true;
    final generation = _generation;
    try {
      await client.synchronize(c);
      if (generation != _generation) return;
      connected = true;
      await _openWebSocket();
      onRemoteChange?.call();
    } catch (e) {
      if (generation != _generation) return;
      connected = false;
      client.lastError = '$e';
      await client.repo.setSetting('lan_sync_last_error', '$e');
    } finally {
      _syncing = false;
      if (generation == _generation) await _emitStatus();
      if (_rerun && _cfg != null) {
        _rerun = false;
        scheduleMicrotask(() => unawaited(_pollOnce()));
      }
    }
  }

  Future<void> onLocalSale(SaleRecord sale) async {
    if (_cfg == null) {
      final c = await client.loadConfig();
      if (c != null) {
        try {
          await connect(c);
        } catch (_) {}
      }
    } else {
      await _pollOnce();
    }
    await _emitStatus();
  }

  Future<String> forceReconcile() async {
    final c = _cfg ?? await client.loadConfig();
    if (c == null) throw StateError('not paired');
    final r = await client.forceReconcile(c);
    connected = true;
    await _emitStatus();
    onRemoteChange?.call();
    return r;
  }

  Future<void> disconnect() async {
    _generation++;
    _rerun = false;
    _poll?.cancel();
    _poll = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    _cfg = null;
    connected = false;
    await _emitStatus();
  }
}
