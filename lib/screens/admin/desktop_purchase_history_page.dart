import 'dart:convert';

import 'package:flutter/material.dart';

import '../../widgets/money_text.dart';

/// Read-only detail for a Purchase whose inventory mutation happened on Desktop.
/// Mobile mirrors this row for history/audit only, so no Reverse/Edit action is
/// exposed here and stock can never be changed a second time from this screen.
class DesktopPurchaseHistoryPage extends StatelessWidget {
  const DesktopPurchaseHistoryPage({
    super.key,
    required this.purchase,
  });

  final Map<String, Object?> purchase;

  List<Map<String, dynamic>> get _lines {
    try {
      final raw = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _money(Object? value) {
    final cents = (value as num?)?.toInt() ?? 0;
    return 'RM ${(cents / 100).toStringAsFixed(2)}';
  }

  Widget _field(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 125,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: SelectableText(value?.toString() ?? '')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final reversed = (purchase['reversed'] as num?)?.toInt() == 1;
    return Scaffold(
      appBar: AppBar(title: Text(purchase['purchase_no']?.toString() ?? 'Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Desktop 进货历史 / Read-only',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '这笔进货的库存变更由 Desktop 负责。Mobile 这里只同步历史记录；如需撤销或修改库存，请回到 Desktop 操作。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const Divider(height: 24),
                  _field('供应商', purchase['supplier_name']),
                  _field('时间', purchase['purchased_at']),
                  _field('Invoice No', purchase['invoice_no']),
                  _field('Invoice Date', purchase['invoice_date']),
                  _field('Discount', _money(purchase['discount_cents'])),
                  _field('Tax / SST', _money(purchase['tax_cents'])),
                  _field('Delivery', _money(purchase['delivery_fee_cents'])),
                  _field('Other Fee', _money(purchase['other_fee_cents'])),
                  _field('状态', reversed ? 'REVERSED' : 'COMMITTED'),
                  _field('备注', purchase['notes']),
                ],
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    '进货明细 / Items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('没有可显示的进货明细'),
                    ),
                  )
                else
                  for (final line in lines)
                    ListTile(
                      title: Text(
                        line['name']?.toString() ??
                            line['rawProductName']?.toString() ??
                            line['productId']?.toString() ??
                            '',
                      ),
                      subtitle: Text(
                        'Qty ${line['invoiceQty'] ?? line['qty'] ?? ''} '
                        '${line['unit'] ?? ''} · Conversion '
                        '${line['conversionFactor'] ?? line['conversion_factor'] ?? 1}',
                      ),
                      trailing: Text(
                        _money(
                          line['subtotalCents'] ?? line['lineSubtotalCents'],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('合计 / Total'),
              trailing: MoneyText(
                amountCents: (purchase['total_cents'] as num?)?.toInt() ?? 0,
                fontSize: 16,
              ),
            ),
          ),
          if (reversed)
            Card(
              child: ListTile(
                title: const Text('此进货已在 Desktop 撤销'),
                subtitle: Text(
                  '${purchase['reversed_at'] ?? ''}\n'
                  '${purchase['reversal_reason'] ?? ''} '
                  '${purchase['reversal_notes'] ?? ''}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
