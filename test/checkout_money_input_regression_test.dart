import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/screens/checkout_screen.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/qr_storage.dart';

const _product = Product(
  id: 'money',
  nameZh: 'Money',
  nameEn: 'Money',
  sku: 'MONEY',
  barcode: 'MONEY',
  priceCents: 1000,
  stock: 5,
);

class _Repository extends PosRepository {
  int commits = 0;
  @override
  Future<List<Customer>> listCustomers({
    int? limit,
    int offset = 0,
    String query = '',
  }) async => [];
  @override
  Future<String> stockPolicy() async => 'block';
  @override
  Future<Product?> getProduct(String id) async => _product;
  @override
  Future<SaleRecord> createSale({
    required CartState cart,
    required String paymentMethod,
    required int paidCents,
    required String cashier,
    String? depositMethod,
    Customer? customer,
    String? customerPhone,
  }) async {
    commits++;
    throw StateError('invalid input must not reach persistence');
  }
}

class _QrStorage extends QrStorage {
  @override
  Future<String?> getLocalPath() async => null;
}

void main() {
  for (final value in ['NaN', 'Infinity', '1e309', '1e308']) {
    testWidgets('cash input $value does not crash or commit', (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutScreen(
            cart: CartState(items: [CartItem(product: _product)]),
            user: const AppUser(username: 'admin', role: AppRole.admin),
            qrStorage: _QrStorage(),
            repo: repo,
            onCancel: () {},
            onPaid: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cash = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == '收取现金 / Cash tendered',
      );
      await tester.enterText(cash, value);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('确认收款 / Confirm'));
      await tester.pumpAndSettle();
      expect(repo.commits, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
