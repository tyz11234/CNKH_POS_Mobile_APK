import 'dart:io';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  late LanSyncClient client;

  setUp(() async {
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('cnkh-pairing-config-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    client = LanSyncClient(repo, database: database);
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test('same Desktop host accepts a rotated pairing token', () async {
    await client.saveConfig(
      const LanSyncConfig(
        baseUrl: 'http://192.168.1.20:8787/',
        token: 'old-token-012345678901234567890123',
        name: 'CNKH-PC',
      ),
    );

    await client.saveConfig(
      const LanSyncConfig(
        baseUrl: '192.168.1.20:8787',
        token: 'new-token-012345678901234567890123',
        name: 'CNKH-PC',
      ),
    );

    final saved = await client.loadConfig();
    expect(saved, isNotNull);
    expect(saved!.normalizedBase, 'http://192.168.1.20:8787');
    expect(saved.token, 'new-token-012345678901234567890123');
  });

  test('different Desktop host is still blocked when credentials already exist', () async {
    await client.saveConfig(
      const LanSyncConfig(
        baseUrl: 'http://192.168.1.20:8787',
        token: 'old-token-012345678901234567890123',
        name: 'Store A',
      ),
    );

    await expectLater(
      client.saveConfig(
        const LanSyncConfig(
          baseUrl: 'http://192.168.1.99:8787',
          token: 'other-token-012345678901234567890',
          name: 'Store B',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('先同步并备份'),
        ),
      ),
    );

    final saved = await client.loadConfig();
    expect(saved!.normalizedBase, 'http://192.168.1.20:8787');
    expect(saved.token, 'old-token-012345678901234567890123');
  });
}
