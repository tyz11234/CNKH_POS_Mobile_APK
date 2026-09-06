import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/pos_repository.dart';
import '../../services/purchase_ocr_repository.dart';
import '../../theme/cnkh_theme.dart';

class SupplierAliasesPage extends StatefulWidget {
  const SupplierAliasesPage({super.key, required this.repo});

  final PosRepository repo;

  @override
  State<SupplierAliasesPage> createState() => _SupplierAliasesPageState();
}

class _SupplierAliasesPageState extends State<SupplierAliasesPage> {
  late final PurchaseOcrRepository _ocr = PurchaseOcrRepository(widget.repo);
  List<Map<String, Object?>> _aliases = const [];
  List<Supplier> _suppliers = const [];
  List<Product> _products = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final aliases = await _ocr.listAliases();
    final suppliers = await widget.repo.listSuppliers();
    final products = await widget.repo.searchProducts('', limit: 5000);
    if (!mounted) return;
    setState(() {
      _aliases = aliases;
      _suppliers = suppliers;
      _products = products.where((p) => p.isDeleted == 0).toList();
      _loading = false;
    });
  }

  String _supplierName(String id) {
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier.name;
    }
    return id;
  }

  String _productName(String id) {
    for (final product in _products) {
      if (product.id == id) return product.nameZh;
    }
    return id;
  }

  Future<void> _edit(Map<String, Object?> alias) async {
    if (_busy || _products.isEmpty) return;
    var productId = alias['product_id']?.toString() ?? '';
    if (!_products.any((p) => p.id == productId)) {
      productId = _products.first.id;
    }
    final unit = TextEditingController(
      text: alias['unit']?.toString().trim().isNotEmpty == true
          ? alias['unit'].toString()
          : 'pcs',
    );
    final conversion = TextEditingController(
      text: ((alias['conversion_factor'] as num?)?.toDouble() ?? 1)
          .toString(),
    );
    String? conversionError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('编辑供应商商品记忆'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  alias['raw_name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: '匹配商品 / Product'),
                  items: [
                    for (final product in _products)
                      DropdownMenuItem(
                        value: product.id,
                        child: Text('${product.nameZh} · ${product.sku}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setLocal(() => productId = value);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: unit,
                  decoration: const InputDecoration(labelText: '进货单位 / Unit'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: conversion,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (conversionError != null) {
                      setLocal(() => conversionError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '换算倍率 / Conversion factor',
                    errorText: conversionError,
                  ),
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
                final factor = double.tryParse(conversion.text.trim());
                if (factor == null || !factor.isFinite || factor <= 0) {
                  setLocal(() => conversionError = '必须是大于 0 的有效数字');
                  return;
                }
                if (unit.text.trim().isEmpty) {
                  setLocal(() => conversionError = '单位不能为空');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      unit.dispose();
      conversion.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await _ocr.updateAlias(
        aliasId: alias['id'] as String,
        productId: productId,
        unit: unit.text.trim(),
        conversionFactor: double.parse(conversion.text.trim()),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('供应商商品记忆已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      unit.dispose();
      conversion.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, Object?> alias) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除商品记忆？'),
        content: Text(
          '删除「${alias['raw_name'] ?? ''}」的供应商匹配记忆？\n'
          '不会删除商品、供应商或历史进货记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _ocr.deleteAlias(alias['id'] as String);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('供应商商品记忆 / Aliases')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _aliases.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '暂无已确认的供应商商品记忆。\n只有人工确认并入库后的 OCR 匹配才会写入这里。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _aliases.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final alias = _aliases[index];
                          final supplierId = alias['supplier_id']?.toString() ?? '';
                          final productId = alias['product_id']?.toString() ?? '';
                          final factor =
                              (alias['conversion_factor'] as num?)?.toDouble() ?? 1;
                          return ListTile(
                            title: Text(
                              alias['raw_name']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${_supplierName(supplierId)} → ${_productName(productId)}\n'
                              '${alias['unit'] ?? 'pcs'} × $factor · 已确认使用 ${alias['use_count'] ?? 0} 次',
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: '编辑 / Edit',
                                  onPressed: _busy ? null : () => _edit(alias),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: '删除 / Delete',
                                  onPressed: _busy ? null : () => _delete(alias),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                if (_busy)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color(0x22000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
