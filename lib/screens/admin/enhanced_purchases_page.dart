import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../services/pos_repository.dart';
import '../../widgets/money_text.dart';
import 'purchase_ocr_screen.dart';

class EnhancedPurchasesPage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;

  const EnhancedPurchasesPage({
    super.key,
    required this.repo,
    required this.user,
  });

  @override
  State<EnhancedPurchasesPage> createState() => _EnhancedPurchasesPageState();
}

class _EnhancedPurchasesPageState extends State<EnhancedPurchasesPage> {
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _rows = await widget.repo.listPurchases();
    if (mounted) setState(() {});
  }

  Future<void> _chooseCreate() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('新增进货 / New Purchase',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('OCR 只生成草稿，核对并确认后才会更新库存。'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('拍照扫描进货单'),
              subtitle: const Text('本机离线 OCR · Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择进货单'),
              subtitle: const Text('本机离线 OCR · Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('手动进货'),
              subtitle: const Text('保留原有 Simple Purchase 流程'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'manual') {
      await _createManual();
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseOcrScreen(
          repo: widget.repo,
          user: widget.user,
          source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        ),
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _createManual() async {
    final suppliers = await widget.repo.listSuppliers();
    final products = await widget.repo.searchProducts('', limit: 50);
    if (!mounted || suppliers.isEmpty || products.isEmpty) return;
    var supplier = suppliers.first;
    var product = products.first;
    final qty = TextEditingController(text: '10');
    final cost = TextEditingController(
      text: centsToRm(product.costCents).toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('简易进货 / Simple purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Supplier>(
                isExpanded: true,
                value: supplier,
                items: [
                  for (final s in suppliers)
                    DropdownMenuItem(value: s, child: Text(s.name)),
                ],
                onChanged: (v) => setLocal(() => supplier = v!),
              ),
              DropdownButton<Product>(
                isExpanded: true,
                value: product,
                items: [
                  for (final p in products)
                    DropdownMenuItem(value: p, child: Text(p.nameZh)),
                ],
                onChanged: (v) => setLocal(() {
                  product = v!;
                  cost.text = centsToRm(product.costCents).toStringAsFixed(2);
                }),
              ),
              TextField(
                controller: qty,
                decoration: const InputDecoration(labelText: '数量'),
              ),
              TextField(
                controller: cost,
                decoration: const InputDecoration(
                  labelText: '成本 RM',
                  prefixText: 'RM ',
                ),
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
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.trim()) ?? 0;
    final unitCost = rmToCents(double.tryParse(cost.text.trim()) ?? 0);
    final total = (unitCost * q).round();
    await widget.repo.createPurchase(
      supplierId: supplier.id,
      supplierName: supplier.name,
      lines: [
        {
          'productId': product.id,
          'name': product.nameZh,
          'qty': q,
          'unitCostCents': unitCost,
          'subtotalCents': total,
        },
      ],
      totalCents: total,
      operator: widget.user.username,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('进货 / Purchases'),
        actions: [
          IconButton(
            onPressed: _chooseCreate,
            tooltip: '新增进货',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final row = _rows[i];
          return ListTile(
            title: Text('${row['purchase_no']} · ${row['supplier_name']}'),
            subtitle: Text(
              '${row['purchased_at']}'
              '${row['source'] == 'ocr' ? ' · OCR' : ''}'
              '${row['reversed'] == 1 ? ' · 已撤销' : ''}',
            ),
            trailing: MoneyText(
              amountCents: (row['total_cents'] as num).toInt(),
              fontSize: 14,
            ),
            onTap: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => PurchaseDetailScreen(
                    repo: widget.repo,
                    user: widget.user,
                    purchaseId: row['id'] as String,
                  ),
                ),
              );
              if (changed == true) await _load();
            },
          );
        },
      ),
    );
  }
}
