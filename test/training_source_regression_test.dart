import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/screens/training_page.dart';

void main() {
  test('Desktop training screenshots use the same pinned companion as integration', () {
    final workflow = File('.github/workflows/mobile-ci.yml').readAsStringSync();
    final checkout = RegExp(
      r'- name: Checkout Desktop training source[\s\S]*?(?=\n      - name:)',
    ).firstMatch(workflow)!.group(0)!;
    expect(checkout, contains('ref: \${{ steps.training_source.outputs.ref }}'));
    expect(workflow, contains('< .github/paired-desktop-ref'));
    expect(File('.github/paired-desktop-ref').readAsStringSync().trim(),
        matches(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$')));
  });

  test('MyInvois training covers certificates and durable Invalid reconciliation', () {
    final setup = TrainingPage.lessons.singleWhere((lesson) => lesson.$2 == 'einvoice_setup').$3;
    final errors = TrainingPage.lessons.singleWhere((lesson) => lesson.$1 == '常见错误处理').$3;
    expect(setup, contains('PFX/P12'));
    expect(errors, contains('Invalid'));
    expect(errors, contains('Submission UID'));
    expect(errors, contains('更正尝试'));
  });
}
