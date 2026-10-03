import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/screens/admin/products_admin.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

class _Picker extends ImagePickerPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Repository extends PosRepository {
  _Repository(this.product);
  Product product;
  int commits = 0;
  bool rejectSave = false;
  @override
  Future<bool> productImagesEnabled() async => true;
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 40,
    int offset = 0,
    String? category,
  }) async => [product];
  @override
  Future<void> upsertProduct(Product next, {Product? original}) async {
    commits++;
    if (rejectSave) throw StateError('stale product conflict');
    product = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in ['cancel', 'rejected save', 'save']) {
    testWidgets('$action product image edit preserves original file', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('image-edit-'),
      ))!;
      final imageDirectory = (await tester.runAsync(
        () => Directory('${directory.path}/product_images').create(),
      ))!;
      final original = File('${imageDirectory.path}/product.png');
      final oldBytes = img.encodePng(img.Image(width: 2, height: 2));
      final replacement = File('${directory.path}/replacement.png');
      final nextBytes = img.encodePng(img.Image(width: 3, height: 3));
      await tester.runAsync(() async {
        await original.writeAsBytes(oldBytes);
        await replacement.writeAsBytes(nextBytes);
      });
      final picker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _Picker(replacement.path);
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      addTearDown(() async {
        ImagePickerPlatform.instance = picker;
        PathProviderPlatform.instance = paths;
        await directory.delete(recursive: true);
      });
      final repo = _Repository(
        Product(
          id: 'product',
          nameZh: 'Product',
          nameEn: 'Product',
          sku: 'PRODUCT',
          barcode: 'PRODUCT',
          priceCents: 100,
          imagePath: original.path,
        ),
      );
      repo.rejectSave = action == 'rejected save';
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
      final pick = find.text('选择商品图片 / Pick image');
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text(action == 'cancel' ? '取消' : '保存'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(await tester.runAsync(original.readAsBytes), oldBytes);
      expect(repo.commits, action == 'cancel' ? 0 : 1);
      if (action == 'save') {
        expect(repo.product.imagePath, isNot(original.path));
        expect(
          await tester.runAsync(
            () => File(repo.product.imagePath).readAsBytes(),
          ),
          nextBytes,
        );
      } else {
        expect(repo.product.imagePath, original.path);
        expect(await tester.runAsync(() => imageDirectory.list().length), 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
