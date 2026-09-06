import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../models/purchase_ocr.dart';
import '../../services/ocr_service.dart';
import '../../services/pos_repository.dart';
import '../../services/purchase_invoice_image_store.dart';
import '../../services/purchase_invoice_parser.dart';
import '../../services/purchase_ocr_repository.dart';
import '../../theme/cnkh_theme.dart';

class PurchaseOcrScreen extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  final ImageSource? source;
  final String? draftId;

  const PurchaseOcrScreen({
    super.key,
    required this.repo,
    required this.user,
    this.source,
    this.draftId,
  }) : assert(source != null || draftId != null);

  @override
  State<PurchaseOcrScreen> createState() => _PurchaseOcrScreenState();
}

class _PurchaseOcrScreenState extends State<PurchaseOcrScreen> {
  late final PurchaseOcrRepository _ocrRepo = PurchaseOcrRepository(widget.repo);
  final _recognizer = LocalOcrService();
  final _imageStore = const PurchaseInvoiceImageStore();
  final _parser = const PurchaseInvoiceParser();
  PurchaseDraft? _draft;
  List<Supplier> _suppliers = const [];
  List<Product> _products = const [];
  bool _busy = true;
  bool _onlyExceptions = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _suppliers = await widget.repo.listSuppliers();
      _products = await widget.repo.searchProducts('', limit: 5000);

      PurchaseDraft draft;
      final existingDraftId = widget.draftId;
      if (existingDraftId != null) {
        final saved = await _ocrRepo.loadDraft(existingDraftId);
        if (saved == null) throw StateError('OCR 草稿不存在或已处理');
        draft = await _ocrRepo.validateDraft(saved);
      } else {
        final picked = await ImagePicker().pickImage(source: widget.source!);
        if (picked == null) {
          if (mounted) Navigator.pop(context);
          return;
        }
        final draftId = AppDatabase.newId();
        final savedPath = await _imageStore.saveCompressed(picked.path, draftId);
        final rawText = await _recognizer.recognizeFile(savedPath);
        draft = _parser.parse(
          rawText,
          draftId: draftId,
          createdBy: widget.user.username,
          imagePath: savedPath,
        );
        draft = await _ocrRepo.prepareDraft(draft);
      }
      await _ocrRepo.saveDraft(draft);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _revalidate({bool save = true}) async {
    final draft = _draft;
    if (draft == null) return;
    final checked = await _ocrRepo.validateDraft(draft);
    if (save) await _ocrRepo.saveDraft(checked);
    if (mounted) setState(() => _draft = checked);
  }

  Future<void> _editLine(int index) async {
    final draft = _draft!;
    final line = draft.lines[index];
    String? productId = line.matchedProductId;
    if (productId != null && !_products.any((p) => p.id == productId)) {
      productId = null;
    }
    final qty = TextEditingController(text: line.quantity.toString());
    final unit = TextEditingController(text: line.unit);
    final cost = TextEditingController(
      text: (line.unitCostCents / 100).toStringAsFixed(2),
    );
    final subtotal = TextEditingController(
      text: (line.lineSubtotalCents / 100).toStringAsFixed(2),
    );
    final conversion =
        TextEditingController(text: line.conversionFactor.toString());

    String? qtyError;
    String? conversionError;
    String? costError;
    String? subtotalError;
    double? parsedQty;
    double? parsedConversion;
    int? parsedCost;
    int? parsedSubtotal;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('核对商品 / Review line'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'OCR：${line.rawProductName}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '匹配商品'),
                    items: [
                      for (final p in _products)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nameZh, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => productId = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (qtyError != null) setLocal(() => qtyError = null);
                    },
                    decoration: InputDecoration(
                      labelText: '数量 / Qty',
                      errorText: qtyError,
                    ),
                  ),
                  TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: '单位 / Unit'),
                  ),
                  TextField(
                    controller: conversion,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (conversionError != null) {
                        setLocal(() => conversionError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '换算倍率 / Conversion',
                      helperText: '普通单件保持 1；例如 1 CTN = 24 PCS 时填 24',
                      errorText: conversionError,
                    ),
                  ),
                  TextField(
                    controller: cost,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (costError != null) setLocal(() => costError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'OCR 单位成本',
                      prefixText: 'RM ',
                      errorText: costError,
                    ),
                  ),
                  TextField(
                    controller: subtotal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (subtotalError != null) {
                        setLocal(() => subtotalError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'OCR 行小计',
                      prefixText: 'RM ',
                      errorText: subtotalError,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qty.text.trim());
                final c = double.tryParse(conversion.text.trim());
                final unitCost = _parser.parseMoneyCents(cost.text.trim());
                final lineSubtotal =
                    _parser.parseMoneyCents(subtotal.text.trim());
                final nextQtyError = q == null || !q.isFinite || q <= 0
                    ? '数量必须是大于 0 的有效数字'
                    : null;
                final nextConversionError =
                    c == null || !c.isFinite || c <= 0
                        ? '换算倍率必须是大于 0 的有效数字'
                        : null;
                final nextCostError = unitCost == null ? '金额格式错误' : null;
                final nextSubtotalError =
                    lineSubtotal == null ? '金额格式错误' : null;
                if (nextQtyError != null ||
                    nextConversionError != null ||
                    nextCostError != null ||
                    nextSubtotalError != null) {
                  setLocal(() {
                    qtyError = nextQtyError;
                    conversionError = nextConversionError;
                    costError = nextCostError;
                    subtotalError = nextSubtotalError;
                  });
                  return;
                }
                parsedQty = q;
                parsedConversion = c;
                parsedCost = unitCost;
                parsedSubtotal = lineSubtotal;
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || productId == null) return;
    final product = _products.firstWhere((p) => p.id == productId);
    final nextLine = line.copyWith(
      matchedProductId: product.id,
      matchedProductName: product.nameZh,
      matchConfidence: 1,
      quantity: parsedQty!,
      unit: unit.text.trim().isEmpty ? line.unit : unit.text.trim(),
      conversionFactor: parsedConversion!,
      unitCostCents: parsedCost!,
      lineSubtotalCents: parsedSubtotal!,
      userModified: true,
    );
    final lines = [...draft.lines]..[index] = nextLine;
    setState(() => _draft = draft.copyWith(lines: lines));
    await _revalidate();
  }

  Future<void> _editFees() async {
    final draft = _draft!;
    final discount = _moneyCtrl(draft.discountCents);
    final tax = _moneyCtrl(draft.taxCents);
    final delivery = _moneyCtrl(draft.deliveryFeeCents);
    final other = _moneyCtrl(draft.otherFeeCents);
    final invoice = TextEditingController(
      text: draft.invoiceTotalCents == null
          ? ''
          : (draft.invoiceTotalCents! / 100).toStringAsFixed(2),
    );
    final no = TextEditingController(text: draft.invoiceNo);
    final date = TextEditingController(text: draft.invoiceDate);

    String? discountError;
    String? taxError;
    String? deliveryError;
    String? otherError;
    String? invoiceError;
    int parsedDiscount = draft.discountCents;
    int parsedTax = draft.taxCents;
    int parsedDelivery = draft.deliveryFeeCents;
    int parsedOther = draft.otherFeeCents;
    int? parsedInvoice = draft.invoiceTotalCents;

    int? parseFee(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return 0;
      return _parser.parseMoneyCents(text);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('单据金额 / Invoice totals'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: no,
                  decoration: const InputDecoration(labelText: 'Invoice No'),
                ),
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Date (YYYY-MM-DD)',
                  ),
                ),
                _moneyField(
                  discount,
                  'Discount',
                  errorText: discountError,
                  onChanged: (_) {
                    if (discountError != null) {
                      setLocal(() => discountError = null);
                    }
                  },
                ),
                _moneyField(
                  tax,
                  'Tax / SST',
                  errorText: taxError,
                  onChanged: (_) {
                    if (taxError != null) setLocal(() => taxError = null);
                  },
                ),
                _moneyField(
                  delivery,
                  'Delivery / Freight',
                  errorText: deliveryError,
                  onChanged: (_) {
                    if (deliveryError != null) {
                      setLocal(() => deliveryError = null);
                    }
                  },
                ),
                _moneyField(
                  other,
                  'Other Fee',
                  errorText: otherError,
                  onChanged: (_) {
                    if (otherError != null) setLocal(() => otherError = null);
                  },
                ),
                _moneyField(
                  invoice,
                  'Invoice Total',
                  errorText: invoiceError,
                  onChanged: (_) {
                    if (invoiceError != null) {
                      setLocal(() => invoiceError = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final d = parseFee(discount);
                final t = parseFee(tax);
                final deliveryValue = parseFee(delivery);
                final o = parseFee(other);
                final invoiceText = invoice.text.trim();
                final inv = invoiceText.isEmpty
                    ? null
                    : _parser.parseMoneyCents(invoiceText);
                final nextDiscountError = d == null ? '金额格式错误' : null;
                final nextTaxError = t == null ? '金额格式错误' : null;
                final nextDeliveryError =
                    deliveryValue == null ? '金额格式错误' : null;
                final nextOtherError = o == null ? '金额格式错误' : null;
                final nextInvoiceError =
                    invoiceText.isNotEmpty && inv == null ? '金额格式错误' : null;
                if (nextDiscountError != null ||
                    nextTaxError != null ||
                    nextDeliveryError != null ||
                    nextOtherError != null ||
                    nextInvoiceError != null) {
                  setLocal(() {
                    discountError = nextDiscountError;
                    taxError = nextTaxError;
                    deliveryError = nextDeliveryError;
                    otherError = nextOtherError;
                    invoiceError = nextInvoiceError;
                  });
                  return;
                }
                parsedDiscount = d!;
                parsedTax = t!;
                parsedDelivery = deliveryValue!;
                parsedOther = o!;
                parsedInvoice = inv;
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _draft = draft.copyWith(
        invoiceNo: no.text.trim(),
        invoiceDate: date.text.trim(),
        discountCents: parsedDiscount,
        taxCents: parsedTax,
        deliveryFeeCents: parsedDelivery,
        otherFeeCents: parsedOther,
        invoiceTotalCents: parsedInvoice,
        clearInvoiceTotal: parsedInvoice == null,
      );
    });
    await _revalidate();
  }

  TextEditingController _moneyCtrl(int cents) =>
      TextEditingController(text: (cents / 100).toStringAsFixed(2));

  Widget _moneyField(
    TextEditingController c,
    String label, {
    String? errorText,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'RM ',
          errorText: errorText,
        ),
      );

  Future<void> _selectSupplier(String? id) async {
    if (id == null) return;
    final supplier = _suppliers.firstWhere((s) => s.id == id);
    setState(() {
      _draft = _draft!.copyWith(
        supplierId: supplier.id,
        supplierName: supplier.name,
      );
    });
    await _revalidate();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    var committed = false;
    try {
      await _revalidate();
      final draft = _draft!;
      if (draft.hasBlockingIssues) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请先处理红色错误和未匹配商品，OCR 不会直接入库。'),
            ),
          );
        }
        return;
      }
      final warnings = [
        ...draft.warnings,
        ...draft.lines.expand((l) => l.warnings),
      ].where((w) => w.level == PurchaseWarningLevel.warning).toList();
      if (warnings.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('仍有警告，确认入库？'),
            content: SizedBox(
              width: 520,
              child: ListView(
                shrinkWrap: true,
                children: warnings
                    .take(12)
                    .map((w) => Text('• ${w.message}'))
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续检查'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认入库'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      await _ocrRepo.commitDraft(draft, operator: widget.user.username);
      committed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR 进货已确认入库')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (!committed && mounted) setState(() => _busy = false);
    }
  }

  void _showRawText() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OCR 原文'),
        content: SizedBox(
          width: 600,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(_draft!.ocrRawText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('OCR 进货 / OCR Purchase')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(widget.draftId == null ? '正在本机识别进货单…' : '正在载入 OCR 草稿…'),
              const Text('OCR 结果只会生成草稿，不会自动改库存。'),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('OCR 进货 / OCR Purchase')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text('OCR 草稿处理失败，库存没有任何变化。'),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回进货'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final draft = _draft!;
    final visible = <MapEntry<int, PurchaseDraftLine>>[
      for (var i = 0; i < draft.lines.length; i++) MapEntry(i, draft.lines[i]),
    ].where((e) {
      if (!_onlyExceptions) return true;
      return !e.value.isMatched || e.value.warnings.isNotEmpty;
    }).toList();
    final warningCount = draft.warnings.length +
        draft.lines.fold<int>(0, (sum, l) => sum + l.warnings.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR 进货 / OCR Purchase'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _showRawText,
            tooltip: 'OCR 原文',
            icon: const Icon(Icons.text_snippet_outlined),
          ),
          IconButton(
            onPressed: _busy ? null : _editFees,
            tooltip: '单据金额',
            icon: const Icon(Icons.calculate_outlined),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _ocrRepo.saveDraft(draft);
                          if (mounted) Navigator.pop(context, false);
                        },
                  child: const Text('保存草稿'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认并入库'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (draft.imagePath.isNotEmpty && File(draft.imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(draft.imagePath),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: (draft.supplierId ?? '').isEmpty
                        ? null
                        : draft.supplierId,
                    decoration: const InputDecoration(
                      labelText: '供应商 / Supplier',
                    ),
                    items: [
                      for (final s in _suppliers)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: _busy ? null : _selectSupplier,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invoice: ${draft.invoiceNo.isEmpty ? '未识别' : draft.invoiceNo}',
                  ),
                  Text(
                    'Date: ${draft.invoiceDate.isEmpty ? '未识别' : draft.invoiceDate}',
                  ),
                  const SizedBox(height: 8),
                  Text('商品行 ${draft.lines.length} · 警告/提示 $warningCount'),
                  Text('商品小计 ${formatRm(draft.linesSubtotalCents)}'),
                  Text(
                    'Discount -${formatRm(draft.discountCents)} · SST ${formatRm(draft.taxCents)}',
                  ),
                  Text(
                    'Delivery ${formatRm(draft.deliveryFeeCents)} · Other ${formatRm(draft.otherFeeCents)}',
                  ),
                  Text(
                    '系统计算 ${formatRm(draft.calculatedTotalCents)} · 单据 ${draft.invoiceTotalCents == null ? '未识别' : formatRm(draft.invoiceTotalCents!)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _editFees,
                    icon: const Icon(Icons.edit),
                    label: const Text('核对单据编号、日期和费用'),
                  ),
                ],
              ),
            ),
          ),
          for (final w in draft.warnings) _warningTile(w),
          SwitchListTile(
            value: _onlyExceptions,
            onChanged: _busy ? null : (v) => setState(() => _onlyExceptions = v),
            title: const Text('只看异常 / Exceptions only'),
          ),
          ...visible.map((entry) {
            final line = entry.value;
            final product = line.isMatched
                ? _products
                    .where((p) => p.id == line.matchedProductId)
                    .firstOrNull
                : null;
            final stockAfter =
                product == null ? null : product.stock + line.stockQuantity;
            return Card(
              child: InkWell(
                onTap: _busy ? null : () => _editLine(entry.key),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.rawProductName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        line.isMatched
                            ? '→ ${line.matchedProductName} · ${(line.matchConfidence * 100).round()}%'
                            : '→ 未匹配 / Unmatched',
                        style: TextStyle(
                          color: line.isMatched
                              ? CnkhColors.muted
                              : CnkhColors.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${line.quantity} ${line.unit} × ${formatRm(line.unitCostCents)} = ${formatRm(line.lineSubtotalCents)}',
                      ),
                      if (product != null)
                        Text(
                          '库存 ${product.stock} → ${stockAfter?.toStringAsFixed(2)} ${product.unit} · 成本 ${formatRm(product.costCents)} → ${formatRm(line.baseUnitCostCents)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: CnkhColors.muted,
                          ),
                        ),
                      for (final w in line.warnings) _warningInline(w),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _warningTile(PurchaseWarning w) => Card(
        color: w.level == PurchaseWarningLevel.error
            ? const Color(0xFFFFECEC)
            : const Color(0xFFFFF7E6),
        child: ListTile(
          dense: true,
          leading: Icon(
            w.level == PurchaseWarningLevel.error
                ? Icons.error_outline
                : Icons.warning_amber_rounded,
          ),
          title: Text(w.message),
        ),
      );

  Widget _warningInline(PurchaseWarning w) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '⚠ ${w.message}',
          style: TextStyle(
            fontSize: 12,
            color: w.level == PurchaseWarningLevel.error
                ? CnkhColors.danger
                : const Color(0xFF8A6500),
          ),
        ),
      );
}

class PurchaseDetailScreen extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  final String purchaseId;

  const PurchaseDetailScreen({
    super.key,
    required this.repo,
    required this.user,
    required this.purchaseId,
  });

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  late final PurchaseOcrRepository _ocrRepo = PurchaseOcrRepository(widget.repo);
  Map<String, Object?>? _purchase;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await _ocrRepo.getPurchase(widget.purchaseId);
    if (mounted) {
      setState(() {
        _purchase = row;
        _loading = false;
      });
    }
  }

  Future<void> _reverse() async {
    var reason = 'OCR error';
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('撤销这次进货？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('不会删除原记录；系统会生成反向库存流水。'),
              DropdownButtonFormField<String>(
                value: reason,
                items: const [
                  DropdownMenuItem(
                    value: 'Duplicate entry',
                    child: Text('重复入库'),
                  ),
                  DropdownMenuItem(
                    value: 'OCR error',
                    child: Text('OCR 识别错误'),
                  ),
                  DropdownMenuItem(
                    value: 'Supplier invoice error',
                    child: Text('供应商单据错误'),
                  ),
                  DropdownMenuItem(
                    value: 'Cancelled',
                    child: Text('进货取消'),
                  ),
                  DropdownMenuItem(value: 'Other', child: Text('其他')),
                ],
                onChanged: (v) => setLocal(() => reason = v ?? reason),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认撤销'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _ocrRepo.reversePurchase(
        purchaseId: widget.purchaseId,
        operator: widget.user.username,
        reason: reason,
        notes: notes.text.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('进货已撤销，库存已生成反向流水')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _showRaw(String raw) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OCR 原文'),
        content: SizedBox(
          width: 600,
          height: 420,
          child: SingleChildScrollView(child: SelectableText(raw)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('进货详情')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final p = _purchase;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('进货详情')),
        body: const Center(child: Text('记录不存在')),
      );
    }
    final lines = (jsonDecode(p['lines_json'] as String) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final reversed = p['reversed'] == 1;
    final imagePath = p['image_path']?.toString() ?? '';
    final rawText = p['ocr_raw_text']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text('${p['purchase_no']}'),
        actions: [
          if (rawText.isNotEmpty)
            IconButton(
              onPressed: () => _showRaw(rawText),
              icon: const Icon(Icons.text_snippet_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (imagePath.isNotEmpty && File(imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath),
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          Card(
            child: ListTile(
              title: Text('${p['supplier_name']}'),
              subtitle: Text(
                '${p['purchased_at']}\nInvoice ${p['invoice_no'] ?? ''} ${p['invoice_date'] ?? ''}\n'
                '来源 ${p['source'] ?? 'manual'}${reversed ? ' · 已撤销' : ''}',
              ),
              isThreeLine: true,
              trailing: Text(formatRm(p['total_cents'] as int)),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Discount ${formatRm((p['discount_cents'] as num?)?.toInt() ?? 0)} · '
                'SST ${formatRm((p['tax_cents'] as num?)?.toInt() ?? 0)}\n'
                'Delivery ${formatRm((p['delivery_fee_cents'] as num?)?.toInt() ?? 0)} · '
                'Other ${formatRm((p['other_fee_cents'] as num?)?.toInt() ?? 0)}',
              ),
            ),
          ),
          ...lines.map(
            (line) => ListTile(
              title: Text(
                line['name']?.toString() ??
                    line['rawProductName']?.toString() ??
                    '',
              ),
              subtitle: Text(
                '${line['invoiceQty'] ?? line['qty']} ${line['unit'] ?? ''} × '
                '${formatRm((line['invoiceUnitCostCents'] as num?)?.toInt() ?? (line['unitCostCents'] as num?)?.toInt() ?? 0)}',
              ),
              trailing: Text(
                formatRm((line['subtotalCents'] as num?)?.toInt() ?? 0),
              ),
            ),
          ),
          if (reversed)
            Card(
              color: const Color(0xFFFFECEC),
              child: ListTile(
                title: const Text('此进货已撤销'),
                subtitle: Text(
                  '${p['reversed_at'] ?? ''}\n${p['reversal_reason'] ?? ''} ${p['reversal_notes'] ?? ''}',
                ),
              ),
            ),
          if (widget.user.isAdmin && !reversed)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton.icon(
                onPressed: _reverse,
                icon: const Icon(Icons.undo),
                label: const Text('撤销最近这次进货 / Reverse purchase'),
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
