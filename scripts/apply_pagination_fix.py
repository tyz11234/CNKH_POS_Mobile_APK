from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    if old not in text:
        raise RuntimeError(f'missing pattern: {label}')
    return text.replace(old, new, 1)


def replace_regex(text, pattern, repl, label):
    out, n = re.subn(pattern, repl, text, count=1, flags=re.S)
    if n != 1:
        raise RuntimeError(f'pattern count {n}: {label}')
    return out


# Repository: real database paging with stable ordering. Existing call sites remain compatible.
p = 'lib/services/pos_repository.dart'
t = read(p)
new_search = r'''  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async {
    final d = await _db.db;
    final q = query.trim();
    final cat = (category ?? '').trim();
    final catClause = cat.isEmpty ? '' : ' AND category=?';
    final catArgs = cat.isEmpty ? <Object?>[] : <Object?>[cat];
    if (q.isEmpty) {
      final rows = await d.query(
        'products',
        where: 'is_deleted=0$catClause',
        whereArgs: catArgs.isEmpty ? null : catArgs,
        orderBy: 'category COLLATE NOCASE, name_zh COLLATE NOCASE, id',
        limit: limit,
        offset: offset,
      );
      return rows.map(Product.fromMap).toList();
    }
    final like = '%$q%';
    final rows = await d.query(
      'products',
      where:
          'is_deleted=0 AND (name_zh LIKE ? OR name_en LIKE ? OR sku LIKE ? OR barcode LIKE ? OR category LIKE ?)$catClause',
      whereArgs: [like, like, like, like, like, ...catArgs],
      orderBy: 'name_zh COLLATE NOCASE, id',
      limit: limit,
      offset: offset,
    );
    // Keep the original exact-barcode preference inside each stable page.
    rows.sort((a, b) {
      final ab = (a['barcode'] as String?) ?? '';
      final bb = (b['barcode'] as String?) ?? '';
      if (ab == q && bb != q) return -1;
      if (bb == q && ab != q) return 1;
      final an = ((a['name_zh'] as String?) ?? '').toLowerCase();
      final bn = ((b['name_zh'] as String?) ?? '').toLowerCase();
      final byName = an.compareTo(bn);
      if (byName != 0) return byName;
      return (a['id'] as String).compareTo(b['id'] as String);
    });
    return rows.map(Product.fromMap).toList();
  }

  Future<int> countProducts(String query, {String? category}) async {
    final d = await _db.db;
    final q = query.trim();
    final cat = (category ?? '').trim();
    final where = <String>['is_deleted=0'];
    final args = <Object?>[];
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add(
        '(name_zh LIKE ? OR name_en LIKE ? OR sku LIKE ? OR barcode LIKE ? OR category LIKE ?)',
      );
      args.addAll([like, like, like, like, like]);
    }
    if (cat.isNotEmpty) {
      where.add('category=?');
      args.add(cat);
    }
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM products WHERE ${where.join(' AND ')}',
      args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
'''
t = replace_regex(t, r"  Future<List<Product>> searchProducts\([\s\S]*?\n  Future<Product\?> findByBarcodeOrSku", new_search + "\n  Future<Product?> findByBarcodeOrSku", 'searchProducts')

new_customers = r'''  Future<List<Customer>> listCustomers({
    int? limit,
    int offset = 0,
    String query = '',
  }) async {
    final d = await _db.db;
    final q = query.trim();
    final like = '%$q%';
    final rows = await d.query(
      'customers',
      where: q.isEmpty
          ? 'is_deleted=0'
          : 'is_deleted=0 AND (name LIKE ? OR phone LIKE ? OR notes LIKE ?)',
      whereArgs: q.isEmpty ? null : [like, like, like],
      orderBy: 'name COLLATE NOCASE, id',
      limit: limit,
      offset: limit == null ? null : offset,
    );
    return rows.map(Customer.fromMap).toList();
  }
'''
t = replace_regex(t, r"  Future<List<Customer>> listCustomers\(\) async \{[\s\S]*?\n  Future<void> _saveEntity", new_customers + "\n  Future<void> _saveEntity", 'listCustomers')

old_suppliers = """  Future<List<Supplier>> listSuppliers() async => (await (await _db.db).query(\n    'suppliers',\n    where: 'is_deleted=0',\n    orderBy: 'name COLLATE NOCASE',\n  )).map(Supplier.fromMap).toList();\n"""
new_suppliers = r'''  Future<List<Supplier>> listSuppliers({
    int? limit,
    int offset = 0,
    String query = '',
  }) async {
    final d = await _db.db;
    final q = query.trim();
    final like = '%$q%';
    final rows = await d.query(
      'suppliers',
      where: q.isEmpty
          ? 'is_deleted=0'
          : 'is_deleted=0 AND (name LIKE ? OR phone LIKE ? OR email LIKE ? OR notes LIKE ?)',
      whereArgs: q.isEmpty ? null : [like, like, like, like],
      orderBy: 'name COLLATE NOCASE, id',
      limit: limit,
      offset: limit == null ? null : offset,
    );
    return rows.map(Supplier.fromMap).toList();
  }
'''
t = replace_once(t, old_suppliers, new_suppliers, 'listSuppliers')

old_sales_all = """  Future<List<SaleRecord>> salesAll({int? limit}) async {\n    final d = await _db.db;\n    final rows = await d.query('sales', orderBy: 'sold_at DESC', limit: limit);\n    return rows.map(SaleRecord.fromMap).toList();\n  }\n"""
new_sales_all = r'''  Future<List<SaleRecord>> salesAll({int? limit, int offset = 0}) async {
    final d = await _db.db;
    final rows = await d.query(
      'sales',
      orderBy: 'sold_at DESC, id DESC',
      limit: limit,
      offset: limit == null ? null : offset,
    );
    return rows.map(SaleRecord.fromMap).toList();
  }

  Future<List<SaleRecord>> salesPage({
    bool todayOnly = false,
    String query = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final d = await _db.db;
    final where = <String>[];
    final args = <Object?>[];
    if (todayOnly) {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      where.add('sold_at LIKE ?');
      args.add('$day%');
      // Preserve the old Today behavior: voided sales are excluded.
      where.add('voided=0');
    }
    if (from != null) {
      where.add('substr(sold_at,1,10) >= ?');
      args.add(from.toIso8601String().substring(0, 10));
    }
    if (to != null) {
      where.add('substr(sold_at,1,10) <= ?');
      args.add(to.toIso8601String().substring(0, 10));
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add(
        '(receipt_no LIKE ? OR customer_phone LIKE ? OR customer_name LIKE ? OR payment_method LIKE ?)',
      );
      args.addAll([like, like, like, like]);
    }
    final rows = await d.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'sold_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(SaleRecord.fromMap).toList();
  }
'''
t = replace_once(t, old_sales_all, new_sales_all, 'salesAll')

old_purchases = """  Future<List<Map<String, Object?>>> listPurchases() async {\n    final d = await _db.db;\n    return d.query('purchases', orderBy: 'purchased_at DESC');\n  }\n"""
new_purchases = r'''  Future<List<Map<String, Object?>>> listPurchases({
    int? limit,
    int offset = 0,
  }) async {
    final d = await _db.db;
    return d.query(
      'purchases',
      orderBy: 'purchased_at DESC, id DESC',
      limit: limit,
      offset: limit == null ? null : offset,
    );
  }
'''
t = replace_once(t, old_purchases, new_purchases, 'listPurchases')

old_closings = """  Future<List<Map<String, Object?>>> listClosings() async {\n    final d = await _db.db;\n    return d.query('daily_closings', orderBy: 'business_date DESC');\n  }\n"""
new_closings = r'''  Future<List<Map<String, Object?>>> listClosings({
    int? limit,
    int offset = 0,
  }) async {
    final d = await _db.db;
    return d.query(
      'daily_closings',
      orderBy: 'business_date DESC, closed_at DESC, id DESC',
      limit: limit,
      offset: limit == null ? null : offset,
    );
  }
'''
t = replace_once(t, old_closings, new_closings, 'listClosings')

t = replace_once(t, "    int limit = 200,\n  }) async {\n    final d = await _db.db;", "    int limit = 200,\n    int offset = 0,\n  }) async {\n    final d = await _db.db;", 'listAudit offset signature')
t = replace_once(t, "      orderBy: 'occurred_at DESC',\n      limit: limit,\n    );", "      orderBy: 'occurred_at DESC, id DESC',\n      limit: limit,\n      offset: offset,\n    );", 'listAudit offset query')
write(p, t)

# Cashier product strip: 40 per page, complete search/category paging, stale-request protection.
p = 'lib/screens/cart_screen.dart'
t = read(p)
t = replace_once(t, "  bool _imagesOn = false;\n", "  bool _imagesOn = false;\n  static const _productPageSize = 40;\n  int _productPage = 0;\n  bool _productHasNext = false;\n  int _productRequest = 0;\n", 'cart fields')
t = replace_once(t, "    _search.addListener(() => _reload(_search.text));", "    _search.addListener(_onSearchChanged);", 'cart search listener')
t = replace_once(t, "  void dispose() {\n    _search.dispose();", "  void dispose() {\n    _search.removeListener(_onSearchChanged);\n    _search.dispose();", 'cart dispose')
new_reload = r'''  void _onSearchChanged() {
    _productPage = 0;
    _reload(_search.text);
  }

  Future<void> _reload(String q) async {
    final request = ++_productRequest;
    if (mounted) setState(() => _loading = true);
    final list = await widget.repo.searchProducts(
      q,
      limit: _productPageSize + 1,
      offset: _productPage * _productPageSize,
      category: _category.isEmpty ? null : _category,
    );
    if (!mounted || request != _productRequest) return;
    if (list.isEmpty && _productPage > 0) {
      _productPage--;
      await _reload(q);
      return;
    }
    setState(() {
      _productHasNext = list.length > _productPageSize;
      _results = list.take(_productPageSize).toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _changeProductPage(int delta) async {
    final next = _productPage + delta;
    if (next < 0 || (delta > 0 && !_productHasNext)) return;
    setState(() => _productPage = next);
    await _reload(_search.text);
  }
'''
t = replace_regex(t, r"  Future<void> _reload\(String q\) async \{[\s\S]*?\n  Future<bool> _add", new_reload + "\n  Future<bool> _add", 'cart reload')
t = replace_once(t, "                          setState(() => _category = '');\n                          _reload(_search.text);", "                          setState(() {\n                            _category = '';\n                            _productPage = 0;\n                          });\n                          _reload(_search.text);", 'cart all category')
t = replace_once(t, "                            setState(() => _category = c.name);\n                            _reload(_search.text);", "                            setState(() {\n                              _category = c.name;\n                              _productPage = 0;\n                            });\n                            _reload(_search.text);", 'cart category')
t = replace_once(t, "                  itemCount: _results.length.clamp(0, 40),", "                  itemCount: _results.length,", 'cart item count')
marker = """        Padding(\n          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),\n          child: Row(\n            children: [\n              Text('购物车 (${cart.itemCount})',"""
pager = """        SizedBox(\n          height: 40,\n          child: Row(\n            mainAxisAlignment: MainAxisAlignment.center,\n            children: [\n              TextButton(\n                onPressed: _loading || _productPage == 0\n                    ? null\n                    : () => _changeProductPage(-1),\n                child: const Text('上一页'),\n              ),\n              Padding(\n                padding: const EdgeInsets.symmetric(horizontal: 12),\n                child: Text('第 ${_productPage + 1} 页'),\n              ),\n              TextButton(\n                onPressed: _loading || !_productHasNext\n                    ? null\n                    : () => _changeProductPage(1),\n                child: const Text('下一页'),\n              ),\n            ],\n          ),\n        ),\n        Padding(\n          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),\n          child: Row(\n            children: [\n              Text('购物车 (${cart.itemCount})',"""
t = replace_once(t, marker, pager, 'cart pager')
write(p, t)

# Customer/supplier management: 50 per page, database-backed.
p = 'lib/screens/admin/entities_page.dart'
t = read(p)
t = replace_once(t, "  bool _busy = false;\n", "  bool _busy = false;\n  static const _pageSize = 50;\n  int _page = 0;\n  bool _hasNext = false;\n  int _loadVersion = 0;\n", 'entities fields')
new_load = r'''  Future<void> _load() async {
    final version = ++_loadVersion;
    final items = _isCustomers
        ? await widget.repo.listCustomers(
            limit: _pageSize + 1,
            offset: _page * _pageSize,
          )
        : await widget.repo.listSuppliers(
            limit: _pageSize + 1,
            offset: _page * _pageSize,
          );
    if (!mounted || version != _loadVersion) return;
    if (items.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _hasNext = items.length > _pageSize;
      _items = items.take(_pageSize).cast<Object>().toList(growable: false);
      _selected.removeWhere(
        (id) => !_items.any((item) => _idOf(item) == id),
      );
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext) || _busy) return;
    setState(() {
      _page = next;
      _selected.clear();
      _selectMode = false;
    });
    await _load();
  }
'''
t = replace_regex(t, r"  Future<void> _load\(\) async \{[\s\S]*?\n  Future<void> _edit", new_load + "\n  Future<void> _edit", 'entities load')
t = replace_once(t, "      body: Stack(\n", "      bottomNavigationBar: SafeArea(\n        top: false,\n        child: Padding(\n          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),\n          child: Row(\n            children: [\n              OutlinedButton(\n                onPressed: _page == 0 || _busy ? null : () => _changePage(-1),\n                child: const Text('上一页'),\n              ),\n              Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),\n              OutlinedButton(\n                onPressed: !_hasNext || _busy ? null : () => _changePage(1),\n                child: const Text('下一页'),\n              ),\n            ],\n          ),\n        ),\n      ),\n      body: Stack(\n", 'entities pager')
write(p, t)

# Product management: 50 per page; remove the hidden 300-row ceiling.
p = 'lib/screens/admin/products_admin.dart'
t = read(p)
t = replace_once(t, "  bool _busy = false;\n", "  bool _busy = false;\n  static const _pageSize = 50;\n  int _page = 0;\n  bool _hasNext = false;\n  int _loadVersion = 0;\n", 'products fields')
t = replace_once(t, "    _q.addListener(_load);", "    _q.addListener(_onQueryChanged);", 'products listener')
t = replace_once(t, "  void dispose() {\n    _q.dispose();", "  void dispose() {\n    _q.removeListener(_onQueryChanged);\n    _q.dispose();", 'products dispose')
new_products_load = r'''  void _onQueryChanged() {
    _page = 0;
    _selected.clear();
    _selectMode = false;
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final list = await widget.repo.searchProducts(
      _q.text,
      limit: _pageSize + 1,
      offset: _page * _pageSize,
    );
    if (!mounted || version != _loadVersion) return;
    if (list.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _hasNext = list.length > _pageSize;
      _items = list.take(_pageSize).toList(growable: false);
      _selected.removeWhere((id) => !_items.any((p) => p.id == id));
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext) || _busy) return;
    setState(() {
      _page = next;
      _selected.clear();
      _selectMode = false;
    });
    await _load();
  }
'''
t = replace_regex(t, r"  Future<void> _load\(\) async \{[\s\S]*?\n  List<Product> get _selectedProducts", new_products_load + "\n  List<Product> get _selectedProducts", 'products load')
t = replace_once(t, "      body: Stack(\n", "      bottomNavigationBar: SafeArea(\n        top: false,\n        child: Padding(\n          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),\n          child: Row(\n            children: [\n              OutlinedButton(\n                onPressed: _page == 0 || _busy ? null : () => _changePage(-1),\n                child: const Text('上一页'),\n              ),\n              Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),\n              OutlinedButton(\n                onPressed: !_hasNext || _busy ? null : () => _changePage(1),\n                child: const Text('下一页'),\n              ),\n            ],\n          ),\n        ),\n      ),\n      body: Stack(\n", 'products pager')
write(p, t)

# Enhanced purchases: 50 history rows/page + 50-row supplier/product selectors + qty default 0.
p = 'lib/screens/admin/enhanced_purchases_page.dart'
t = read(p)
t = replace_once(t, "  String? _historySyncError;\n", "  String? _historySyncError;\n  static const _pageSize = 50;\n  int _historyPage = 0;\n  bool _historyHasNext = false;\n", 'purchase fields')
new_purchase_load = r'''  Future<void> _load({bool syncHistory = true}) async {
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
'''
t = replace_regex(t, r"  Future<void> _load\(\) async \{[\s\S]*?\n  Future<void> _openAliases", new_purchase_load + "\n  Future<void> _openAliases", 'purchase load')
new_manual = r'''  Future<void> _createManual() async {
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
'''
t = replace_regex(t, r"  Future<void> _createManual\(\) async \{[\s\S]*?\n  @override\n  Widget build", new_manual + "\n\n  @override\n  Widget build", 'manual purchase')
t = replace_once(t, "      body: Column(\n", "      bottomNavigationBar: SafeArea(\n        top: false,\n        child: Padding(\n          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),\n          child: Row(\n            children: [\n              OutlinedButton(\n                onPressed: _historyPage == 0 ? null : () => _changeHistoryPage(-1),\n                child: const Text('上一页'),\n              ),\n              Expanded(child: Center(child: Text('第 ${_historyPage + 1} 页'))),\n              OutlinedButton(\n                onPressed: !_historyHasNext ? null : () => _changeHistoryPage(1),\n                child: const Text('下一页'),\n              ),\n            ],\n          ),\n        ),\n      ),\n      body: Column(\n", 'purchase history pager')
write(p, t)

# Sales history: SQL-backed filters across all records, 50 per page.
p = 'lib/screens/sales_list_screen.dart'
t = read(p)
t = replace_once(t, "  List<SaleRecord> _filtered = [];\n  bool _loading = true;", "  List<SaleRecord> _filtered = [];\n  bool _loading = true;\n  static const _pageSize = 50;\n  int _page = 0;\n  bool _hasNext = false;\n  int _loadVersion = 0;", 'sales fields')
new_sales_load = r'''  Future<void> _load() async {
    final version = ++_loadVersion;
    if (mounted) setState(() => _loading = true);
    final list = await widget.repo.salesPage(
      todayOnly: widget.todayOnly,
      query: _q.text,
      from: _from,
      to: _to,
      limit: _pageSize + 1,
      offset: _page * _pageSize,
    );
    if (!mounted || version != _loadVersion) return;
    if (list.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _sales = list.take(_pageSize).toList(growable: false);
      _filtered = _sales;
      _hasNext = list.length > _pageSize;
      _loading = false;
    });
  }

  void _applyFilter() {
    _page = 0;
    _load();
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext)) return;
    setState(() => _page = next);
    await _load();
  }
'''
t = replace_regex(t, r"  Future<void> _load\(\) async \{[\s\S]*?\n  bool _match", new_sales_load + "\n  bool _match", 'sales load')
# Date/search filters now reload the whole matching dataset, so _match is retained only as harmless legacy code.
# Insert page controls before the closing of the main Column.
old_sales_tail = """        Expanded(\n          child: RefreshIndicator("""
# no-op marker assertion keeps the patch tied to the expected screen
if old_sales_tail not in t:
    raise RuntimeError('missing sales list body')
# Add pager after the Expanded block by targeting the exact end before the Column children close.
needle = """          ),\n        ),\n      ],\n    );\n    if (!widget.asRoute) return body;"""
replacement = """          ),\n        ),\n        SafeArea(\n          top: false,\n          child: Padding(\n            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),\n            child: Row(\n              children: [\n                OutlinedButton(\n                  onPressed: _page == 0 || _loading ? null : () => _changePage(-1),\n                  child: const Text('上一页'),\n                ),\n                Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),\n                OutlinedButton(\n                  onPressed: !_hasNext || _loading ? null : () => _changePage(1),\n                  child: const Text('下一页'),\n                ),\n              ],\n            ),\n          ),\n        ),\n      ],\n    );\n    if (!widget.asRoute) return body;"""
t = replace_once(t, needle, replacement, 'sales pager')
write(p, t)

# Legacy-routed admin pages still active: stocktake, daily-close history and audit log.
p = 'lib/screens/admin/admin_hub_legacy.dart'
t = read(p)
new_stocktake = r'''class StocktakePage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const StocktakePage({super.key, required this.repo, required this.user});
  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  static const _pageSize = 50;
  List<Product> _items = [];
  final _q = TextEditingController();
  int _page = 0;
  bool _hasNext = false;
  bool _loading = true;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _q.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _q.removeListener(_onQueryChanged);
    _q.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _page = 0;
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    if (mounted) setState(() => _loading = true);
    final rows = await widget.repo.searchProducts(
      _q.text,
      limit: _pageSize + 1,
      offset: _page * _pageSize,
    );
    if (!mounted || version != _loadVersion) return;
    if (rows.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _hasNext = rows.length > _pageSize;
      _items = rows.take(_pageSize).toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext)) return;
    setState(() => _page = next);
    await _load();
  }

  Future<void> _adjust(Product p) async {
    final ctrl = TextEditingController(text: p.stock.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('盘点 ${p.nameZh}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '实盘数量'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.adjustStock(
      productId: p.id,
      newStock: double.tryParse(ctrl.text.trim()) ?? p.stock,
      operator: widget.user.username,
      reason: 'stocktake',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '盘点 / Stocktake',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索商品',
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final p = _items[i];
                      return ListTile(
                        title: Text(p.nameZh),
                        subtitle: Text('账面 ${p.stock} ${p.unit}'),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _adjust(p),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _page == 0 || _loading ? null : () => _changePage(-1),
                    child: const Text('上一页'),
                  ),
                  Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),
                  OutlinedButton(
                    onPressed: !_hasNext || _loading ? null : () => _changePage(1),
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

'''
t = replace_regex(t, r"class StocktakePage extends StatefulWidget \{[\s\S]*?\nclass UsersPage extends StatefulWidget", new_stocktake + "class UsersPage extends StatefulWidget", 'stocktake class')

new_daily = r'''class DailyClosePage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const DailyClosePage({super.key, required this.repo, required this.user});
  @override
  State<DailyClosePage> createState() => _DailyClosePageState();
}

class _DailyClosePageState extends State<DailyClosePage> {
  static const _pageSize = 50;
  final _open = TextEditingController(text: '0.00');
  final _count = TextEditingController(text: '0.00');
  final _notes = TextEditingController();
  int _systemCash = 0;
  List<Map<String, Object?>> _history = [];
  int _page = 0;
  bool _hasNext = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dash = await widget.repo.dashboardToday();
    final rows = await widget.repo.listClosings(
      limit: _pageSize + 1,
      offset: _page * _pageSize,
    );
    if (!mounted) return;
    if (rows.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _systemCash = dash['cash'] ?? 0;
      _hasNext = rows.length > _pageSize;
      _history = rows.take(_pageSize).toList(growable: false);
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext)) return;
    setState(() => _page = next);
    await _load();
  }

  Future<void> _save() async {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    await widget.repo.saveDailyClosing(
      businessDate: day,
      openingCashCents: rmToCents(double.tryParse(_open.text) ?? 0),
      countedCashCents: rmToCents(double.tryParse(_count.text) ?? 0),
      systemCashCents: _systemCash,
      closedBy: widget.user.username,
      notes: _notes.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日结已保存 / Closing saved')),
    );
    _page = 0;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '日结 / Daily cash',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('系统现金 / System cash: ${formatRm(_systemCash)}'),
          const SizedBox(height: 8),
          TextField(controller: _open, decoration: const InputDecoration(labelText: '开档现金 RM', prefixText: 'RM ')),
          TextField(controller: _count, decoration: const InputDecoration(labelText: '实盘现金 RM', prefixText: 'RM ')),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: '备注')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('保存日结')),
          const Divider(height: 32),
          const Text('历史 / History', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._history.map((h) => ListTile(
                title: Text('${h['business_date']}'),
                subtitle: Text(
                    '系统 ${formatRm(h['system_cash_cents'] as int)} · 实盘 ${formatRm(h['counted_cash_cents'] as int)}'),
              )),
          Row(
            children: [
              OutlinedButton(
                onPressed: _page == 0 ? null : () => _changePage(-1),
                child: const Text('上一页'),
              ),
              Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),
              OutlinedButton(
                onPressed: !_hasNext ? null : () => _changePage(1),
                child: const Text('下一页'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

'''
t = replace_regex(t, r"class DailyClosePage extends StatefulWidget \{[\s\S]*?\nclass MaintenancePage extends StatelessWidget", new_daily + "class MaintenancePage extends StatelessWidget", 'daily close class')

new_audit = r'''class AuditLogPage extends StatefulWidget {
  final PosRepository repo;
  const AuditLogPage({super.key, required this.repo});
  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  static const _pageSize = 50;
  bool _todayOnly = true;
  String _userFilter = '';
  List<AuditEntry> _rows = [];
  bool _loading = true;
  int _page = 0;
  bool _hasNext = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    if (mounted) setState(() => _loading = true);
    final list = await widget.repo.listAudit(
      todayOnly: _todayOnly,
      username: _userFilter.trim().isEmpty ? null : _userFilter.trim(),
      limit: _pageSize + 1,
      offset: _page * _pageSize,
    );
    if (!mounted || version != _loadVersion) return;
    if (list.isEmpty && _page > 0) {
      _page--;
      await _load();
      return;
    }
    setState(() {
      _rows = list.take(_pageSize).toList(growable: false);
      _hasNext = list.length > _pageSize;
      _loading = false;
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext)) return;
    setState(() => _page = next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('折扣/改价审计 / Audit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('今日'),
                  selected: _todayOnly,
                  onSelected: (v) {
                    setState(() {
                      _todayOnly = v;
                      _page = 0;
                    });
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '按用户名筛选 / Filter user',
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      _userFilter = v;
                      _page = 0;
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('暂无审计记录'))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final a = _rows[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${a.action} · ${a.productName ?? a.context}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${a.occurredAt.replaceFirst('T', ' ').substring(0, 19)}\n'
                              '${a.username} (${a.role})  ${a.oldValue} → ${a.newValue}'
                              '${a.reason.isEmpty ? '' : ' · ${a.reason}'}',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _page == 0 || _loading ? null : () => _changePage(-1),
                    child: const Text('上一页'),
                  ),
                  Expanded(child: Center(child: Text('第 ${_page + 1} 页'))),
                  OutlinedButton(
                    onPressed: !_hasNext || _loading ? null : () => _changePage(1),
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
'''
t = replace_regex(t, r"class AuditLogPage extends StatefulWidget \{[\s\S]*\Z", new_audit, 'audit class')
write(p, t)

# Regression tests for 50/40 paging boundaries and stable full-set access.
Path('test/pagination_repository_test.dart').write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository pagination', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_paging_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    test('101 products page as 50 / 50 / 1 without duplicates', () async {
      final db = await database.db;
      for (var i = 0; i < 101; i++) {
        final id = 'p-${i.toString().padLeft(3, '0')}';
        await db.insert('products', Product(
          id: id,
          nameZh: '商品 ${i.toString().padLeft(3, '0')}',
          nameEn: '',
          sku: 'SKU$i',
          barcode: 'B$i',
          priceCents: 100,
          costCents: 50,
          stock: 1,
          unit: 'pcs',
          category: '测试',
        ).toMap());
      }

      final a = await repo.searchProducts('', limit: 50, offset: 0);
      final b = await repo.searchProducts('', limit: 50, offset: 50);
      final c = await repo.searchProducts('', limit: 50, offset: 100);
      expect([a.length, b.length, c.length], [50, 50, 1]);
      final ids = [...a, ...b, ...c].map((p) => p.id).toList();
      expect(ids.toSet().length, 101);
      expect(await repo.countProducts(''), 101);
    });

    test('customer and supplier page boundaries reach row 51', () async {
      final db = await database.db;
      for (var i = 0; i < 51; i++) {
        final n = i.toString().padLeft(3, '0');
        await db.insert('customers', {
          'id': 'c$n', 'name': 'Customer $n', 'phone': '', 'notes': '', 'is_deleted': 0,
        });
        await db.insert('suppliers', {
          'id': 's$n', 'name': 'Supplier $n', 'phone': '', 'email': '', 'notes': '', 'is_deleted': 0,
        });
      }
      expect((await repo.listCustomers(limit: 50)).length, 50);
      expect((await repo.listCustomers(limit: 50, offset: 50)).single.id, 'c050');
      expect((await repo.listSuppliers(limit: 50)).length, 50);
      expect((await repo.listSuppliers(limit: 50, offset: 50)).single.id, 's050');
    });
  });
}
''', encoding='utf-8')

# Remove this one-shot machinery from the resulting source commit.
Path('scripts/apply_pagination_fix.py').unlink(missing_ok=True)
Path('.github/workflows/apply-pagination-fix.yml').unlink(missing_ok=True)
