import 'dart:io';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/money_text.dart';
import 'barcode_scan_screen.dart';
import '../services/lan_sync.dart';

class CartScreen extends StatefulWidget {
  final CartState cart;
  final AppUser user;
  final PosRepository repo;
  final VoidCallback onChanged;
  final VoidCallback onCheckout;
  final Future<void> Function() onHold;
  final Future<void> Function() onResume;
  final void Function(LanSyncConfig config)? onPairing;

  const CartScreen({
    super.key,
    required this.cart,
    required this.user,
    required this.repo,
    required this.onChanged,
    required this.onCheckout,
    required this.onHold,
    required this.onResume,
    this.onPairing,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _search = TextEditingController();
  List<Product> _results = [];
  List<Category> _categories = [];
  String _category = ''; // empty = 全部
  bool _loading = true;
  bool _imagesOn = false;

  @override
  void initState() {
    super.initState();
    _reload('');
    _search.addListener(() => _reload(_search.text));
    widget.repo.listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    });
    widget.repo.productImagesEnabled().then((v) {
      if (mounted) setState(() => _imagesOn = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload(String q) async {
    final list = await widget.repo.searchProducts(
      q,
      category: _category.isEmpty ? null : _category,
    );
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  Future<bool> _add(Product p, {int addQty = 1}) async {
    final existing = widget.cart.find(p.id);
    final nextQty = (existing?.qty ?? 0) + addQty;
    final stock = p.stock;
    if (nextQty > stock) {
      final policy = await widget.repo.stockPolicy();
      if (!mounted) return false;
      if (policy == 'block') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('库存不足 / Insufficient stock (有 $stock)'),
            backgroundColor: CnkhColors.danger,
          ),
        );
        return false;
      }
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('库存不足 / Low stock'),
          content: Text('${p.nameZh}\n需要 $nextQty · 库存 $stock\n仍要加购？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
          ],
        ),
      );
      if (cont != true) return false;
    }
    if (existing != null) {
      existing.qty += addQty;
      existing.discountCents =
          clampDiscountCents(existing.discountCents, existing.grossCents);
    } else {
      widget.cart.items.add(CartItem(product: p, qty: addQty));
    }
    widget.onChanged();
    return true;
  }

  void _adjust(CartItem item, int delta) {
    item.qty += delta;
    if (item.qty <= 0) {
      widget.cart.items.remove(item);
    } else {
      item.discountCents =
          clampDiscountCents(item.discountCents, item.grossCents);
    }
    widget.onChanged();
  }

  void _remove(CartItem item) {
    widget.cart.items.remove(item);
    widget.onChanged();
  }

  Future<void> _editLineDiscount(CartItem item) async {
    if (!widget.user.canDiscount) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('行折扣 / Line discount'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'rm'),
            child: const Text('金额 RM'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'pct'),
            child: const Text('百分比 %'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: const Text('清除折扣 / Clear'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == 'clear') {
      item.discountCents = 0;
      widget.onChanged();
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mode == 'rm' ? '折扣 RM' : '折扣 %'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: mode == 'rm' ? 'RM ' : '',
            suffixText: mode == 'pct' ? '%' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = double.tryParse(ctrl.text.trim()) ?? 0;
    final oldDisc = item.discountCents;
    if (mode == 'rm') {
      item.discountCents = clampDiscountCents(rmToCents(v), item.grossCents);
    } else {
      item.discountCents = percentDiscountCents(item.grossCents, v);
    }
    await widget.repo.logAudit(
      username: widget.user.username,
      role: widget.user.isAdmin ? 'ADMIN' : 'STAFF',
      action: 'line_discount',
      productId: item.product.id,
      productName: item.product.nameZh,
      context: 'cart',
      oldValue: '$oldDisc',
      newValue: '${item.discountCents}',
      reason: mode,
    );
    widget.onChanged();
  }

  Future<void> _editOrderDiscount() async {
    if (!widget.user.canDiscount) return;
    final ctrl = TextEditingController(
      text: centsToRm(widget.cart.orderDiscountCents).toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('整单折扣 RM / Order discount'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: 'RM '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final oldOrder = widget.cart.orderDiscountCents;
    widget.cart.orderDiscountCents =
        rmToCents(double.tryParse(ctrl.text.trim()) ?? 0);
    await widget.repo.logAudit(
      username: widget.user.username,
      role: widget.user.isAdmin ? 'ADMIN' : 'STAFF',
      action: 'order_discount',
      context: 'cart',
      oldValue: '$oldOrder',
      newValue: '${widget.cart.orderDiscountCents}',
    );
    widget.onChanged();
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BarcodeScanScreen(
          repo: widget.repo,
          onProduct: (p) async {
            await _add(p);
            if (mounted) setState(() {});
          },
          onPairing: widget.onPairing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final due = cart.payableCents(isCredit: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripH = constraints.maxHeight < 560 ? 72.0 : 120.0;
        return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('收银台 / POS', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: '搜索 名称 / SKU / 条码',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('全部'),
                        selected: _category.isEmpty,
                        onSelected: (_) {
                          setState(() => _category = '');
                          _reload(_search.text);
                        },
                      ),
                    ),
                    for (final c in _categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(c.name),
                          selected: _category == c.name,
                          onSelected: (_) {
                            setState(() => _category = c.name);
                            _reload(_search.text);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CnkhColors.navy,
                  ),
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码加购 / Scan barcode',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: cart.items.isEmpty ? null : widget.onHold,
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: const Text('挂单'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: widget.onResume,
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('取单'),
                    ),
                  ),
                  TextButton(
                    onPressed: cart.items.isEmpty
                        ? null
                        : () {
                            cart.items.clear();
                            cart.orderDiscountCents = 0;
                            widget.onChanged();
                          },
                    child: const Text('清空'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: stripH,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _results.length.clamp(0, 40),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = _results[i];
                    return _ProductChip(product: p, showImage: _imagesOn, onTap: () { _add(p); });
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('购物车 (${cart.itemCount})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: cart.items.isEmpty ? null : _editOrderDiscount,
                child: Text(
                  cart.orderDiscountApplied > 0
                      ? '整单折扣 −${formatRm(cart.orderDiscountApplied)}'
                      : '整单折扣',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: cart.items.isEmpty
              ? const Center(
                  child: Text('购物车为空\n搜索并点选商品',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: CnkhColors.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = cart.items[i];
                    return _CartTile(
                      item: item,
                      onMinus: () => _adjust(item, -1),
                      onPlus: () => _adjust(item, 1),
                      onRemove: () => _remove(item),
                      onDiscount: () => _editLineDiscount(item),
                    );
                  },
                ),
        ),
        Material(
          elevation: 8,
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '合计 / Total · ${cart.itemCount} 件',
                          style: const TextStyle(
                              color: CnkhColors.muted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MoneyText(
                              amountCents: due, fontSize: 26, hero: true),
                        ),
                        if (cart.itemDiscountsCents + cart.orderDiscountApplied > 0)
                          Text(
                            '折扣 −${formatRm(cart.itemDiscountsCents + cart.orderDiscountApplied)}',
                            style: const TextStyle(
                              color: CnkhColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: CnkhColors.success,
                          disabledBackgroundColor: CnkhColors.border,
                        ),
                        onPressed:
                            cart.items.isEmpty ? null : widget.onCheckout,
                        child: const Text('结账\nCheckout',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                height: 1.15, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
      },
    );
  }
}

class _ProductChip extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final bool showImage;
  const _ProductChip({required this.product, required this.onTap, this.showImage = false});
  @override
  Widget build(BuildContext context) {
    final hasImg = showImage &&
        product.imagePath.isNotEmpty &&
        File(product.imagePath).existsSync();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CnkhColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImg)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(product.imagePath),
                      height: 36, width: double.infinity, fit: BoxFit.cover),
                ),
              Text(product.nameZh,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(product.sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CnkhColors.muted, fontSize: 11)),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                      child: MoneyText(
                          amountCents: product.priceCents, fontSize: 14)),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: CnkhColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;
  final VoidCallback onDiscount;

  const _CartTile({
    required this.item,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
    required this.onDiscount,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.product.nameZh,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    item.lineDiscountCents > 0
                        ? '${formatRm(item.grossCents)} → ${formatRm(item.lineTotalCents)} (−${formatRm(item.lineDiscountCents)})'
                        : formatRm(item.lineTotalCents),
                    style: const TextStyle(fontSize: 13),
                  ),
                  TextButton(
                    onPressed: onDiscount,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('行折扣 / Discount',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline, color: CnkhColors.danger)),
            _QtyBtn(icon: Icons.remove, onTap: onMinus),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${item.qty}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            _QtyBtn(icon: Icons.add, onTap: onPlus),
          ],
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: CnkhColors.softBlue,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
            width: 40, height: 40, child: Icon(icon, color: CnkhColors.navy)),
      ),
    );
  }
}
