import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/screens/cart_screen.dart';
import 'package:cnkh_pos_mobile/screens/admin/products_admin.dart';
import 'package:cnkh_pos_mobile/screens/admin/entities_page.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/theme/cnkh_theme.dart';
import 'package:cnkh_pos_mobile/widgets/paged_list_footer.dart';

class FailableRepository extends PosRepository {
  FailableRepository(AppDatabase db) : super(database: db);
  bool fail = false;
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) {
    if (fail) return Future.error(StateError('Test read failure'));
    return super.searchProducts(
      query,
      limit: limit,
      offset: offset,
      category: category,
    );
  }

  @override
  Future<List<Customer>> listCustomers({
    int? limit,
    int offset = 0,
    String query = '',
  }) {
    if (fail) return Future.error(StateError('Test read failure'));
    return super.listCustomers(limit: limit, offset: offset, query: query);
  }

  @override
  Future<List<Supplier>> listSuppliers({
    int? limit,
    int offset = 0,
    String query = '',
  }) {
    if (fail) return Future.error(StateError('Test read failure'));
    return super.listSuppliers(limit: limit, offset: offset, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late FailableRepository repo;
  const user = AppUser(
    username: 'admin',
    role: AppRole.admin,
    displayName: 'Admin',
  );
  Product product(int i) => Product(
    id: 'layout-$i',
    nameZh: '商品${i.toString().padLeft(3, '0')}',
    nameEn: 'Layout $i',
    sku: 'LAYOUT-$i',
    barcode: 'LAYOUT-$i',
    priceCents: 1000,
    stock: 100,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cnkh-layout-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = FailableRepository(database);
    await database.db;
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(430, 932),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCnkhTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await settle(tester);
  }

  for (final kind in ['products', 'customers', 'suppliers']) {
    testWidgets(
      '$kind records occupy the body, footer stays at bottom and page two works',
      (tester) async {
        await tester.runAsync(() async {
          for (var i = 0; i < 52; i++) {
            if (kind == 'products') {
              await repo.upsertProduct(product(i));
            } else if (kind == 'customers') {
              await repo.upsertCustomer(
                Customer(id: 'c$i', name: '客户${i.toString().padLeft(3, '0')}'),
              );
            } else {
              await repo.upsertSupplier(
                Supplier(id: 's$i', name: '供应商${i.toString().padLeft(3, '0')}'),
              );
            }
          }
        });
        final screen = kind == 'products'
            ? ProductsAdminPage(repo: repo, user: user)
            : EntitiesPage(repo: repo, kind: kind);
        await show(tester, screen);
        final tiles = find.byType(ListTile).hitTestable();
        expect(tiles, findsWidgets);
        final footer = tester.getRect(find.byType(PagedListFooter));
        expect(footer.height, lessThan(120));
        expect(footer.bottom, closeTo(932, 1));
        expect(tester.getRect(tiles.first).bottom, lessThan(footer.top));
        await tester.tap(find.text('下一页'));
        await settle(tester);
        expect(find.text('第 2 页'), findsOneWidget);
        expect(find.byType(ListTile).hitTestable(), findsNWidgets(2));
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '下一页'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('上一页'));
        await settle(tester);
        expect(find.text('第 1 页'), findsOneWidget);
        if (kind == 'products') {
          await tester.enterText(find.byType(TextField).first, 'LAYOUT-51');
          await settle(tester);
          expect(find.text('商品051'), findsOneWidget);
          await tester.enterText(find.byType(TextField).first, 'not-found');
          await settle(tester);
          expect(find.textContaining('No matching products'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final kind in ['products', 'customers', 'suppliers', 'pos']) {
    testWidgets('$kind read failure is visible and retry recovers records', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await repo.upsertProduct(product(0));
        await repo.upsertCustomer(const Customer(id: 'retry-c', name: '测试客户'));
        await repo.upsertSupplier(const Supplier(id: 'retry-s', name: '测试供应商'));
      });
      repo.fail = true;
      final Widget screen = kind == 'products'
          ? ProductsAdminPage(repo: repo, user: user)
          : kind == 'pos'
          ? Scaffold(
              body: CartScreen(
                cart: CartState(),
                user: user,
                repo: repo,
                onChanged: () {},
                onCheckout: () {},
                onHold: () async {},
                onResume: () async {},
              ),
            )
          : EntitiesPage(repo: repo, kind: kind);
      await show(tester, screen);
      expect(find.text('重试 / Retry').hitTestable(), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('重试 / Retry'));
      await settle(tester);
      expect(find.text('重试 / Retry'), findsNothing);
      expect(
        find
            .text(
              kind == 'customers'
                  ? '测试客户'
                  : kind == 'suppliers'
                  ? '测试供应商'
                  : '商品000',
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'small screen large type keeps populated body and compact footer',
    (tester) async {
      await tester.runAsync(
        () => repo.upsertCustomer(const Customer(id: 'c', name: '测试客户')),
      );
      await show(
        tester,
        EntitiesPage(repo: repo, kind: 'customers'),
        size: const Size(320, 640),
        scale: 1.8,
      );
      expect(find.text('测试客户').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byType(PagedListFooter)).height,
        lessThan(160),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'POS uses one vertical scroll, collapses products and keeps checkout reachable',
    (tester) async {
      await tester.runAsync(() => repo.upsertProduct(product(0)));
      final cart = CartState(
        items: List.generate(15, (i) => CartItem(product: product(i))),
      );
      var checkouts = 0;
      await show(
        tester,
        Scaffold(
          body: CartScreen(
            cart: cart,
            user: user,
            repo: repo,
            onChanged: () {},
            onCheckout: () {
              checkouts++;
            },
            onHold: () async {},
            onResume: () async {},
          ),
        ),
      );
      final scroll = find.byKey(const PageStorageKey('pos-scroll'));
      final shelf = find.byKey(const PageStorageKey('pos-products'));
      final before = tester.getSize(shelf).height;
      final checkout = find.widgetWithText(FilledButton, '结账\nCheckout');
      final fixed = tester.getRect(checkout);
      await tester.drag(scroll, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(tester.getSize(shelf).height, lessThan(before));
      expect(tester.getRect(checkout), fixed);
      expect(find.byIcon(Icons.delete_outline).hitTestable(), findsWidgets);
      await tester.tap(checkout);
      expect(checkouts, 1);
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      state.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(shelf).height, closeTo(before, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty POS scrolls on a small screen with large text and keyboard',
    (tester) async {
      await tester.runAsync(() => repo.upsertProduct(product(0)));
      await show(
        tester,
        Scaffold(
          body: CartScreen(
            cart: CartState(),
            user: user,
            repo: repo,
            onChanged: () {},
            onCheckout: () {},
            onHold: () async {},
            onResume: () async {},
          ),
        ),
        size: const Size(320, 640),
        scale: 1.8,
      );
      await tester.drag(
        find.byKey(const PageStorageKey('pos-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('结账\nCheckout').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
