import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/screens/sales_list_screen.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

class _Repository extends PosRepository {
  final sale = SaleRecord(
    id: 'protected',
    receiptNo: 'PROTECTED',
    soldAt: DateTime.now().toIso8601String(),
    cashier: 'admin',
    paymentMethod: 'CARD',
    subtotalCents: 100,
    itemDiscountCents: 0,
    orderDiscountCents: 0,
    roundingCents: 0,
    totalCents: 100,
    paidCents: 100,
    changeCents: 0,
    creditOutstandingCents: 0,
    linesJson: '[]',
  );
  @override
  Future<List<SaleRecord>> salesPage({
    bool todayOnly = false,
    String query = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async => [sale];
  @override
  Future<void> voidSale(String id, String note) async =>
      throw StateError('库存活动已改变，不能安全作废');
}

void main() {
  testWidgets('a refused void is visible and leaves the sale intact', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesListScreen(repo: repo, todayOnly: false, canVoid: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('作废'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作废').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('库存活动已改变，不能安全作废'), findsOneWidget);
    expect(find.text('PROTECTED · CARD'), findsOneWidget);
  });
}
