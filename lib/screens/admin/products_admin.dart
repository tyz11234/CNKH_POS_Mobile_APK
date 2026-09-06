import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../services/barcode_labels.dart';
import '../../services/pos_repository.dart';
import '../../services/product_images.dart';
import '../../theme/cnkh_theme.dart';
import '../../widgets/money_text.dart';

class ProductsAdminPage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const ProductsAdminPage({super.key, required this.repo, required this.user});
  @override
  State<ProductsAdminPage> createState() => _ProductsAdminPageState();
}

class _ProductsAdminPageState extends State<ProductsAdminPage> {
  List<Product> _items = [];
  final _q = TextEditingController();
  final _selected = <String>{};
  bool _selectMode = false;
  bool _imagesOn = false;
  bool _busy = false;
  late final BarcodeLabelService _labels = BarcodeLabelService(widget.repo);
  final _imgStore = ProductImageStore();

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(_load);
    widget.repo.productImagesEnabled().then((v) {
      if (mounted) setState(() => _imagesOn = v);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await widget.repo.searchProducts(_q.text, limit: 300);
    if (mounted) {
      setState(() {
        _items = list;
        _selected.removeWhere((id) => !_items.any((p) => p.id == id));
        if (_selected.isEmpty) _selectMode = false;
      });
    }
  }

  List<Product> get _selectedProducts =>
      _items.where((p) => _selected.contains(p.id)).toList();

  Future<void> _pickCategory(TextEditingController catCtrl) async {
    final cats = await widget.repo.listCategories();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '选择分类 / Pick category',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              title: const Text('（未分类 / None）'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            SizedBox(
              height: (cats.length * 56.0).clamp(56.0, 320.0),
              child: ListView.builder(
                itemCount: cats.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(cats[i].name),
                  onTap: () => Navigator.pop(ctx, cats[i].name),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '新分类请到「分类管理」添加\nNew categories only via Category Management',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) catCtrl.text = picked;
  }

  Future<void> _edit([Product? existing]) async {
    if (_busy) return;
    final nameZh = TextEditingController(text: existing?.nameZh ?? '');
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final sku = TextEditingController(text: existing?.sku ?? '');
    final barcode = TextEditingController(text: existing?.barcode ?? '');
    final price = TextEditingController(
      text: existing == null
          ? ''
          : centsToRm(existing.priceCents).toStringAsFixed(2),
    );
    final stock = TextEditingController(text: existing?.stock.toString() ?? '0');
    final unit = TextEditingController(text: existing?.unit ?? 'pcs');
    final cat = TextEditingController(text: existing?.category ?? '');
    final reorder = TextEditingController(
      text: existing == null ? '0' : existing.reorderLevel.toString(),
    );
    var imagePath = existing?.imagePath ?? '';
    var barcodeMode = existing == null
        ? 'auto'
        : (existing.barcode.trim().isEmpty ? 'auto' : 'manual');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? '新增商品' : '编辑商品'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameZh,
                  decoration: const InputDecoration(labelText: '中文名'),
                ),
                TextField(
                  controller: nameEn,
                  decoration: const InputDecoration(labelText: 'English'),
                ),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '条码 / Barcode',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('自动生成'),
                      selected: barcodeMode == 'auto',
                      onSelected: (_) => setLocal(() => barcodeMode = 'auto'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('手动输入'),
                      selected: barcodeMode == 'manual',
                      onSelected: (_) => setLocal(() => barcodeMode = 'manual'),
                    ),
                  ],
                ),
                if (barcodeMode == 'manual')
                  TextField(
                    controller: barcode,
                    decoration: const InputDecoration(labelText: 'Barcode / 条码'),
                  )
                else
                  Text(
                    existing?.barcode.trim().isNotEmpty == true
                        ? '将保留或保存时自动生成（若空）\nKeep existing, or auto-generate if empty'
                        : '保存时自动生成 EAN-13 条码 / Auto EAN-13 on save',
                    style: const TextStyle(fontSize: 12, color: CnkhColors.muted),
                  ),
                TextField(
                  controller: price,
                  decoration: const InputDecoration(
                    labelText: '售价 RM',
                    prefixText: 'RM ',
                  ),
                ),
                TextField(
                  controller: stock,
                  decoration: const InputDecoration(labelText: '库存'),
                ),
                TextField(
                  controller: reorder,
                  decoration: const InputDecoration(
                    labelText: '缺货阈值 / Reorder level',
                  ),
                ),
                TextField(
                  controller: unit,
                  decoration: const InputDecoration(labelText: '单位'),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    await _pickCategory(cat);
                    setLocal(() {});
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '分类（仅可选）/ Category picker',
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(cat.text.isEmpty ? '未分类 / None' : cat.text),
                  ),
                ),
                if (_imagesOn) ...[
                  const SizedBox(height: 10),
                  if (imagePath.isNotEmpty && File(imagePath).existsSync())
                    SizedBox(
                      height: 80,
                      child: Image.file(File(imagePath), fit: BoxFit.contain),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final f = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                      );
                      if (f == null) return;
                      final id = existing?.id ?? AppDatabase.newId();
                      final saved = await _imgStore.saveFromFile(id, f.path);
                      if (saved != null) setLocal(() => imagePath = saved);
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('选择商品图片 / Pick image'),
                  ),
                ],
              ],
            ),
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

    var code = barcode.text.trim();
    if (barcodeMode == 'auto' && code.isEmpty) {
      code = await _labels.autoGenerateBarcode();
    }

    final id = existing?.id ?? AppDatabase.newId();
    final p = Product(
      id: id,
      nameZh: nameZh.text.trim(),
      nameEn: nameEn.text.trim(),
      sku: sku.text.trim(),
      barcode: code,
      priceCents: rmToCents(double.tryParse(price.text.trim()) ?? 0),
      costCents: existing?.costCents ?? 0,
      stock: double.tryParse(stock.text.trim()) ?? 0,
      unit: unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
      category: cat.text.trim(),
      imagePath: imagePath,
      reorderLevel: double.tryParse(reorder.text.trim()) ?? 0,
    );
    await widget.repo.upsertProduct(p);
    await _load();
  }

  Future<bool> _confirmDeleteProducts(List<Product> products) async {
    if (products.isEmpty) return false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(products.length == 1 ? '确认删除商品？' : '确认批量删除商品？'),
            content: Text(
              products.length == 1
                  ? '确定删除「${products.single.nameZh}」吗？\n历史销售、进货、库存流水和收据仍会保留。'
                  : '确定删除所选的 ${products.length} 个商品吗？\n历史销售、进货、库存流水和收据仍会保留。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _productActions(Product p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑 / Edit'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('加入打印队列 / Add to print queue'),
              subtitle: const Text('PC「条码标签」页可批量打印'),
              onTap: () => Navigator.pop(ctx, 'queue'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('导出条码图片 / Export barcode image'),
              subtitle: const Text('条码 + 品名，可分享到相册/文件夹'),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: CnkhColors.danger),
              title: const Text('删除 / Delete'),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'edit') {
        await _edit(p);
      } else if (action == 'queue') {
        await _labels.enqueue(p);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入打印队列 / Queued for PC print')),
        );
      } else if (action == 'export') {
        final file = await _labels.exportPngFile(p);
        await _labels.shareFiles([file]);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${file.path.split('/').last}')),
        );
      } else if (action == 'del') {
        if (!await _confirmDeleteProducts([p])) return;
        await widget.repo.softDeleteProduct(p.id);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('商品已删除')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final products = _selectedProducts;
    if (_busy || products.isEmpty) return;
    if (!await _confirmDeleteProducts(products)) return;
    setState(() => _busy = true);
    var deleted = 0;
    try {
      for (final product in products) {
        await widget.repo.softDeleteProduct(product.id);
        deleted++;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deleted 个商品')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除 $deleted 项；其余失败：$e'),
            backgroundColor: CnkhColors.danger,
          ),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batchAction(String kind) async {
    final sel = _selectedProducts;
    if (sel.isEmpty || _busy) return;
    try {
      if (kind == 'queue') {
        await _labels.enqueueMany(sel);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入 ${sel.length} 项到打印队列')),
        );
      } else if (kind == 'export') {
        final files = await _labels.exportMany(sel);
        if (files.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('所选商品无条码 / No barcodes'),
              backgroundColor: CnkhColors.danger,
            ),
          );
          return;
        }
        await _labels.shareFiles(files);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${files.length} 张条码图（含品名）')),
        );
      }
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
        _selectMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((p) => p.id));
        _selectMode = _selected.isNotEmpty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selected.length}' : '商品 / Products'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: _selected.length == _items.length ? '取消全选' : '全选',
              onPressed: _busy ? null : _selectAll,
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              tooltip: '删除所选',
              onPressed: _busy || _selected.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: '取消多选',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _selected.clear();
                        _selectMode = false;
                      }),
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              tooltip: '多选',
              icon: const Icon(Icons.checklist),
              onPressed: _busy ? null : () => setState(() => _selectMode = true),
            ),
            IconButton(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _q,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索商品',
                  ),
                ),
              ),
              if (_selectMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _batchAction('queue'),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('批量入队打印'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: CnkhColors.navy,
                          ),
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _batchAction('export'),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('批量导出图片'),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final p = _items[i];
                    final sel = _selected.contains(p.id);
                    return ListTile(
                      leading: _selectMode
                          ? Checkbox(
                              value: sel,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                        if (v == true) {
                                          _selected.add(p.id);
                                        } else {
                                          _selected.remove(p.id);
                                          if (_selected.isEmpty) {
                                            _selectMode = false;
                                          }
                                        }
                                      }),
                            )
                          : (_imagesOn &&
                                  p.imagePath.isNotEmpty &&
                                  File(p.imagePath).existsSync())
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(p.imagePath),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : CircleAvatar(
                                  backgroundColor: CnkhColors.softBlue,
                                  child: Text(
                                    p.category.isEmpty
                                        ? '?'
                                        : p.category.substring(0, 1),
                                    style: const TextStyle(
                                      color: CnkhColors.navy,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                      title: Text(
                        p.nameZh,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${p.sku} · ${p.barcode}\n${p.category.isEmpty ? "未分类" : p.category} · 库存 ${p.stock} ${p.unit}',
                      ),
                      isThreeLine: true,
                      trailing: MoneyText(amountCents: p.priceCents, fontSize: 14),
                      selected: sel,
                      onTap: _busy
                          ? null
                          : () {
                              if (_selectMode) {
                                setState(() {
                                  if (sel) {
                                    _selected.remove(p.id);
                                    if (_selected.isEmpty) _selectMode = false;
                                  } else {
                                    _selected.add(p.id);
                                  }
                                });
                              } else {
                                _productActions(p);
                              }
                            },
                      onLongPress: _busy
                          ? null
                          : () => setState(() {
                                _selectMode = true;
                                _selected.add(p.id);
                              }),
                    );
                  },
                ),
              ),
            ],
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

class CategoriesAdminPage extends StatefulWidget {
  final PosRepository repo;
  const CategoriesAdminPage({super.key, required this.repo});
  @override
  State<CategoriesAdminPage> createState() => _CategoriesAdminPageState();
}

class _CategoriesAdminPageState extends State<CategoriesAdminPage> {
  List<Category> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.repo.listCategories();
    if (mounted) setState(() => _items = list);
  }

  Future<void> _addOrRename([Category? existing]) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '新增分类' : '重命名分类'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如 水管 / 紧固件'),
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
    );
    if (ok != true) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    try {
      if (existing == null) {
        await widget.repo.upsertCategory(Category(id: '', name: name));
      } else {
        await widget.repo.renameCategory(existing.id, name);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除分类？'),
        content: Text(
          '确定删除「${category.name}」吗？\n该分类下的商品不会被删除，只会改成未分类。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await widget.repo.deleteCategory(category.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除；$n 个商品改为未分类')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理 / Categories'),
        actions: [
          IconButton(onPressed: () => _addOrRename(), icon: const Icon(Icons.add)),
        ],
      ),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final c = _items[i];
          return ListTile(
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: Wrap(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _addOrRename(c),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: CnkhColors.danger),
                  onPressed: () => _deleteCategory(c),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BarcodeQueuePage extends StatefulWidget {
  final PosRepository repo;
  const BarcodeQueuePage({super.key, required this.repo});
  @override
  State<BarcodeQueuePage> createState() => _BarcodeQueuePageState();
}

class _BarcodeQueuePageState extends State<BarcodeQueuePage> {
  List<Map<String, Object?>> _rows = [];
  late final BarcodeLabelService _labels = BarcodeLabelService(widget.repo);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.repo.listBarcodeQueue();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _exportQueue() async {
    if (_busy) return;
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打印队列为空 / Queue empty')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final products = <Product>[];
      var missing = 0;
      for (final row in _rows) {
        final id = row['product_id'] as String?;
        if (id == null) {
          missing++;
          continue;
        }
        final product = await widget.repo.getProduct(id);
        if (product == null || product.isDeleted != 0) {
          missing++;
          continue;
        }
        if (product.barcode.trim().isEmpty) {
          missing++;
          continue;
        }
        products.add(product);
      }
      if (products.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('没有可导出的有效条码；跳过 $missing 项'),
            backgroundColor: CnkhColors.danger,
          ),
        );
        return;
      }
      final files = await _labels.exportMany(products);
      if (files.isEmpty) {
        throw StateError('条码图片生成失败，没有可分享文件');
      }
      await _labels.shareFiles(files);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing == 0
                ? '已生成 ${files.length} 张条码图'
                : '已生成 ${files.length} 张；跳过 $missing 项',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('条码打印队列 / Print queue'),
        actions: [
          IconButton(
            tooltip: '导出队列图片',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _busy ? null : _exportQueue,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('队列为空\n在商品页「加入打印队列」或批量入队'))
          : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                return ListTile(
                  title: Text(
                    '${r['product_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${r['barcode']} · ×${r['copies']} · ${r['status']}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy
                        ? null
                        : () async {
                            await widget.repo.removeBarcodeQueueItem(
                              r['id'] as String,
                            );
                            await _load();
                          },
                  ),
                );
              },
            ),
    );
  }
}
