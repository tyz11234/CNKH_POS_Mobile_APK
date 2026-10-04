import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/screens/cart_screen.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

class _Repository extends PosRepository {
  int auditWrites = 0;
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [];
  @override
  Future<List<Category>> listCategories({bool includeDeleted = false}) async =>
      [];
  @override
  Future<bool> productImagesEnabled() async => false;
  @override
  Future<void> logAudit({
    required String username,
    required String role,
    required String action,
    String module = 'pos',
    String? productId,
    String? productName,
    String context = '',
    String oldValue = '',
    String newValue = '',
    String reason = '',
  }) async {
    auditWrites++;
  }
}

void main() {
  for (final mode in ['order', 'line RM', 'line percent']) {
    for (final amount in ['NaN', 'Infinity', '1e100']) {
      testWidgets(
        '$mode discount handles pasted $amount without corrupting cart',
        (tester) async {
          tester.view.physicalSize = const Size(430, 932);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = _Repository();
          final cart = CartState(
            items: [
              CartItem(
                product: const Product(
                  id: 'cart',
                  nameZh: 'Cart product',
                  nameEn: 'Cart product',
                  sku: 'CART',
                  barcode: 'CART',
                  priceCents: 100,
                  stock: 5,
                ),
              ),
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CartScreen(
                  cart: cart,
                  repo: repo,
                  user: const AppUser(username: 'admin', role: AppRole.admin),
                  onChanged: () {},
                  onCheckout: () {},
                  onHold: () async {},
                  onResume: () async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (mode == 'order') {
            await tester.tap(find.text('整单折扣'));
          } else {
            await tester.ensureVisible(find.text('行折扣 / Discount'));
            await tester.tap(find.text('行折扣 / Discount'));
            await tester.pumpAndSettle();
            await tester.tap(find.text(mode == 'line RM' ? '金额 RM' : '百分比 %'));
          }
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            amount,
          );
          await tester.tap(find.text('确定'));
          await tester.pumpAndSettle();
          final isCappedPercent = mode == 'line percent' && amount == '1e100';
          expect(cart.items.single.discountCents, isCappedPercent ? 100 : 0);
          expect(cart.orderDiscountCents, 0);
          expect(cart.rawPayableCents, isCappedPercent ? 0 : 100);
          expect(repo.auditWrites, isCappedPercent ? 1 : 0);
          expect(tester.takeException(), isNull);
          if (!isCappedPercent)
            expect(find.textContaining('请输入有效折扣'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
