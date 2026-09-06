import '../models/purchase_ocr.dart';

class PurchaseHistorySample {
  /// Typical quantity in the POS base stock unit (for example PCS, not CTN).
  final double? typicalQuantity;

  /// Previous cost in cents per POS base stock unit.
  final int? lastUnitCostCents;

  const PurchaseHistorySample({this.typicalQuantity, this.lastUnitCostCents});
}

class PurchaseValidationService {
  const PurchaseValidationService({
    this.lineToleranceCents = 5,
    this.invoiceToleranceCents = 10,
    this.quantityMultiplierWarning = 3,
    this.costChangeWarningRatio = 0.30,
  });

  final int lineToleranceCents;
  final int invoiceToleranceCents;
  final double quantityMultiplierWarning;
  final double costChangeWarningRatio;

  List<PurchaseWarning> validateLine(
    PurchaseDraftLine line, {
    PurchaseHistorySample history = const PurchaseHistorySample(),
  }) {
    final out = <PurchaseWarning>[];
    if (!line.quantity.isFinite || line.quantity <= 0) {
      out.add(const PurchaseWarning(
        code: 'invalid_quantity',
        message: '数量必须大于 0。',
        level: PurchaseWarningLevel.error,
      ));
    }
    if (!line.conversionFactor.isFinite || line.conversionFactor <= 0) {
      out.add(const PurchaseWarning(
        code: 'invalid_conversion_factor',
        message: '换算倍率必须是大于 0 的有效数字。',
        level: PurchaseWarningLevel.error,
      ));
    }
    if (line.unitCostCents < 0 || line.lineSubtotalCents < 0) {
      out.add(const PurchaseWarning(
        code: 'invalid_cost',
        message: '成本或小计不能为负数。',
        level: PurchaseWarningLevel.error,
      ));
    }
    if (!line.isMatched) {
      out.add(const PurchaseWarning(
        code: 'product_unmatched',
        message: '商品尚未匹配，确认前必须人工选择商品。',
        level: PurchaseWarningLevel.error,
      ));
    } else if (line.matchConfidence < 0.72) {
      out.add(PurchaseWarning(
        code: 'low_match_confidence',
        message: '商品匹配可信度较低（${(line.matchConfidence * 100).round()}%），请确认。',
      ));
    }

    final mathDelta = (line.calculatedSubtotalCents - line.lineSubtotalCents).abs();
    if (mathDelta > lineToleranceCents) {
      out.add(PurchaseWarning(
        code: 'line_math_mismatch',
        message:
            '数量 × 单价与行小计相差 RM ${(mathDelta / 100).toStringAsFixed(2)}，请核对 OCR 数字。',
      ));
    }

    final typical = history.typicalQuantity;
    final stockQuantity = line.stockQuantity;
    if (typical != null &&
        typical > 0 &&
        stockQuantity.isFinite &&
        stockQuantity >= typical * quantityMultiplierWarning) {
      out.add(PurchaseWarning(
        code: 'quantity_anomaly',
        message:
            '本次换算后数量 ${stockQuantity.toStringAsFixed(2)} 明显高于近期常见数量 ${typical.toStringAsFixed(2)}，请确认数量与换算倍率。',
      ));
    }

    final previousCost = history.lastUnitCostCents;
    if (previousCost != null && previousCost > 0 && line.conversionFactor.isFinite && line.conversionFactor > 0) {
      final currentBaseCost = line.baseUnitCostCents;
      final ratio = (currentBaseCost - previousCost).abs() / previousCost;
      if (ratio >= costChangeWarningRatio) {
        out.add(PurchaseWarning(
          code: 'cost_anomaly',
          message:
              '基础单位成本与上次相差 ${(ratio * 100).toStringAsFixed(0)}%（上次 RM ${(previousCost / 100).toStringAsFixed(2)}）。',
        ));
      }
    }
    return out;
  }

  List<PurchaseWarning> validateDraft(PurchaseDraft draft) {
    final out = <PurchaseWarning>[];
    if ((draft.supplierId ?? '').isEmpty) {
      out.add(const PurchaseWarning(
        code: 'supplier_required',
        message: '请选择供应商。',
        level: PurchaseWarningLevel.error,
      ));
    }
    if (draft.lines.isEmpty) {
      out.add(const PurchaseWarning(
        code: 'lines_required',
        message: '进货单没有商品行。',
        level: PurchaseWarningLevel.error,
      ));
    }
    final invoiceTotal = draft.invoiceTotalCents;
    if (invoiceTotal != null) {
      final delta = (draft.calculatedTotalCents - invoiceTotal).abs();
      if (delta > invoiceToleranceCents) {
        out.add(PurchaseWarning(
          code: 'invoice_total_mismatch',
          message:
              '系统计算 RM ${(draft.calculatedTotalCents / 100).toStringAsFixed(2)} 与单据总额 RM ${(invoiceTotal / 100).toStringAsFixed(2)} 相差 RM ${(delta / 100).toStringAsFixed(2)}。',
        ));
      }
    }
    return out;
  }
}
