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
  Future<void> waitForState(WidgetTester tester, bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (ready()) return;
    }
    fail('Image operation did not reach its observable UI state');
  }

  Future<void> waitForFiles(
    WidgetTester tester,
    Directory directory,
    int expected,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final count = await tester.runAsync(() => directory.list().length);
      if (count == expected) return;
    }
    fail('Image operation did not finish with $expected owned files');
  }

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
        await tester.pumpWidget(const SizedBox.shrink());
        final decodingDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (tester.binding.imageCache.pendingImageCount > 0 &&
            DateTime.now().isBefore(decodingDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(tester.binding.imageCache.pendingImageCount, 0);
        tester.binding.imageCache.clear();
        tester.binding.imageCache.clearLiveImages();
        ImagePickerPlatform.instance = picker;
        PathProviderPlatform.instance = paths;
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (await directory.exists()) {
            try {
              await directory.delete(recursive: true);
            } on FileSystemException catch (error) {
              if (error.osError?.errorCode != 32 ||
                  DateTime.now().isAfter(deadline))
                rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          }
        });
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
      await waitForFiles(tester, imageDirectory, 2);
      await waitForState(
        tester,
        () => find
            .byWidgetPredicate((widget) {
              if (widget is! Image || widget.image is! FileImage) return false;
              return (widget.image as FileImage).file.path != original.path;
            })
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(action == 'cancel' ? '取消' : '保存'));
      if (action == 'save') {
        await waitForState(
          tester,
          () => repo.commits == 1 && repo.product.imagePath != original.path,
        );
      }
      await waitForFiles(tester, imageDirectory, action == 'save' ? 2 : 1);
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
