import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cnkh-widget-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: true);
    repo = PosRepository(database: database);
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin', '839201');
    await repo.auth.setUserPin('staff', '728394');
    repo.auth.logout();
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });
  Future<void> signIn(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('登录 / Sign in'));
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (repo.auth.currentUser == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(repo.auth.currentUser, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  }


  testWidgets('app boots to login with role picker', (tester) async {
    await tester.pumpWidget(CnkhPosMobileApp(repository: repo));
    expect(find.textContaining('黄金发宝号'), findsOneWidget);
    expect(find.textContaining('员工 Staff'), findsOneWidget);
    expect(find.textContaining('管理员 Admin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  });

  testWidgets('staff login reaches POS shell', (tester) async {
    await tester.pumpWidget(CnkhPosMobileApp(repository: repo));
    await tester.enterText(find.byType(TextField).at(1), '728394');
    await signIn(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // DB seed may take a moment
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.textContaining('收银台'), findsOneWidget);
    expect(find.textContaining('Staff'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  });

  testWidgets('admin settings shows import; staff view-only', (tester) async {
    await tester.pumpWidget(CnkhPosMobileApp(repository: repo));
    await tester.tap(find.text('管理员 Admin'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '839201');
    await signIn(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.textContaining('Admin'), findsWidgets);

    await tester.tap(find.textContaining('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('从相册导入'), findsOneWidget);

    await tester.tap(find.byTooltip('退出 / Logout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('员工 Staff'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '728394');
    await signIn(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.tap(find.textContaining('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('仅管理员可更改收款码'), findsOneWidget);
    expect(find.textContaining('从相册导入'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  });
}
