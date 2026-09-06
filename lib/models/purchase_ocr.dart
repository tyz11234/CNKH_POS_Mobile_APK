enum PurchaseWarningLevel { info, warning, error }

class PurchaseWarning {
  final String code;
  final String message;
  final PurchaseWarningLevel level;

  const PurchaseWarning({
    required this.code,
    required this.message,
    this.level = PurchaseWarningLevel.warning,
  });

  Map<String, Object?> toMap() => {
        'code': code,
        'message': message,
        'level': level.name,
      };

  factory PurchaseWarning.fromMap(Map<String, Object?> map) => PurchaseWarning(
        code: map['code']?.toString() ?? '',
        message: map['message']?.toString() ?? '',
        level: PurchaseWarningLevel.values.firstWhere(
          (e) => e.name == map['level'],
          orElse: () => PurchaseWarningLevel.warning,
        ),
      );
}

class PurchaseDraftLine {
  final String id;
  final String rawText;
  final String rawProductName;
  final String? matchedProductId;
  final String matchedProductName;
  final double matchConfidence;
  final double quantity;
  final String unit;
  final int unitCostCents;
  final int lineSubtotalCents;
  final double? originalQuantity;
  final int? originalUnitCostCents;
  final int? originalLineSubtotalCents;
  final double conversionFactor;
  final List<PurchaseWarning> warnings;
  final bool userModified;

  const PurchaseDraftLine({
    required this.id,
    required this.rawText,
    required this.rawProductName,
    this.matchedProductId,
    this.matchedProductName = '',
    this.matchConfidence = 0,
    required this.quantity,
    this.unit = 'pcs',
    required this.unitCostCents,
    required this.lineSubtotalCents,
    this.originalQuantity,
    this.originalUnitCostCents,
    this.originalLineSubtotalCents,
    this.conversionFactor = 1,
    this.warnings = const [],
    this.userModified = false,
  });

  double get stockQuantity => quantity * conversionFactor;
  int get calculatedSubtotalCents => (quantity * unitCostCents).round();
  int get baseUnitCostCents => conversionFactor <= 0
      ? unitCostCents
      : (unitCostCents / conversionFactor).round();
  bool get isMatched => (matchedProductId ?? '').isNotEmpty;
  bool get hasError =>
      warnings.any((w) => w.level == PurchaseWarningLevel.error);

  PurchaseDraftLine copyWith({
    String? rawText,
    String? rawProductName,
    String? matchedProductId,
    bool clearMatchedProduct = false,
    String? matchedProductName,
    double? matchConfidence,
    double? quantity,
    String? unit,
    int? unitCostCents,
    int? lineSubtotalCents,
    double? originalQuantity,
    int? originalUnitCostCents,
    int? originalLineSubtotalCents,
    double? conversionFactor,
    List<PurchaseWarning>? warnings,
    bool? userModified,
  }) =>
      PurchaseDraftLine(
        id: id,
        rawText: rawText ?? this.rawText,
        rawProductName: rawProductName ?? this.rawProductName,
        matchedProductId:
            clearMatchedProduct ? null : (matchedProductId ?? this.matchedProductId),
        matchedProductName: matchedProductName ?? this.matchedProductName,
        matchConfidence: matchConfidence ?? this.matchConfidence,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        unitCostCents: unitCostCents ?? this.unitCostCents,
        lineSubtotalCents: lineSubtotalCents ?? this.lineSubtotalCents,
        originalQuantity: originalQuantity ?? this.originalQuantity,
        originalUnitCostCents:
            originalUnitCostCents ?? this.originalUnitCostCents,
        originalLineSubtotalCents:
            originalLineSubtotalCents ?? this.originalLineSubtotalCents,
        conversionFactor: conversionFactor ?? this.conversionFactor,
        warnings: warnings ?? this.warnings,
        userModified: userModified ?? this.userModified,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'raw_text': rawText,
        'raw_product_name': rawProductName,
        'matched_product_id': matchedProductId,
        'matched_product_name': matchedProductName,
        'match_confidence': matchConfidence,
        'quantity': quantity,
        'unit': unit,
        'unit_cost_cents': unitCostCents,
        'line_subtotal_cents': lineSubtotalCents,
        'original_quantity': originalQuantity,
        'original_unit_cost_cents': originalUnitCostCents,
        'original_line_subtotal_cents': originalLineSubtotalCents,
        'conversion_factor': conversionFactor,
        'warnings': warnings.map((w) => w.toMap()).toList(),
        'user_modified': userModified ? 1 : 0,
      };

  factory PurchaseDraftLine.fromMap(Map<String, Object?> map) {
    final rawWarnings = (map['warnings'] as List?) ?? const [];
    return PurchaseDraftLine(
      id: map['id']?.toString() ?? '',
      rawText: map['raw_text']?.toString() ?? '',
      rawProductName: map['raw_product_name']?.toString() ?? '',
      matchedProductId: map['matched_product_id']?.toString(),
      matchedProductName: map['matched_product_name']?.toString() ?? '',
      matchConfidence: (map['match_confidence'] as num?)?.toDouble() ?? 0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: map['unit']?.toString() ?? 'pcs',
      unitCostCents: (map['unit_cost_cents'] as num?)?.toInt() ?? 0,
      lineSubtotalCents:
          (map['line_subtotal_cents'] as num?)?.toInt() ?? 0,
      originalQuantity: (map['original_quantity'] as num?)?.toDouble(),
      originalUnitCostCents:
          (map['original_unit_cost_cents'] as num?)?.toInt(),
      originalLineSubtotalCents:
          (map['original_line_subtotal_cents'] as num?)?.toInt(),
      conversionFactor:
          (map['conversion_factor'] as num?)?.toDouble() ?? 1,
      warnings: rawWarnings
          .whereType<Map>()
          .map((w) => PurchaseWarning.fromMap(Map<String, Object?>.from(w)))
          .toList(),
      userModified: map['user_modified'] == true || map['user_modified'] == 1,
    );
  }
}

class PurchaseDraft {
  final String draftId;
  final String? supplierId;
  final String supplierName;
  final String invoiceNo;
  final String invoiceDate;
  final String imagePath;
  final String ocrRawText;
  final List<PurchaseDraftLine> lines;
  final int discountCents;
  final int taxCents;
  final int deliveryFeeCents;
  final int otherFeeCents;
  final int? invoiceTotalCents;
  final List<PurchaseWarning> warnings;
  final String createdAt;
  final String createdBy;
  final String status;

  const PurchaseDraft({
    required this.draftId,
    this.supplierId,
    this.supplierName = '',
    this.invoiceNo = '',
    this.invoiceDate = '',
    this.imagePath = '',
    this.ocrRawText = '',
    this.lines = const [],
    this.discountCents = 0,
    this.taxCents = 0,
    this.deliveryFeeCents = 0,
    this.otherFeeCents = 0,
    this.invoiceTotalCents,
    this.warnings = const [],
    required this.createdAt,
    required this.createdBy,
    this.status = 'draft',
  });

  int get linesSubtotalCents =>
      lines.fold<int>(0, (sum, line) => sum + line.lineSubtotalCents);

  int get calculatedTotalCents => linesSubtotalCents - discountCents +
      taxCents +
      deliveryFeeCents +
      otherFeeCents;

  bool get hasBlockingIssues =>
      (supplierId ?? '').isEmpty ||
      lines.isEmpty ||
      lines.any((l) => !l.isMatched || l.hasError) ||
      warnings.any((w) => w.level == PurchaseWarningLevel.error);

  PurchaseDraft copyWith({
    String? supplierId,
    bool clearSupplier = false,
    String? supplierName,
    String? invoiceNo,
    String? invoiceDate,
    String? imagePath,
    String? ocrRawText,
    List<PurchaseDraftLine>? lines,
    int? discountCents,
    int? taxCents,
    int? deliveryFeeCents,
    int? otherFeeCents,
    int? invoiceTotalCents,
    bool clearInvoiceTotal = false,
    List<PurchaseWarning>? warnings,
    String? status,
  }) =>
      PurchaseDraft(
        draftId: draftId,
        supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
        supplierName: supplierName ?? this.supplierName,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        invoiceDate: invoiceDate ?? this.invoiceDate,
        imagePath: imagePath ?? this.imagePath,
        ocrRawText: ocrRawText ?? this.ocrRawText,
        lines: lines ?? this.lines,
        discountCents: discountCents ?? this.discountCents,
        taxCents: taxCents ?? this.taxCents,
        deliveryFeeCents: deliveryFeeCents ?? this.deliveryFeeCents,
        otherFeeCents: otherFeeCents ?? this.otherFeeCents,
        invoiceTotalCents:
            clearInvoiceTotal ? null : (invoiceTotalCents ?? this.invoiceTotalCents),
        warnings: warnings ?? this.warnings,
        createdAt: createdAt,
        createdBy: createdBy,
        status: status ?? this.status,
      );
}
