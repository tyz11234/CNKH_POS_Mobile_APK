import 'dart:typed_data';

import 'package:cnkh_pos_mobile/services/barcode_labels.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void expectRealBars(Uint8List bytes, {int sampleY = 80}) {
    final decoded = img.decodePng(bytes);
    expect(decoded, isNotNull);
    final image = decoded!;
    expect(sampleY, lessThan(image.height));

    final dark = <bool>[];
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, sampleY);
      dark.add(pixel.r < 128 && pixel.g < 128 && pixel.b < 128);
    }
    final darkColumns = dark.where((v) => v).length;
    final whiteColumns = dark.length - darkColumns;
    var transitions = 0;
    for (var i = 1; i < dark.length; i++) {
      if (dark[i] != dark[i - 1]) transitions++;
    }

    expect(darkColumns, greaterThan(40));
    expect(whiteColumns, greaterThan(40));
    expect(transitions, greaterThan(20));
  }

  test('EAN-13 PNG contains real barcode bars and CJK name layout', () async {
    final svc = BarcodeLabelService(PosRepository());
    final bytes = await svc.renderPng(
      barcode: '1234567890128',
      productName: '水管接头 Pipe fitting',
    );
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50);
    expect(bytes[2], 0x4E);
    expect(bytes[3], 0x47);
    expectRealBars(bytes);
  });

  test('Code128 PNG contains real barcode bars', () async {
    final svc = BarcodeLabelService(PosRepository());
    final bytes = await svc.renderPng(
      barcode: 'CNKH-ABC-001',
      productName: 'English Product Name',
    );
    expectRealBars(bytes);
  });

  test('renderPng rejects empty barcode', () async {
    final svc = BarcodeLabelService(PosRepository());
    expect(
      () => svc.renderPng(barcode: '  ', productName: 'x'),
      throwsA(isA<StateError>()),
    );
  });
}
