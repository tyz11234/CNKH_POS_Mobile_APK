import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/screens/admin/products_admin.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

class _Repository extends PosRepository {
  Product product = const Product(
    id: 'product',
    nameZh: 'Product',
    nameEn: 'Product',
    sku: 'PRODUCT',
    barcode: 'PRODUCT',
    priceCents: 100,
    stock: 5,
  );
  int commits = 0;

  @override
  Future<bool> productImagesEnabled() async => false;

  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [product];

  @override
  Future<void> upsertProduct(Product next, {Product? original}) async {
    commits++;
    product = next;
  }
}

void main() {
  for (final label in ['中文名', '售价 RM']) {
    for (final save in [false, true]) {
      testWidgets(
        'focused product $label closes safely on ${save ? 'save' : 'cancel'}',
        (tester) async {
          final repo = _Repository();
          await tester.pumpWidget(
            MaterialApp(
              home: ProductsAdminPage(
                repo: repo,
                user: const AppUser(username: 'admin', role: AppRole.admin),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Product'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('编辑 / Edit'));
          await tester.pumpAndSettle();
          final field = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          );
          await tester.ensureVisible(field);
          await tester.enterText(
            field,
            label == '中文名' ? 'Edited product' : '2.50',
          );
          await tester.tap(find.text(save ? '保存' : '取消'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(repo.commits, save ? 1 : 0);
          expect(
            repo.product.nameZh,
            save && label == '中文名' ? 'Edited product' : 'Product',
          );
          expect(repo.product.priceCents, save && label == '售价 RM' ? 250 : 100);
          expect(find.text('编辑商品'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
