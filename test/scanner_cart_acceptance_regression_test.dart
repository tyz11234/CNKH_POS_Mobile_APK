import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/screens/barcode_scan_screen.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

class _Repository extends PosRepository {
  int feedbackReads = 0;
  static const product = Product(
    id: 'scan',
    nameZh: 'Scan product',
    nameEn: 'Scan product',
    sku: 'SCAN',
    barcode: 'SCAN',
    priceCents: 100,
    stock: 0,
  );
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [product];
  @override
  Future<String> getSetting(String key, {String fallback = ''}) async {
    if (key == 'scan_feedback') feedbackReads++;
    return key == 'scan_feedback' ? 'mute' : fallback;
  }
}

void main() {
  for (final accepted in [false, true]) {
    testWidgets(
      'scanner waits for async cart acceptance=$accepted before feedback',
      (tester) async {
        final repo = _Repository();
        final gate = Completer<bool>();
        Future<bool> addProduct(Product product) => gate.future;
        await tester.pumpWidget(
          MaterialApp(
            home: BarcodeScanScreen(repo: repo, onProduct: addProduct),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scan product'));
        await tester.pumpAndSettle();
        expect(
          repo.feedbackReads,
          0,
          reason: 'an unresolved stock decision is not an accepted item',
        );
        gate.complete(accepted);
        await tester.pumpAndSettle();
        expect(repo.feedbackReads, accepted ? 1 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
