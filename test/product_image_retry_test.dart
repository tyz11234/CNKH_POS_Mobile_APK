import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/product_image_sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final initiallyEnabled in [true, false]) {
    test('image retries survive a new client after cursor advances; enabled=$initiallyEnabled', () async {
      final dir = await Directory.systemTemp.createTemp('cnkh-image-retry-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      final database = AppDatabase.forTesting('${dir.path}/db.sqlite', seed: false);
      final repo = PosRepository(database: database);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var imageRequests = 0, fullCatalogs = 0;
      var failImage = true;
      var now = DateTime(2026, 9, 20);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path;
        var body = <String, Object?>{'ok': true, 'cursor': 10, 'items': []};
        if (path == '/api/v1/health') {
          body.addAll({'protocol': 1, 'capabilities': ['mutations_v1'], 'stock_policy': 'warn'});
        } else if (path == '/api/v1/products') {
          final since = int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
          if (since == 0) fullCatalogs++;
          if (since < 10) body['items'] = [{
            'pc_id': 'p1', 'name_zh': '图片商品', 'name_en': 'Image product',
            'sku': 'IMG', 'barcode': 'IMG', 'price_cents': 100, 'stock': 5,
            'has_image': true, 'is_deleted': 0,
          }];
        } else if (path == '/api/v1/product_images/p1') {
          imageRequests++;
          if (failImage) { request.response.statusCode = 503; body = {'ok': false}; }
          else { body = {'ok': true, 'base64': base64Encode([1, 2, 3]), 'ext': 'png'}; }
        }
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      try {
        final cfg = LanSyncConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 'test');
        await repo.setSetting('product_images_enabled', initiallyEnabled ? '1' : '0');
        await LanSyncClient(repo, imageClock: () => now).synchronize(cfg);
        expect(await repo.getSetting('lan_sync_products_cursor'), '10');
        expect(imageRequests, initiallyEnabled ? 1 : 0);
        expect(await repo.getSetting('lan_sync_last_error'), '');
        final before = await repo.getProduct('pc-p1');
        expect(before!.imagePath, isEmpty);
        await repo.setSetting('product_images_enabled', '1');
        failImage = false;
        now = now.add(const Duration(seconds: 31));
        await LanSyncClient(repo, imageClock: () => now).synchronize(cfg);
        final saved = await repo.getProduct('pc-p1');
        expect(await File(saved!.imagePath).readAsBytes(), [1, 2, 3]);
        expect(fullCatalogs, initiallyEnabled ? 1 : 2);
        expect(saved.stock, 5);
        expect(await repo.getSetting('product_image_sync_error'), '');
        final count = imageRequests;
        await LanSyncClient(repo, imageClock: () => now).synchronize(cfg);
        expect(imageRequests, count);
      } finally {
        await server.close(force: true);
        await database.close();
        await dir.delete(recursive: true);
      }
    });
  }
  test('queue isolates hosts, rotates failures and cancels obsolete downloads', () async {
    final dir = await Directory.systemTemp.createTemp('cnkh-image-queue-');
    final database = AppDatabase.forTesting('${dir.path}/db.sqlite', seed: false);
    try {
      final db = await database.db;
      final queue = ProductImageSyncQueue(db, 'host-a');
      await queue.enqueue([
        {'remoteId': 'fail', 'localId': 'l1', 'hasImage': true},
        {'remoteId': 'ok', 'localId': 'l2', 'hasImage': true},
      ]);
      final seen = <String>[];
      expect(await queue.drain((job) async { seen.add(job['remoteId'] as String); throw StateError('offline'); }, limit: 1), 2);
      expect(await ProductImageSyncQueue(db, 'host-b').drain((_) async => fail('wrong host')), 0);
      expect(await ProductImageSyncQueue(db, 'host-a').drain((job) async { seen.add(job['remoteId'] as String); }), 1);
      expect(seen, ['fail', 'ok']);
      await queue.enqueue([{'remoteId': 'fail', 'localId': 'l1', 'hasImage': false, 'localHasImage': false}]);
      expect(await queue.drain((_) async => fail('obsolete job')), 0);
    } finally { await database.close(); await dir.delete(recursive: true); }
  });
}
