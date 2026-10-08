import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'settings token changes refresh both live requests and the WebSocket',
    () async {
      final temp = await Directory.systemTemp.createTemp('cnkh-live-config-');
      final database = AppDatabase.forTesting(
        '${temp.path}/phone.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestTokens = <String>[];
      final socketTokens = <String>[];
      final sockets = <WebSocket>[];
      final expectedSockets = {
        'old': Completer<void>(),
        'rotated': Completer<void>(),
        'latest': Completer<void>(),
      };
      final serving = server.forEach((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final token = request.uri.queryParameters['token']!;
          socketTokens.add(token);
          sockets.add(await WebSocketTransformer.upgrade(request));
          expectedSockets[token]!.complete();
          return;
        }
        requestTokens.add(request.headers.value('X-CNKH-Token') ?? '');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path == '/api/v1/health'
                ? {
                    'ok': true,
                    'protocol': 1,
                    'cursor': 1,
                    'capabilities': ['mutations_v1'],
                  }
                : {'ok': true, 'cursor': 1, 'items': []},
          ),
        );
        await request.response.close();
      });
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final transport = IOClient(HttpClient());
      final live = LanLiveSync(LanSyncClient(repo, httpClient: transport));
      final base = 'http://127.0.0.1:${server.port}';
      try {
        // onLocalSale needs the completed local sale; uploads are tested elsewhere.
        const product = Product(
          id: 'p1',
          sku: 'P1',
          barcode: 'P1',
          nameZh: '商品',
          nameEn: 'Product',
          priceCents: 100,
          stock: 2,
        );
        await repo.upsertProduct(product);
        final sale = await repo.createSale(
          cart: CartState(items: [CartItem(product: product)]),
          paymentMethod: 'CASH',
          paidCents: 100,
          cashier: 'test',
        );
        final db = await database.db;
        await db.update(
          'sales',
          {'synced_at': '2026-10-01'},
          where: 'id=?',
          whereArgs: [sale.id],
        );
        await db.delete('sync_outbox');
        await live.connect(LanSyncConfig(baseUrl: base, token: 'old'));
        await expectedSockets['old']!.future.timeout(
          const Duration(seconds: 3),
        );
        expect(requestTokens, everyElement('old'));

        requestTokens.clear();
        // The settings screen instantiates a separate client for saving.
        await LanSyncClient(repo)
            .saveConfig(LanSyncConfig(baseUrl: base, token: 'rotated'));
        await live.forceReconcile();
        await expectedSockets['rotated']!.future.timeout(
          const Duration(seconds: 3),
        );
        expect(requestTokens, isNotEmpty);
        expect(requestTokens, everyElement('rotated'));

        requestTokens.clear();
        await LanSyncClient(repo)
            .saveConfig(LanSyncConfig(baseUrl: base, token: 'latest'));
        await live.onLocalSale(sale);
        await expectedSockets['latest']!.future.timeout(
          const Duration(seconds: 3),
        );
        expect(requestTokens, isNotEmpty);
        expect(requestTokens, everyElement('latest'));
        expect(socketTokens, ['old', 'rotated', 'latest']);
        expect(live.connected, isTrue);
      } finally {
        await live.disconnect();
        transport.close();
        for (final socket in sockets) {
          await socket.close();
        }
        HttpOverrides.global = previousOverrides;
        await server.close(force: true);
        await serving;
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
