import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/services/purchase_history_sync.dart';

void main() {
  test('explicit reconciliation surfaces purchase errors instead of completing', () async {
    var error = '';
    final coordinator = PurchaseHistoryCoordinator(
      pull: ({required bool full}) async => throw StateError('purchase HTTP 500'),
      saveError: (value) async { error = value; }, onChanged: () {},
    );
    await expectLater(coordinator.synchronize(force: true), throwsStateError);
    expect(error, contains('purchase HTTP 500'));
  });

  test('background errors remain recorded without escaping into live sync', () async {
    var error = '';
    final coordinator = PurchaseHistoryCoordinator(
      pull: ({required bool full}) async => throw StateError('offline'),
      saveError: (value) async { error = value; }, onChanged: () {},
    );
    await coordinator.synchronize();
    expect(error, contains('offline'));
  });

  test('forced pull waits for background work and runs a fresh full request', () async {
    final started = Completer<void>();
    final pending = Completer<PurchaseHistoryPullResult>();
    final flags = <bool>[];
    var changed = 0;
    final coordinator = PurchaseHistoryCoordinator(
      pull: ({required bool full}) async {
        flags.add(full);
        if (flags.length == 1) { started.complete(); return pending.future; }
        return const PurchaseHistoryPullResult(supported: true, changed: 1);
      }, saveError: (_) async {}, onChanged: () { changed++; },
    );
    final background = coordinator.synchronize();
    await started.future;
    var completed = false;
    final foreground = coordinator.synchronize(force: true).then((_) { completed = true; });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(flags, [false]);
    pending.complete(const PurchaseHistoryPullResult(supported: true, changed: 0));
    await background;
    await foreground;
    expect(flags, [false, true]);
    expect(changed, 1);
  });

  test('unsupported history cannot report successful full reconciliation', () async {
    final coordinator = PurchaseHistoryCoordinator(
      pull: ({required bool full}) async =>
          const PurchaseHistoryPullResult(supported: false, changed: 0),
      saveError: (_) async {}, onChanged: () {},
    );
    await expectLater(coordinator.synchronize(force: true), throwsStateError);
  });
}
