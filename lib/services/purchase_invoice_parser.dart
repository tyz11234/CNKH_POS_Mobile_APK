import '../models/purchase_ocr.dart';

class PurchaseInvoiceParser {
  const PurchaseInvoiceParser();

  PurchaseDraft parse(
    String rawText, {
    required String draftId,
    required String createdBy,
    String imagePath = '',
    DateTime? now,
  }) {
    final lines = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final supplier = _guessSupplier(lines);
    var invoiceNo = '';
    var invoiceDate = '';
    var discount = 0;
    var tax = 0;
    var delivery = 0;
    var otherFee = 0;
    int? invoiceTotal;
    final parsedLines = <PurchaseDraftLine>[];
    final warnings = <PurchaseWarning>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      invoiceNo = invoiceNo.isEmpty ? (_parseInvoiceNo(line) ?? '') : invoiceNo;
      invoiceDate = invoiceDate.isEmpty ? (_parseDate(line) ?? '') : invoiceDate;

      final money = _lastMoneyCents(line);
      if (_isDiscount(lower) && money != null) {
        discount += money.abs();
        continue;
      }
      if (_isTax(lower) && money != null) {
        tax += money.abs();
        continue;
      }
      if (_isDelivery(lower) && money != null) {
        delivery += money.abs();
        continue;
      }
      if (_isOtherFee(lower) && money != null) {
        otherFee += money.abs();
        continue;
      }
      if (_isGrandTotal(lower) && money != null) {
        invoiceTotal = money.abs();
        continue;
      }
      if (_looksLikeHeader(lower) || _isSubtotal(lower)) continue;

      final parsed = _parseProductLine(line, i);
      if (parsed != null) parsedLines.add(parsed);
    }

    if (parsedLines.isEmpty) {
      warnings.add(const PurchaseWarning(
        code: 'no_product_lines',
        message: '没有可靠识别到商品行，请检查原图或手动录入。',
        level: PurchaseWarningLevel.error,
      ));
    }
    if (invoiceTotal == null) {
      warnings.add(const PurchaseWarning(
        code: 'invoice_total_missing',
        message: '未识别到 Invoice Total，请人工确认整单金额。',
      ));
    }
    if (supplier.isEmpty) {
      warnings.add(const PurchaseWarning(
        code: 'supplier_missing',
        message: '未能自动识别供应商，请人工选择。',
      ));
    }

    return PurchaseDraft(
      draftId: draftId,
      supplierName: supplier,
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      imagePath: imagePath,
      ocrRawText: rawText,
      lines: parsedLines,
      discountCents: discount,
      taxCents: tax,
      deliveryFeeCents: delivery,
      otherFeeCents: otherFee,
      invoiceTotalCents: invoiceTotal,
      warnings: warnings,
      createdAt: (now ?? DateTime.now()).toIso8601String(),
      createdBy: createdBy,
    );
  }

  PurchaseDraftLine? _parseProductLine(String line, int index) {
    final normalized = line
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\bRM\s*', caseSensitive: false), 'RM');

    final pattern = RegExp(
      r'^(.+?)\s+(\d+(?:[.,]\d+)?)\s*([A-Za-z]{1,8})?\s+(?:RM)?\s*([0-9][0-9.,]*)\s+(?:RM)?\s*([0-9][0-9.,]*)$',
      caseSensitive: false,
    );
    final m = pattern.firstMatch(normalized);
    if (m == null) return null;

    final name = (m.group(1) ?? '').trim();
    final qty = _decimal(m.group(2));
    final unit = (m.group(3) ?? 'pcs').trim();
    final unitCost = parseMoneyCents(m.group(4));
    final subtotal = parseMoneyCents(m.group(5));
    if (name.isEmpty || qty == null || qty <= 0 || unitCost == null || subtotal == null) {
      return null;
    }

    return PurchaseDraftLine(
      id: 'ocr-line-$index',
      rawText: line,
      rawProductName: name,
      quantity: qty,
      unit: unit.isEmpty ? 'pcs' : unit,
      unitCostCents: unitCost,
      lineSubtotalCents: subtotal,
      originalQuantity: qty,
      originalUnitCostCents: unitCost,
      originalLineSubtotalCents: subtotal,
    );
  }

  String _guessSupplier(List<String> lines) {
    for (final line in lines.take(8)) {
      final lower = line.toLowerCase();
      if (_looksLikeHeader(lower) ||
          _isSubtotal(lower) ||
          _isGrandTotal(lower) ||
          _parseDate(line) != null ||
          _parseInvoiceNo(line) != null) {
        continue;
      }
      if (RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(line) &&
          !RegExp(r'^\d+[\s\-/:]').hasMatch(line)) {
        return line.length > 120 ? line.substring(0, 120) : line;
      }
    }
    return '';
  }

  String? _parseInvoiceNo(String line) {
    final m = RegExp(
      r'\b(?:invoice|inv|bill)\s*(?:no\.?|#|number)?\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-_/]{2,})',
      caseSensitive: false,
    ).firstMatch(line);
    return m?.group(1)?.trim();
  }

  String? _parseDate(String line) {
    final ymd = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b').firstMatch(line);
    if (ymd != null) {
      return '${ymd.group(1)}-${_two(ymd.group(2))}-${_two(ymd.group(3))}';
    }
    final dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b').firstMatch(line);
    if (dmy != null) {
      return '${dmy.group(3)}-${_two(dmy.group(2))}-${_two(dmy.group(1))}';
    }
    return null;
  }

  String _two(String? v) => (int.tryParse(v ?? '') ?? 0).toString().padLeft(2, '0');

  bool _looksLikeHeader(String lower) =>
      lower.contains('description') ||
      (lower.contains('product') && lower.contains('qty')) ||
      (lower.contains('item') && lower.contains('price')) ||
      lower.contains('invoice no') ||
      lower.startsWith('invoice #') ||
      lower.startsWith('date:');

  bool _isDiscount(String lower) => lower.contains('discount') || lower.contains('rebate');
  bool _isTax(String lower) => lower.contains('sst') || RegExp(r'\btax\b').hasMatch(lower);
  bool _isDelivery(String lower) =>
      lower.contains('delivery') ||
      lower.contains('freight') ||
      lower.contains('shipping') ||
      lower.contains('handling');
  bool _isOtherFee(String lower) => lower.contains('other fee') || lower.contains('service fee');
  bool _isSubtotal(String lower) => lower.contains('subtotal') || lower.contains('sub total');
  bool _isGrandTotal(String lower) =>
      (lower.contains('grand total') || RegExp(r'^total\b').hasMatch(lower)) && !_isSubtotal(lower);

  int? _lastMoneyCents(String line) {
    final matches = RegExp(
      r'(?:RM\s*)?-?\d[\d.,]*',
      caseSensitive: false,
    ).allMatches(line).toList();
    if (matches.isEmpty) return null;
    return parseMoneyCents(matches.last.group(0));
  }

  double? _decimal(String? raw) =>
      double.tryParse((raw ?? '').replaceAll(',', '.').replaceAll(' ', ''));

  /// Parses invoice money without silently dropping thousands separators.
  /// Supports common forms such as RM 1,234.56 and 1.234,56.
  int? parseMoneyCents(String? raw) {
    if (raw == null) return null;
    var s = raw
        .toUpperCase()
        .replaceAll('RM', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    if (s.isEmpty) return null;

    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);
    if (s.isEmpty || !RegExp(r'^\d[\d.,]*$').hasMatch(s)) return null;

    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    String normalized;

    if (lastComma >= 0 && lastDot >= 0) {
      final decimalSeparator = lastComma > lastDot ? ',' : '.';
      final groupingSeparator = decimalSeparator == ',' ? '.' : ',';
      normalized = s.replaceAll(groupingSeparator, '');
      if (decimalSeparator == ',') normalized = normalized.replaceAll(',', '.');
    } else if (lastComma >= 0) {
      final decimals = s.length - lastComma - 1;
      normalized = decimals == 1 || decimals == 2
          ? s.replaceAll(',', '.')
          : s.replaceAll(',', '');
    } else if (lastDot >= 0) {
      final decimals = s.length - lastDot - 1;
      normalized = decimals == 1 || decimals == 2
          ? s
          : s.replaceAll('.', '');
    } else {
      normalized = s;
    }

    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite) return null;
    final cents = (value * 100).round();
    return negative ? -cents : cents;
  }
}
