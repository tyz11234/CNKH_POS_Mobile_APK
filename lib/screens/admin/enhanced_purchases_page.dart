import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../services/pos_repository.dart';
import '../../services/purchase_history_sync.dart';
import '../../services/purchase_invoice_parser.dart';
import '../../services/purchase_ocr_repository.dart';
import '../../widgets/money_text.dart';
import 'desktop_purchase_history_page.dart';
import 'purchase_ocr_screen.dart';
import 'supplier_aliases_page.dart';

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
  List<Map<String, Object?>> _drafts = [];
  String? _historySyncError;
  static const _pageSize = 50;
  int _historyPage = 0;
  bool _historyHasNext = false;
  static const _invoiceParser = PurchaseInvoiceParser();

  PurchaseOcrRepository get _ocrRepo => PurchaseOcrRepository(widget.repo);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool syncHistory = true}) async {
    String? syncError;
    if (syncHistory) {
      try {
        await PurchaseHistorySync(widget.repo).pullFromSavedDesktop();
      } catch (e) {
        syncError = '进货历史同步失败：$e';
      }
    }
    final rows = await widget.repo.listPurchases(
      limit: _pageSize + 1,
      offset: _historyPage * _pageSize,
    );
    _drafts = await _ocrRepo.listDrafts();
    if (!mounted) return;
    if (rows.isEmpty && _historyPage > 0) {
      _historyPage--;
      await _load(syncHistory: false);
      return;
    }
    setState(() {
      _rows = rows.take(_pageSize).toList(growable: false);
      _historyHasNext = rows.length > _pageSize;
      if (syncHistory || syncError != null) _historySyncError = syncError;
    });
  }

  Future<void> _changeHistoryPage(int delta) async {
    final next = _historyPage + delta;
    if (next < 0 || (delta > 0 && !_historyHasNext)) return;
    setState(() => _historyPage = next);
    await _load(syncHistory: false);
  }

  Future<void> _openAliases() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SupplierAliasesPage(repo: widget.repo),
      ),
    );
  }

  Future<void> _openDrafts() async {
    final drafts = await _ocrRepo.listDrafts();
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有未完成的 OCR 草稿')),
      );
      return;
    }
    final draftId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.55,
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  '未完成 OCR 草稿',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('点选后继续核对；草稿不会影响库存。'),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: drafts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = drafts[i];
                    final supplier = (d['supplier_name']?.toString() ?? '').trim();
                    final invoice = (d['invoice_no']?.toString() ?? '').trim();
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        supplier.isEmpty ? '未选择供应商' : supplier,
                      ),
                      subtitle: Text(
                        '${invoice.isEmpty ? '未识别 Invoice No' : invoice}\n${d['created_at'] ?? ''}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(ctx, d['id'] as String),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || draftId == null) return;
    final committed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseOcrScreen(
          repo: widget.repo,
          user: widget.user,
          draftId: draftId,
        ),
      ),
    );
    if (committed == true) await _load();
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
              title: Text(
                '新增进货 / New Purchase',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
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
            if (_drafts.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.drafts_outlined),
                title: Text('继续 OCR 草稿 (${_drafts.length})'),
                subtitle: const Text('继续之前未确认的进货单'),
                onTap: () => Navigator.pop(ctx, 'drafts'),
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
    if (action == 'drafts') {
      await _openDrafts();
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseOcrScreen(
          repo: widget.repo,
          user: widget.user,
          source:
              action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        ),
      ),
    );
    await _load();
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('进货列表已更新')),
      );
    }
  }

  Future<void> _createManual() async {
    const pageSize = 50;
    var supplierPage = 0;
    var productPage = 0;
    var supplierRows = await widget.repo.listSuppliers(limit: pageSize + 1);
    var productRows = await widget.repo.searchProducts('', limit: pageSize + 1);
    if (!mounted) return;
    if (supplierRows.isEmpty || productRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先建立至少一个供应商和商品')),
      );
      return;
    }
    var supplierHasNext = supplierRows.length > pageSize;
    var productHasNext = productRows.length > pageSize;
    supplierRows = supplierRows.take(pageSize).toList(growable: false);
    productRows = productRows.take(pageSize).toList(growable: false);
    var supplier = supplierRows.first;
    var product = productRows.first;
    final qty = TextEditingController(text: '0');
    final cost = TextEditingController(
      text: centsToRm(product.costCents).toStringAsFixed(2),
    );
    String? qtyError;
    String? costError;
    double? validQty;
    int? validUnitCost;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('简易进货 / Simple purchase'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<Supplier>(
                  isExpanded: true,
                  value: supplierRows.any((s) => s.id == supplier.id)
                      ? supplier
                      : null,
                  hint: Text('已选：${supplier.name}（其他页）'),
                  items: [
                    for (final s in supplierRows)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => supplier = v);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: supplierPage == 0
                          ? null
                          : () async {
                              final next = supplierPage - 1;
                              final rows = await widget.repo.listSuppliers(
                                limit: pageSize + 1,
                                offset: next * pageSize,
                              );
                              if (!ctx.mounted) return;
                              setLocal(() {
                                supplierPage = next;
                                supplierHasNext = rows.length > pageSize;
                                supplierRows = rows.take(pageSize).toList();
                              });
                            },
                      child: const Text('上一页'),
                    ),
                    Text('供应商 第 ${supplierPage + 1} 页'),
                    TextButton(
                      onPressed: !supplierHasNext
                          ? null
                          : () async {
                              final next = supplierPage + 1;
                              final rows = await widget.repo.listSuppliers(
                                limit: pageSize + 1,
                                offset: next * pageSize,
                              );
                              if (!ctx.mounted || rows.isEmpty) return;
                              setLocal(() {
                                supplierPage = next;
                                supplierHasNext = rows.length > pageSize;
                                supplierRows = rows.take(pageSize).toList();
                              });
                            },
                      child: const Text('下一页'),
                    ),
                  ],
                ),
                DropdownButton<Product>(
                  isExpanded: true,
                  value: productRows.any((p) => p.id == product.id)
                      ? product
                      : null,
                  hint: Text('已选：${product.nameZh}（其他页）'),
                  items: [
                    for (final p in productRows)
                      DropdownMenuItem(value: p, child: Text(p.nameZh)),
                  ],
                  onChanged: (v) => setLocal(() {
                    if (v == null) return;
                    product = v;
                    cost.text = centsToRm(product.costCents).toStringAsFixed(2);
                    costError = null;
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: productPage == 0
                          ? null
                          : () async {
                              final next = productPage - 1;
                              final rows = await widget.repo.searchProducts(
                                '',
                                limit: pageSize + 1,
                                offset: next * pageSize,
                              );
                              if (!ctx.mounted) return;
                              setLocal(() {
                                productPage = next;
                                productHasNext = rows.length > pageSize;
                                productRows = rows.take(pageSize).toList();
                              });
                            },
                      child: const Text('上一页'),
                    ),
                    Text('商品 第 ${productPage + 1} 页'),
                    TextButton(
                      onPressed: !productHasNext
                          ? null
                          : () async {
                              final next = productPage + 1;
                              final rows = await widget.repo.searchProducts(
                                '',
                                limit: pageSize + 1,
                                offset: next * pageSize,
                              );
                              if (!ctx.mounted || rows.isEmpty) return;
                              setLocal(() {
                                productPage = next;
                                productHasNext = rows.length > pageSize;
                                productRows = rows.take(pageSize).toList();
                              });
                            },
                      child: const Text('下一页'),
                    ),
                  ],
                ),
                TextField(
                  controller: qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (qtyError != null) setLocal(() => qtyError = null);
                  },
                  decoration: InputDecoration(
                    labelText: '数量',
                    errorText: qtyError,
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
                    labelText: '成本 RM',
                    prefixText: 'RM ',
                    errorText: costError,
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
                final q = double.tryParse(
                  qty.text.trim().replaceAll(',', '.'),
                );
                final unitCost = _invoiceParser.parseMoneyCents(cost.text);
                var invalid = false;
                if (q == null || !q.isFinite || q <= 0) {
                  qtyError = '数量必须是大于 0 的有效数字';
                  invalid = true;
                }
                if (unitCost == null || unitCost < 0) {
                  costError = '请输入有效金额，例如 12.50 或 1,234.56';
                  invalid = true;
                }
                if (invalid) {
                  setLocal(() {});
                  return;
                }
                validQty = q;
                validUnitCost = unitCost;
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      qty.dispose();
      cost.dispose();
      return;
    }
    final q = validQty!;
    final unitCost = validUnitCost!;
    final total = (unitCost * q).round();
    qty.dispose();
    cost.dispose();

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
    _historyPage = 0;
    await _load();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('进货 / Purchases'),
        actions: [
          IconButton(
            onPressed: _openAliases,
            tooltip: '供应商商品记忆 / Aliases',
            icon: const Icon(Icons.memory_outlined),
          ),
          if (_drafts.isNotEmpty)
            IconButton(
              onPressed: _openDrafts,
              tooltip: 'OCR 草稿 (${_drafts.length})',
              icon: Badge(
                label: Text('${_drafts.length}'),
                child: const Icon(Icons.drafts_outlined),
              ),
            ),
          IconButton(
            onPressed: _chooseCreate,
            tooltip: '新增进货',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _historyPage == 0 ? null : () => _changeHistoryPage(-1),
                child: const Text('上一页'),
              ),
              Expanded(child: Center(child: Text('第 ${_historyPage + 1} 页'))),
              OutlinedButton(
                onPressed: !_historyHasNext ? null : () => _changeHistoryPage(1),
                child: const Text('下一页'),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_historySyncError != null)
            Material(
              color: const Color(0xFFFFECEC),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.sync_problem),
                title: Text(_historySyncError!),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('重试'),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  final desktopHistory = row['source'] == 'desktop_sync';
                  return ListTile(
                    title: Text('${row['purchase_no']} · ${row['supplier_name']}'),
                    subtitle: Text(
                      '${row['purchased_at']}'
                      '${row['source'] == 'ocr' ? ' · OCR' : ''}'
                      '${desktopHistory ? ' · Desktop' : ''}'
                      '${row['reversed'] == 1 ? ' · 已撤销' : ''}',
                    ),
                    trailing: MoneyText(
                      amountCents: (row['total_cents'] as num).toInt(),
                      fontSize: 14,
                    ),
                    onTap: () async {
                      if (desktopHistory) {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => DesktopPurchaseHistoryPage(
                              purchase: row,
                            ),
                          ),
                        );
                        return;
                      }
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
            ),
          ),
        ],
      ),
    );
  }
}
