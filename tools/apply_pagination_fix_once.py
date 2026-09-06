from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    s = text(path)
    if old not in s:
        raise RuntimeError(f'expected text not found in {path}: {old[:120]!r}')
    write(path, s.replace(old, new, 1))


def regex_once(path: str, pattern: str, new: str) -> None:
    s = text(path)
    out, n = re.subn(pattern, new, s, count=1, flags=re.S)
    if n != 1:
        raise RuntimeError(f'expected one regex match in {path}, got {n}: {pattern[:120]}')
    write(path, out)


# ---------------------------------------------------------------------------
# Shared pagination UI helpers
# ---------------------------------------------------------------------------
write('lib/widgets/pager_bar.dart', r'''import 'package:flutter/material.dart';

class PagerBar extends StatelessWidget {
  const PagerBar({
    super.key,
    required this.page,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
    this.loading = false,
  });

  final int page;
  final int totalItems;
  final int pageSize;
  final bool loading;
  final ValueChanged<int> onPageChanged;

  int get totalPages {
    if (totalItems <= 0) return 1;
    return (totalItems + pageSize - 1) ~/ pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final pages = totalPages;
    final safePage = page.clamp(0, pages - 1);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(
        height: 42,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页 / Previous',
              visualDensity: VisualDensity.compact,
              onPressed: loading || safePage <= 0
                  ? null
                  : () => onPageChanged(safePage - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: Text(
                '第 ${safePage + 1} / $pages 页 · 共 $totalItems',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '下一页 / Next',
              visualDensity: VisualDensity.compact,
              onPressed: loading || safePage + 1 >= pages
                  ? null
                  : () => onPageChanged(safePage + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
''')

write('lib/widgets/paged_product_picker.dart', r'''import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/pos_repository.dart';
import 'pager_bar.dart';

class PagedProductPicker {
  const PagedProductPicker._();

  static Future<Product?> show(
    BuildContext context, {
    required PosRepository repo,
    Product? selected,
    String title = '选择商品 / Select product',
  }) {
    return showDialog<Product>(
      context: context,
      builder: (_) => _PagedProductPickerDialog(
        repo: repo,
        selected: selected,
        title: title,
      ),
    );
  }
}

class _PagedProductPickerDialog extends StatefulWidget {
  const _PagedProductPickerDialog({
    required this.repo,
    required this.selected,
    required this.title,
  });

  final PosRepository repo;
  final Product? selected;
  final String title;

  @override
  State<_PagedProductPickerDialog> createState() =>
      _PagedProductPickerDialogState();
}

class _PagedProductPickerDialogState
    extends State<_PagedProductPickerDialog> {
  static const _pageSize = 50;
  final _search = TextEditingController();
  List<Product> _items = const [];
  int _page = 0;
  int _total = 0;
  int _request = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_searchChanged);
    _search.dispose();
    super.dispose();
  }

  void _searchChanged() {
    _page = 0;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted) setState(() => _loading = true);
    final q = _search.text;
    final total = await widget.repo.countProducts(q);
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final items = await widget.repo.searchProducts(
      q,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted || request != _request) return;
    setState(() {
      _page = page;
      _total = total;
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            if (widget.selected != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前：${widget.selected!.nameZh}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索名称 / SKU / 条码',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('没有匹配商品'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = _items[index];
                            return ListTile(
                              dense: true,
                              selected: widget.selected?.id == p.id,
                              title: Text(p.nameZh),
                              subtitle: Text('${p.sku} · ${p.barcode}'),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
            PagerBar(
              page: _page,
              totalItems: _total,
              pageSize: _pageSize,
              loading: _loading,
              onPageChanged: (page) {
                setState(() => _page = page);
                _load();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
''')

# ---------------------------------------------------------------------------
# Repository: real LIMIT/OFFSET + total counts, keeping old defaults compatible
# ---------------------------------------------------------------------------
regex_once(
    'lib/services/pos_repository.dart',
    r"  Future<List<Product>> searchProducts\(.*?\n  Future<Product\?> findByBarcodeOrSku",
    r'''  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async {
    if (limit <= 0 || offset < 0) return const [];
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
    final rows = await d.query(
      'products',
      where: where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: q.isEmpty
          ? 'category COLLATE NOCASE, name_zh COLLATE NOCASE, id'
          : 'name_zh COLLATE NOCASE, id',
      limit: limit,
      offset: offset,
    );
    if (q.isNotEmpty) {
      rows.sort((a, b) {
        final ab = (a['barcode'] as String?) ?? '';
        final bb = (b['barcode'] as String?) ?? '';
        if (ab == q && bb != q) return -1;
        if (bb == q && ab != q) return 1;
        return 0;
      });
    }
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

  Future<Product?> findByBarcodeOrSku''',
)

regex_once(
    'lib/services/pos_repository.dart',
    r"  Future<List<Customer>> listCustomers\(\) async \{.*?\n  Future<void> _saveEntity",
    r'''  Future<List<Customer>> listCustomers({
    int? limit,
    int offset = 0,
    String query = '',
  }) async {
    final d = await _db.db;
    final q = query.trim();
    final where = <String>['is_deleted=0'];
    final args = <Object?>[];
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add('(name LIKE ? OR phone LIKE ? OR notes LIKE ?)');
      args.addAll([like, like, like]);
    }
    final rows = await d.query(
      'customers',
      where: where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE, id',
      limit: limit,
      offset: limit == null ? null : offset,
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<int> countCustomers({String query = ''}) async {
    final d = await _db.db;
    final q = query.trim();
    final args = <Object?>[];
    var where = 'is_deleted=0';
    if (q.isNotEmpty) {
      final like = '%$q%';
      where += ' AND (name LIKE ? OR phone LIKE ? OR notes LIKE ?)';
      args.addAll([like, like, like]);
    }
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM customers WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> _saveEntity''',
)

replace_once(
    'lib/services/pos_repository.dart',
    """  Future<List<Supplier>> listSuppliers() async => (await (await _db.db).query(\n    'suppliers',\n    where: 'is_deleted=0',\n    orderBy: 'name COLLATE NOCASE',\n  )).map(Supplier.fromMap).toList();\n""",
    """  Future<List<Supplier>> listSuppliers({\n    int? limit,\n    int offset = 0,\n    String query = '',\n  }) async {\n    final d = await _db.db;\n    final q = query.trim();\n    final where = <String>['is_deleted=0'];\n    final args = <Object?>[];\n    if (q.isNotEmpty) {\n      final like = '%$q%';\n      where.add('(name LIKE ? OR phone LIKE ? OR email LIKE ? OR notes LIKE ?)');\n      args.addAll([like, like, like, like]);\n    }\n    final rows = await d.query(\n      'suppliers',\n      where: where.join(' AND '),\n      whereArgs: args.isEmpty ? null : args,\n      orderBy: 'name COLLATE NOCASE, id',\n      limit: limit,\n      offset: limit == null ? null : offset,\n    );\n    return rows.map(Supplier.fromMap).toList();\n  }\n\n  Future<int> countSuppliers({String query = ''}) async {\n    final d = await _db.db;\n    final q = query.trim();\n    final args = <Object?>[];\n    var where = 'is_deleted=0';\n    if (q.isNotEmpty) {\n      final like = '%$q%';\n      where += ' AND (name LIKE ? OR phone LIKE ? OR email LIKE ? OR notes LIKE ?)';\n      args.addAll([like, like, like, like]);\n    }\n    final rows = await d.rawQuery(\n      'SELECT COUNT(*) AS c FROM suppliers WHERE $where',\n      args,\n    );\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n""",
)

replace_once(
    'lib/services/pos_repository.dart',
    """  Future<List<SaleRecord>> salesAll({int? limit}) async {\n    final d = await _db.db;\n    final rows = await d.query('sales', orderBy: 'sold_at DESC', limit: limit);\n    return rows.map(SaleRecord.fromMap).toList();\n  }\n\n  Future<void> voidSale""",
    """  Future<List<SaleRecord>> salesAll({int? limit}) async {\n    final d = await _db.db;\n    final rows = await d.query(\n      'sales',\n      orderBy: 'sold_at DESC, id DESC',\n      limit: limit,\n    );\n    return rows.map(SaleRecord.fromMap).toList();\n  }\n\n  ({String where, List<Object?> args}) _saleFilter({\n    required bool todayOnly,\n    required String query,\n    String? fromDay,\n    String? toDay,\n  }) {\n    final where = <String>[];\n    final args = <Object?>[];\n    if (todayOnly) {\n      final day = DateTime.now().toIso8601String().substring(0, 10);\n      where.add('sold_at LIKE ?');\n      args.add('$day%');\n      where.add('voided=0');\n    }\n    if ((fromDay ?? '').isNotEmpty) {\n      where.add('substr(sold_at,1,10) >= ?');\n      args.add(fromDay);\n    }\n    if ((toDay ?? '').isNotEmpty) {\n      where.add('substr(sold_at,1,10) <= ?');\n      args.add(toDay);\n    }\n    final q = query.trim().toLowerCase();\n    if (q.isNotEmpty) {\n      final like = '%$q%';\n      where.add(\n        '(lower(receipt_no) LIKE ? OR lower(COALESCE(customer_phone,\'\')) LIKE ? OR lower(COALESCE(customer_name,\'\')) LIKE ? OR lower(payment_method) LIKE ?)',\n      );\n      args.addAll([like, like, like, like]);\n    }\n    return (where: where.isEmpty ? '1=1' : where.join(' AND '), args: args);\n  }\n\n  Future<List<SaleRecord>> querySales({\n    bool todayOnly = false,\n    String query = '',\n    String? fromDay,\n    String? toDay,\n    int limit = 50,\n    int offset = 0,\n  }) async {\n    final d = await _db.db;\n    final filter = _saleFilter(\n      todayOnly: todayOnly,\n      query: query,\n      fromDay: fromDay,\n      toDay: toDay,\n    );\n    final rows = await d.query(\n      'sales',\n      where: filter.where,\n      whereArgs: filter.args,\n      orderBy: 'sold_at DESC, id DESC',\n      limit: limit,\n      offset: offset,\n    );\n    return rows.map(SaleRecord.fromMap).toList();\n  }\n\n  Future<int> countSales({\n    bool todayOnly = false,\n    String query = '',\n    String? fromDay,\n    String? toDay,\n  }) async {\n    final d = await _db.db;\n    final filter = _saleFilter(\n      todayOnly: todayOnly,\n      query: query,\n      fromDay: fromDay,\n      toDay: toDay,\n    );\n    final rows = await d.rawQuery(\n      'SELECT COUNT(*) AS c FROM sales WHERE ${filter.where}',\n      filter.args,\n    );\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n\n  Future<void> voidSale""",
)

replace_once(
    'lib/services/pos_repository.dart',
    """  Future<List<Map<String, Object?>>> listPurchases() async {\n    final d = await _db.db;\n    return d.query('purchases', orderBy: 'purchased_at DESC');\n  }\n""",
    """  Future<List<Map<String, Object?>>> listPurchases({\n    int? limit,\n    int offset = 0,\n  }) async {\n    final d = await _db.db;\n    return d.query(\n      'purchases',\n      orderBy: 'purchased_at DESC, id DESC',\n      limit: limit,\n      offset: limit == null ? null : offset,\n    );\n  }\n\n  Future<int> countPurchases() async {\n    final d = await _db.db;\n    final rows = await d.rawQuery('SELECT COUNT(*) AS c FROM purchases');\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n""",
)

replace_once(
    'lib/services/pos_repository.dart',
    """  Future<List<Map<String, Object?>>> listClosings() async {\n    final d = await _db.db;\n    return d.query('daily_closings', orderBy: 'business_date DESC');\n  }\n""",
    """  Future<List<Map<String, Object?>>> listClosings({\n    int? limit,\n    int offset = 0,\n  }) async {\n    final d = await _db.db;\n    return d.query(\n      'daily_closings',\n      orderBy: 'business_date DESC, closed_at DESC, id DESC',\n      limit: limit,\n      offset: limit == null ? null : offset,\n    );\n  }\n\n  Future<int> countClosings() async {\n    final d = await _db.db;\n    final rows = await d.rawQuery('SELECT COUNT(*) AS c FROM daily_closings');\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n""",
)

regex_once(
    'lib/services/pos_repository.dart',
    r"  Future<List<AuditEntry>> listAudit\(\{.*?\n  Future<List<Category>> listCategories",
    r'''  ({String where, List<Object?> args}) _auditFilter({
    String? username,
    bool todayOnly = false,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (todayOnly) {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      where.add('occurred_at LIKE ?');
      args.add('$day%');
    }
    if (username != null && username.isNotEmpty) {
      where.add('username=?');
      args.add(username);
    }
    return (where: where.isEmpty ? '1=1' : where.join(' AND '), args: args);
  }

  Future<List<AuditEntry>> listAudit({
    String? username,
    bool todayOnly = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final d = await _db.db;
    final filter = _auditFilter(username: username, todayOnly: todayOnly);
    final rows = await d.query(
      'audit_logs',
      where: filter.where,
      whereArgs: filter.args,
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<int> countAudit({
    String? username,
    bool todayOnly = false,
  }) async {
    final d = await _db.db;
    final filter = _auditFilter(username: username, todayOnly: todayOnly);
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_logs WHERE ${filter.where}',
      filter.args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<Category>> listCategories''',
)

replace_once(
    'lib/services/pos_repository.dart',
    """  Future<List<Map<String, Object?>>> listBarcodeQueue({\n    String status = 'pending',\n  }) async {\n    final d = await _db.db;\n    return d.query(\n      'barcode_print_queue',\n      where: 'status=?',\n      whereArgs: [status],\n      orderBy: 'created_at ASC',\n    );\n  }\n""",
    """  Future<List<Map<String, Object?>>> listBarcodeQueue({\n    String status = 'pending',\n    int? limit,\n    int offset = 0,\n  }) async {\n    final d = await _db.db;\n    return d.query(\n      'barcode_print_queue',\n      where: 'status=?',\n      whereArgs: [status],\n      orderBy: 'created_at ASC, id ASC',\n      limit: limit,\n      offset: limit == null ? null : offset,\n    );\n  }\n\n  Future<int> countBarcodeQueue({String status = 'pending'}) async {\n    final d = await _db.db;\n    final rows = await d.rawQuery(\n      'SELECT COUNT(*) AS c FROM barcode_print_queue WHERE status=?',\n      [status],\n    );\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n""",
)

# ---------------------------------------------------------------------------
# OCR matching: remove hidden 5000-product ceiling by ranking every DB page.
# Alias list also gets real pagination.
# ---------------------------------------------------------------------------
replace_once(
    'lib/services/purchase_ocr_repository.dart',
    """    final products = await posRepo.searchProducts('', limit: 5000);\n    final preparedLines = <PurchaseDraftLine>[];\n""",
    """    final preparedLines = <PurchaseDraftLine>[];\n""",
)
replace_once(
    'lib/services/purchase_ocr_repository.dart',
    """        final candidates = _matcher.rank(line.rawProductName, products);\n""",
    """        final candidates = await candidatesFor(line.rawProductName);\n""",
)
regex_once(
    'lib/services/purchase_ocr_repository.dart',
    r"  Future<List<ProductMatchCandidate>> candidatesFor\(String rawName\) async \{.*?\n  Future<Map<String, Object\?>\?> lookupAlias",
    r'''  Future<List<ProductMatchCandidate>> candidatesFor(String rawName) async {
    const pageSize = 200;
    var offset = 0;
    final best = <ProductMatchCandidate>[];
    while (true) {
      final page = await posRepo.searchProducts(
        '',
        limit: pageSize,
        offset: offset,
      );
      if (page.isEmpty) break;
      best.addAll(_matcher.rank(rawName, page, limit: 8));
      best.sort((a, b) => b.confidence.compareTo(a.confidence));
      if (best.length > 8) best.removeRange(8, best.length);
      if (page.length < pageSize) break;
      offset += page.length;
    }
    return best;
  }

  Future<Map<String, Object?>?> lookupAlias''',
)
replace_once(
    'lib/services/purchase_ocr_repository.dart',
    """  Future<List<Map<String, Object?>>> listAliases({String? supplierId}) async {\n    final db = await _db();\n    return db.query(\n      'supplier_product_aliases',\n      where: supplierId == null ? null : 'supplier_id=?',\n      whereArgs: supplierId == null ? null : [supplierId],\n      orderBy: 'last_used_at DESC',\n    );\n  }\n""",
    """  Future<List<Map<String, Object?>>> listAliases({\n    String? supplierId,\n    int? limit,\n    int offset = 0,\n  }) async {\n    final db = await _db();\n    return db.query(\n      'supplier_product_aliases',\n      where: supplierId == null ? null : 'supplier_id=?',\n      whereArgs: supplierId == null ? null : [supplierId],\n      orderBy: 'last_used_at DESC, id DESC',\n      limit: limit,\n      offset: limit == null ? null : offset,\n    );\n  }\n\n  Future<int> countAliases({String? supplierId}) async {\n    final db = await _db();\n    final rows = await db.rawQuery(\n      supplierId == null\n          ? 'SELECT COUNT(*) AS c FROM supplier_product_aliases'\n          : 'SELECT COUNT(*) AS c FROM supplier_product_aliases WHERE supplier_id=?',\n      supplierId == null ? const [] : [supplierId],\n    );\n    return Sqflite.firstIntValue(rows) ?? 0;\n  }\n""",
)

# ---------------------------------------------------------------------------
# Checkout product strip: 40 per real DB page + stale-request protection.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/cart_screen.dart',
    "import '../widgets/money_text.dart';\n",
    "import '../widgets/money_text.dart';\nimport '../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/cart_screen.dart',
    """  bool _loading = true;\n  bool _imagesOn = false;\n""",
    """  bool _loading = true;\n  bool _imagesOn = false;\n  static const _pageSize = 40;\n  int _page = 0;\n  int _total = 0;\n  int _loadRequest = 0;\n""",
)
replace_once(
    'lib/screens/cart_screen.dart',
    """    _reload('');\n    _search.addListener(() => _reload(_search.text));\n""",
    """    _reload('');\n    _search.addListener(() {\n      _page = 0;\n      _reload(_search.text);\n    });\n""",
)
regex_once(
    'lib/screens/cart_screen.dart',
    r"  Future<void> _reload\(String q\) async \{.*?\n  Future<bool> _add",
    r'''  Future<void> _reload(String q) async {
    final request = ++_loadRequest;
    if (mounted) setState(() => _loading = true);
    final category = _category.isEmpty ? null : _category;
    final total = await widget.repo.countProducts(q, category: category);
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final list = await widget.repo.searchProducts(
      q,
      category: category,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _page = page;
      _total = total;
      _results = list;
      _loading = false;
    });
  }

  Future<bool> _add''',
)
replace_once(
    'lib/screens/cart_screen.dart',
    """                          setState(() => _category = '');\n                          _reload(_search.text);\n""",
    """                          setState(() {\n                            _category = '';\n                            _page = 0;\n                          });\n                          _reload(_search.text);\n""",
)
replace_once(
    'lib/screens/cart_screen.dart',
    """                            setState(() => _category = c.name);\n                            _reload(_search.text);\n""",
    """                            setState(() {\n                              _category = c.name;\n                              _page = 0;\n                            });\n                            _reload(_search.text);\n""",
)
replace_once(
    'lib/screens/cart_screen.dart',
    '                  itemCount: _results.length.clamp(0, 40),\n',
    '                  itemCount: _results.length,\n',
)
replace_once(
    'lib/screens/cart_screen.dart',
    """        Padding(\n          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),\n          child: Row(\n            children: [\n              Text('购物车 (${cart.itemCount})',\n""",
    """        PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _loading,\n          onPageChanged: (page) {\n            setState(() => _page = page);\n            _reload(_search.text);\n          },\n        ),\n        Padding(\n          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),\n          child: Row(\n            children: [\n              Text('购物车 (${cart.itemCount})',\n""",
)

# ---------------------------------------------------------------------------
# Products admin: 50/page, full search, stable page count.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/products_admin.dart',
    "import '../../widgets/money_text.dart';\n",
    "import '../../widgets/money_text.dart';\nimport '../../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    """  bool _imagesOn = false;\n  bool _busy = false;\n""",
    """  bool _imagesOn = false;\n  bool _busy = false;\n  bool _pageLoading = false;\n  static const _pageSize = 50;\n  int _page = 0;\n  int _total = 0;\n  int _loadRequest = 0;\n""",
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    '    _q.addListener(_load);\n',
    """    _q.addListener(() {\n      _page = 0;\n      _load();\n    });\n""",
)
regex_once(
    'lib/screens/admin/products_admin.dart',
    r"  Future<void> _load\(\) async \{\n    final list = await widget\.repo\.searchProducts\(_q\.text, limit: 300\);.*?\n  \}\n\n  List<Product> get _selectedProducts",
    r'''  Future<void> _load() async {
    final request = ++_loadRequest;
    if (mounted) setState(() => _pageLoading = true);
    final q = _q.text;
    final total = await widget.repo.countProducts(q);
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final list = await widget.repo.searchProducts(
      q,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _page = page;
      _total = total;
      _items = list;
      _selected.removeWhere((id) => !_items.any((p) => p.id == id));
      if (_selected.isEmpty) _selectMode = false;
      _pageLoading = false;
    });
  }

  List<Product> get _selectedProducts''',
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    """    return Scaffold(\n      appBar: AppBar(\n        title: Text(_selectMode ? '已选 ${_selected.length}' : '商品 / Products'),\n""",
    """    return Scaffold(\n      bottomNavigationBar: SafeArea(\n        child: PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _pageLoading || _busy,\n          onPageChanged: (page) {\n            setState(() {\n              _page = page;\n              _selected.clear();\n              _selectMode = false;\n            });\n            _load();\n          },\n        ),\n      ),\n      appBar: AppBar(\n        title: Text(_selectMode ? '已选 ${_selected.length}' : '商品 / Products'),\n""",
)

# Barcode queue: 50/page for display, export action still exports the entire queue.
replace_once(
    'lib/screens/admin/products_admin.dart',
    """  late final BarcodeLabelService _labels = BarcodeLabelService(widget.repo);\n  bool _busy = false;\n\n  @override\n  void initState() {\n""",
    """  late final BarcodeLabelService _labels = BarcodeLabelService(widget.repo);\n  bool _busy = false;\n  bool _pageLoading = false;\n  static const _pageSize = 50;\n  int _page = 0;\n  int _total = 0;\n\n  @override\n  void initState() {\n""",
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    """  Future<void> _load() async {\n    final rows = await widget.repo.listBarcodeQueue();\n    if (mounted) setState(() => _rows = rows);\n  }\n\n  Future<void> _exportQueue() async {\n""",
    """  Future<void> _load() async {\n    if (mounted) setState(() => _pageLoading = true);\n    final total = await widget.repo.countBarcodeQueue();\n    var page = _page;\n    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;\n    if (page >= pages) page = pages - 1;\n    final rows = await widget.repo.listBarcodeQueue(\n      limit: _pageSize,\n      offset: page * _pageSize,\n    );\n    if (mounted) {\n      setState(() {\n        _page = page;\n        _total = total;\n        _rows = rows;\n        _pageLoading = false;\n      });\n    }\n  }\n\n  Future<void> _exportQueue() async {\n""",
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    """    if (_rows.isEmpty) {\n      ScaffoldMessenger.of(context).showSnackBar(\n""",
    """    final exportRows = await widget.repo.listBarcodeQueue();\n    if (exportRows.isEmpty) {\n      ScaffoldMessenger.of(context).showSnackBar(\n""",
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    '      for (final row in _rows) {\n',
    '      for (final row in exportRows) {\n',
)
replace_once(
    'lib/screens/admin/products_admin.dart',
    """    return Scaffold(\n      appBar: AppBar(\n        title: const Text('条码打印队列 / Print queue'),\n""",
    """    return Scaffold(\n      bottomNavigationBar: SafeArea(\n        child: PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _pageLoading || _busy,\n          onPageChanged: (page) {\n            setState(() => _page = page);\n            _load();\n          },\n        ),\n      ),\n      appBar: AppBar(\n        title: const Text('条码打印队列 / Print queue'),\n""",
)

# ---------------------------------------------------------------------------
# Customer / supplier management: 50 per page.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/entities_page.dart',
    "import '../../theme/cnkh_theme.dart';\n",
    "import '../../theme/cnkh_theme.dart';\nimport '../../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/admin/entities_page.dart',
    """  bool _selectMode = false;\n  bool _busy = false;\n""",
    """  bool _selectMode = false;\n  bool _busy = false;\n  bool _pageLoading = false;\n  static const _pageSize = 50;\n  int _page = 0;\n  int _total = 0;\n""",
)
regex_once(
    'lib/screens/admin/entities_page.dart',
    r"  Future<void> _load\(\) async \{.*?\n  \}\n\n  Future<void> _edit",
    r'''  Future<void> _load() async {
    if (mounted) setState(() => _pageLoading = true);
    final total = _isCustomers
        ? await widget.repo.countCustomers()
        : await widget.repo.countSuppliers();
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final items = _isCustomers
        ? await widget.repo.listCustomers(
            limit: _pageSize,
            offset: page * _pageSize,
          )
        : await widget.repo.listSuppliers(
            limit: _pageSize,
            offset: page * _pageSize,
          );
    if (!mounted) return;
    setState(() {
      _page = page;
      _total = total;
      _items = items.cast<Object>();
      _selected.removeWhere(
        (id) => !_items.any((item) => _idOf(item) == id),
      );
      if (_selected.isEmpty) _selectMode = false;
      _pageLoading = false;
    });
  }

  Future<void> _edit''',
)
replace_once(
    'lib/screens/admin/entities_page.dart',
    """    return Scaffold(\n      appBar: AppBar(\n        title: Text(_selectMode ? '已选 ${_selected.length}' : _title),\n""",
    """    return Scaffold(\n      bottomNavigationBar: SafeArea(\n        child: PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _pageLoading || _busy,\n          onPageChanged: (page) {\n            setState(() {\n              _page = page;\n              _selected.clear();\n              _selectMode = false;\n            });\n            _load();\n          },\n        ),\n      ),\n      appBar: AppBar(\n        title: Text(_selectMode ? '已选 ${_selected.length}' : _title),\n""",
)

# ---------------------------------------------------------------------------
# Purchase history 50/page; manual product picker sees every product; qty = 0.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    "import '../../widgets/money_text.dart';\n",
    "import '../../widgets/money_text.dart';\nimport '../../widgets/pager_bar.dart';\nimport '../../widgets/paged_product_picker.dart';\n",
)
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    """  String? _historySyncError;\n  static const _invoiceParser = PurchaseInvoiceParser();\n""",
    """  String? _historySyncError;\n  static const _pageSize = 50;\n  int _page = 0;\n  int _total = 0;\n  bool _pageLoading = false;\n  static const _invoiceParser = PurchaseInvoiceParser();\n""",
)
regex_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    r"  Future<void> _load\(\) async \{.*?\n  \}\n\n  Future<void> _openAliases",
    r'''  Future<void> _load({bool sync = true}) async {
    if (mounted) setState(() => _pageLoading = true);
    String? syncError;
    if (sync) {
      try {
        await PurchaseHistorySync(widget.repo).pullFromSavedDesktop();
      } catch (e) {
        syncError = '进货历史同步失败：$e';
      }
    }
    final total = await widget.repo.countPurchases();
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final rows = await widget.repo.listPurchases(
      limit: _pageSize,
      offset: page * _pageSize,
    );
    final drafts = await _ocrRepo.listDrafts();
    if (mounted) {
      setState(() {
        _page = page;
        _total = total;
        _rows = rows;
        _drafts = drafts;
        if (sync) _historySyncError = syncError;
        _pageLoading = false;
      });
    }
  }

  Future<void> _openAliases''',
)
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    """    final suppliers = await widget.repo.listSuppliers();\n    final products = await widget.repo.searchProducts('', limit: 50);\n""",
    """    final suppliers = await widget.repo.listSuppliers();\n    final products = await widget.repo.searchProducts('', limit: 1);\n""",
)
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    "    final qty = TextEditingController(text: '10');\n",
    "    final qty = TextEditingController(text: '0');\n",
)
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    """              DropdownButton<Product>(\n                isExpanded: true,\n                value: product,\n                items: [\n                  for (final p in products)\n                    DropdownMenuItem(value: p, child: Text(p.nameZh)),\n                ],\n                onChanged: (v) => setLocal(() {\n                  product = v!;\n                  cost.text = centsToRm(product.costCents).toStringAsFixed(2);\n                  costError = null;\n                }),\n              ),\n""",
    """              InputDecorator(\n                decoration: const InputDecoration(labelText: '商品 / Product'),\n                child: ListTile(\n                  dense: true,\n                  contentPadding: EdgeInsets.zero,\n                  title: Text(product.nameZh),\n                  subtitle: Text('${product.sku} · ${product.barcode}'),\n                  trailing: const Icon(Icons.search),\n                  onTap: () async {\n                    final picked = await PagedProductPicker.show(\n                      ctx,\n                      repo: widget.repo,\n                      selected: product,\n                    );\n                    if (picked == null) return;\n                    setLocal(() {\n                      product = picked;\n                      cost.text =\n                          centsToRm(product.costCents).toStringAsFixed(2);\n                      costError = null;\n                    });\n                  },\n                ),\n              ),\n""",
)
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    """    await widget.repo.createPurchase(\n      supplierId: supplier.id,\n""",
    """    await widget.repo.createPurchase(\n      supplierId: supplier.id,\n""",
)
# Return to first history page after adding a new purchase.
replace_once(
    'lib/screens/admin/enhanced_purchases_page.dart',
    """      operator: widget.user.username,\n    );\n    await _load();\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      appBar: AppBar(\n        title: const Text('进货 / Purchases'),\n""",
    """      operator: widget.user.username,\n    );\n    _page = 0;\n    await _load();\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      bottomNavigationBar: SafeArea(\n        child: PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _pageLoading,\n          onPageChanged: (page) {\n            setState(() => _page = page);\n            _load(sync: false);\n          },\n        ),\n      ),\n      appBar: AppBar(\n        title: const Text('进货 / Purchases'),\n""",
)

# ---------------------------------------------------------------------------
# Checkout customer selector: 50/page while preserving selected customer.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/checkout_screen.dart',
    "import '../widgets/cash_change_dialog.dart';\n",
    "import '../widgets/cash_change_dialog.dart';\nimport '../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/checkout_screen.dart',
    """  List<Customer> _customers = [];\n  Customer? _customer;\n  bool _busy = false;\n""",
    """  List<Customer> _customers = [];\n  Customer? _customer;\n  static const _customerPageSize = 50;\n  int _customerPage = 0;\n  int _customerTotal = 0;\n  bool _customerLoading = false;\n  bool _busy = false;\n""",
)
regex_once(
    'lib/screens/checkout_screen.dart',
    r"  Future<void> _load\(\) async \{.*?\n  \}\n\n  void _syncCashField",
    r'''  Future<void> _load() async {
    final qr = await widget.qrStorage.getLocalPath();
    final total = await widget.repo.countCustomers();
    final customers = await widget.repo.listCustomers(
      limit: _customerPageSize,
      offset: _customerPage * _customerPageSize,
    );
    if (!mounted) return;
    setState(() {
      _qrPath = qr;
      _customerTotal = total;
      _customers = customers;
      _syncCashField();
    });
  }

  Future<void> _loadCustomerPage(int page) async {
    setState(() {
      _customerPage = page;
      _customerLoading = true;
    });
    final customers = await widget.repo.listCustomers(
      limit: _customerPageSize,
      offset: page * _customerPageSize,
    );
    if (!mounted || page != _customerPage) return;
    setState(() {
      _customers = customers;
      _customerLoading = false;
    });
  }

  void _syncCashField''',
)
replace_once(
    'lib/screens/checkout_screen.dart',
    """                      items: [\n                        const DropdownMenuItem(\n                            value: null, child: Text('— 无 —')),\n                        ..._customers.map(\n""",
    """                      items: [\n                        const DropdownMenuItem(\n                            value: null, child: Text('— 无 —')),\n                        if (_customer != null &&\n                            !_customers.any((c) => c.id == _customer!.id))\n                          DropdownMenuItem(\n                            value: _customer,\n                            child: Text(\n                              '${_customer!.name}  ${_customer!.phone}',\n                              overflow: TextOverflow.ellipsis,\n                            ),\n                          ),\n                        ..._customers.map(\n""",
)
replace_once(
    'lib/screens/checkout_screen.dart',
    """                if (_customer != null && _outstandingCents > 0) ...[\n""",
    """                PagerBar(\n                  page: _customerPage,\n                  totalItems: _customerTotal,\n                  pageSize: _customerPageSize,\n                  loading: _customerLoading,\n                  onPageChanged: _loadCustomerPage,\n                ),\n                if (_customer != null && _outstandingCents > 0) ...[\n""",
)

# ---------------------------------------------------------------------------
# Sales history: DB-side 50/page with query/date filters across all records.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/sales_list_screen.dart',
    "import '../widgets/money_text.dart';\n",
    "import '../widgets/money_text.dart';\nimport '../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    """  List<SaleRecord> _sales = [];\n  List<SaleRecord> _filtered = [];\n  bool _loading = true;\n""",
    """  List<SaleRecord> _sales = [];\n  bool _loading = true;\n  static const _pageSize = 50;\n  int _page = 0;\n  int _total = 0;\n  int _loadRequest = 0;\n""",
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    '    _q.addListener(_applyFilter);\n',
    """    _q.addListener(() {\n      _page = 0;\n      _load();\n    });\n""",
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    """      _load();\n    }\n  }\n\n  Future<void> _load() async {\n""",
    """      _page = 0;\n      _load();\n    }\n  }\n\n  Future<void> _load() async {\n""",
)
regex_once(
    'lib/screens/sales_list_screen.dart',
    r"  Future<void> _load\(\) async \{.*?\n  Future<void> _pickFrom",
    r'''  Future<void> _load() async {
    final request = ++_loadRequest;
    if (mounted) setState(() => _loading = true);
    final fromDay = _from?.toIso8601String().substring(0, 10);
    final toDay = _to?.toIso8601String().substring(0, 10);
    final total = await widget.repo.countSales(
      todayOnly: widget.todayOnly,
      query: _q.text,
      fromDay: fromDay,
      toDay: toDay,
    );
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final list = await widget.repo.querySales(
      todayOnly: widget.todayOnly,
      query: _q.text,
      fromDay: fromDay,
      toDay: toDay,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _page = page;
      _total = total;
      _sales = list;
      _loading = false;
    });
  }

  Future<void> _pickFrom''',
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    """    setState(() => _from = d);\n    _applyFilter();\n""",
    """    setState(() {\n      _from = d;\n      _page = 0;\n    });\n    _load();\n""",
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    """    setState(() => _to = d);\n    _applyFilter();\n""",
    """    setState(() {\n      _to = d;\n      _page = 0;\n    });\n    _load();\n""",
)
replace_once(
    'lib/screens/sales_list_screen.dart',
    """                      setState(() {\n                        _from = null;\n                        _to = null;\n                        _q.clear();\n                      });\n                      _applyFilter();\n""",
    """                      setState(() {\n                        _from = null;\n                        _to = null;\n                        _page = 0;\n                        _q.clear();\n                      });\n                      _load();\n""",
)
replace_once('lib/screens/sales_list_screen.dart', '_filtered.isEmpty', '_sales.isEmpty')
replace_once('lib/screens/sales_list_screen.dart', 'itemCount: _filtered.length,', 'itemCount: _sales.length,')
replace_once('lib/screens/sales_list_screen.dart', 'final s = _filtered[i];', 'final s = _sales[i];')
replace_once(
    'lib/screens/sales_list_screen.dart',
    """        Expanded(\n          child: RefreshIndicator(\n""",
    """        PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _loading,\n          onPageChanged: (page) {\n            setState(() => _page = page);\n            _load();\n          },\n        ),\n        Expanded(\n          child: RefreshIndicator(\n""",
)

# ---------------------------------------------------------------------------
# Legacy module is still routed for Stocktake, DailyClose and Audit.
# Add optional bottom pager slot to its scaffold and paginate active pages.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    "import '../../widgets/money_text.dart';\n",
    "import '../../widgets/money_text.dart';\nimport '../../widgets/pager_bar.dart';\n",
)
replace_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    """  final List<Widget>? actions;\n  const _ScaffoldPage({required this.title, required this.body, this.actions});\n""",
    """  final List<Widget>? actions;\n  final Widget? bottomNavigationBar;\n  const _ScaffoldPage({\n    required this.title,\n    required this.body,\n    this.actions,\n    this.bottomNavigationBar,\n  });\n""",
)
replace_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    """        actions: actions,\n      ),\n      body: body,\n""",
    """        actions: actions,\n      ),\n      body: body,\n      bottomNavigationBar: bottomNavigationBar,\n""",
)
regex_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    r"class StocktakePage extends StatefulWidget \{.*?\nclass UsersPage extends StatefulWidget",
    r'''class StocktakePage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const StocktakePage({super.key, required this.repo, required this.user});
  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  static const _pageSize = 50;
  List<Product> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final total = await widget.repo.countProducts('');
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final items = await widget.repo.searchProducts(
      '',
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _page = page;
      _total = total;
      _items = items;
      _loading = false;
    });
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
      bottomNavigationBar: SafeArea(
        child: PagerBar(
          page: _page,
          totalItems: _total,
          pageSize: _pageSize,
          loading: _loading,
          onPageChanged: (page) {
            setState(() => _page = page);
            _load();
          },
        ),
      ),
      body: _loading && _items.isEmpty
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
    );
  }
}

class UsersPage extends StatefulWidget''',
)
regex_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    r"class DailyClosePage extends StatefulWidget \{.*?\nclass MaintenancePage extends StatelessWidget",
    r'''class DailyClosePage extends StatefulWidget {
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
  int _total = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _open.dispose();
    _count.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dash = await widget.repo.dashboardToday();
    final total = await widget.repo.countClosings();
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final history = await widget.repo.listClosings(
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _systemCash = dash['cash'] ?? 0;
      _page = page;
      _total = total;
      _history = history;
      _loading = false;
    });
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
      bottomNavigationBar: SafeArea(
        child: PagerBar(
          page: _page,
          totalItems: _total,
          pageSize: _pageSize,
          loading: _loading,
          onPageChanged: (page) {
            setState(() => _page = page);
            _load();
          },
        ),
      ),
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
        ],
      ),
    );
  }
}

class MaintenancePage extends StatelessWidget''',
)
regex_once(
    'lib/screens/admin/admin_hub_legacy.dart',
    r"class AuditLogPage extends StatefulWidget \{.*\Z",
    r'''class AuditLogPage extends StatefulWidget {
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
  int _total = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted) setState(() => _loading = true);
    final username = _userFilter.trim().isEmpty ? null : _userFilter.trim();
    final total = await widget.repo.countAudit(
      todayOnly: _todayOnly,
      username: username,
    );
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final list = await widget.repo.listAudit(
      todayOnly: _todayOnly,
      username: username,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    if (!mounted || request != _request) return;
    setState(() {
      _page = page;
      _total = total;
      _rows = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: PagerBar(
          page: _page,
          totalItems: _total,
          pageSize: _pageSize,
          loading: _loading,
          onPageChanged: (page) {
            setState(() => _page = page);
            _load();
          },
        ),
      ),
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
            child: _loading && _rows.isEmpty
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
        ],
      ),
    );
  }
}
''',
)

# ---------------------------------------------------------------------------
# Supplier alias history: 50/page and use the full-dataset product picker.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    "import '../../theme/cnkh_theme.dart';\n",
    "import '../../theme/cnkh_theme.dart';\nimport '../../widgets/pager_bar.dart';\nimport '../../widgets/paged_product_picker.dart';\n",
)
replace_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    """  List<Map<String, Object?>> _aliases = const [];\n  List<Supplier> _suppliers = const [];\n  List<Product> _products = const [];\n  bool _loading = true;\n""",
    """  static const _pageSize = 50;\n  List<Map<String, Object?>> _aliases = const [];\n  List<Supplier> _suppliers = const [];\n  final Map<String, Product> _products = <String, Product>{};\n  int _page = 0;\n  int _total = 0;\n  bool _loading = true;\n""",
)
regex_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    r"  Future<void> _load\(\) async \{.*?\n  \}\n\n  String _supplierName",
    r'''  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final total = await _ocr.countAliases();
    var page = _page;
    final pages = total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    if (page >= pages) page = pages - 1;
    final aliases = await _ocr.listAliases(
      limit: _pageSize,
      offset: page * _pageSize,
    );
    final suppliers = await widget.repo.listSuppliers();
    final productCache = <String, Product>{};
    for (final alias in aliases) {
      final id = alias['product_id']?.toString() ?? '';
      if (id.isEmpty || productCache.containsKey(id)) continue;
      final product = await widget.repo.getProduct(id);
      if (product != null) productCache[id] = product;
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      _total = total;
      _aliases = aliases;
      _suppliers = suppliers;
      _products
        ..clear()
        ..addAll(productCache);
      _loading = false;
    });
  }

  String _supplierName''',
)
replace_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    """  String _productName(String id) {\n    for (final product in _products) {\n      if (product.id == id) return product.nameZh;\n    }\n    return id;\n  }\n""",
    """  String _productName(String id) => _products[id]?.nameZh ?? id;\n""",
)
regex_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    r"  Future<void> _edit\(Map<String, Object\?> alias\) async \{.*?\n  Future<void> _delete",
    r'''  Future<void> _edit(Map<String, Object?> alias) async {
    if (_busy) return;
    var productId = alias['product_id']?.toString() ?? '';
    Product? selectedProduct = productId.isEmpty
        ? null
        : await widget.repo.getProduct(productId);
    selectedProduct ??=
        (await widget.repo.searchProducts('', limit: 1)).firstOrNull;
    if (selectedProduct == null || !mounted) return;
    productId = selectedProduct.id;
    final unit = TextEditingController(
      text: alias['unit']?.toString().trim().isNotEmpty == true
          ? alias['unit'].toString()
          : 'pcs',
    );
    final conversion = TextEditingController(
      text: ((alias['conversion_factor'] as num?)?.toDouble() ?? 1).toString(),
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
                InputDecorator(
                  decoration: const InputDecoration(labelText: '匹配商品 / Product'),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(selectedProduct!.nameZh),
                    subtitle: Text('${selectedProduct.sku} · ${selectedProduct.barcode}'),
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final picked = await PagedProductPicker.show(
                        ctx,
                        repo: widget.repo,
                        selected: selectedProduct,
                      );
                      if (picked != null) {
                        setLocal(() {
                          selectedProduct = picked;
                          productId = picked.id;
                        });
                      }
                    },
                  ),
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

  Future<void> _delete''',
)
replace_once(
    'lib/screens/admin/supplier_aliases_page.dart',
    """    return Scaffold(\n      appBar: AppBar(title: const Text('供应商商品记忆 / Aliases')),\n""",
    """    return Scaffold(\n      bottomNavigationBar: SafeArea(\n        child: PagerBar(\n          page: _page,\n          totalItems: _total,\n          pageSize: _pageSize,\n          loading: _loading || _busy,\n          onPageChanged: (page) {\n            setState(() => _page = page);\n            _load();\n          },\n        ),\n      ),\n      appBar: AppBar(title: const Text('供应商商品记忆 / Aliases')),\n""",
)

# ---------------------------------------------------------------------------
# OCR review product selector: no 5000-item dropdown; cache only matched rows.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    "import '../../theme/cnkh_theme.dart';\n",
    "import '../../theme/cnkh_theme.dart';\nimport '../../widgets/paged_product_picker.dart';\n",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """      _suppliers = await widget.repo.listSuppliers();\n      _products = await widget.repo.searchProducts('', limit: 5000);\n\n      PurchaseDraft draft;\n""",
    """      _suppliers = await widget.repo.listSuppliers();\n\n      PurchaseDraft draft;\n""",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """      await _ocrRepo.saveDraft(draft);\n      persistedDraft = true;\n""",
    """      await _cacheMatchedProducts(draft);\n      await _ocrRepo.saveDraft(draft);\n      persistedDraft = true;\n""",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """  Future<void> _revalidate({bool save = true}) async {\n""",
    """  Future<void> _cacheMatchedProducts(PurchaseDraft draft) async {\n    final ids = draft.lines\n        .map((line) => line.matchedProductId)\n        .whereType<String>()\n        .where((id) => id.isNotEmpty)\n        .toSet();\n    final products = <Product>[];\n    for (final id in ids) {\n      final product = await widget.repo.getProduct(id);\n      if (product != null && product.isDeleted == 0) products.add(product);\n    }\n    _products = products;\n  }\n\n  Future<void> _revalidate({bool save = true}) async {\n""",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """    String? productId = line.matchedProductId;\n    if (productId != null && !_products.any((p) => p.id == productId)) {\n      productId = null;\n    }\n""",
    """    String? productId = line.matchedProductId;\n    Product? selectedProduct = productId == null\n        ? null\n        : await widget.repo.getProduct(productId);\n    if (selectedProduct == null) productId = null;\n""",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """                  DropdownButtonFormField<String>(\n                    value: productId,\n                    isExpanded: true,\n                    decoration: const InputDecoration(labelText: '匹配商品'),\n                    items: [\n                      for (final p in _products)\n                        DropdownMenuItem(\n                          value: p.id,\n                          child: Text(p.nameZh, overflow: TextOverflow.ellipsis),\n                        ),\n                    ],\n                    onChanged: (v) => setLocal(() => productId = v),\n                  ),\n""",
    """                  InputDecorator(\n                    decoration: const InputDecoration(labelText: '匹配商品'),\n                    child: ListTile(\n                      dense: true,\n                      contentPadding: EdgeInsets.zero,\n                      title: Text(selectedProduct?.nameZh ?? '选择商品'),\n                      subtitle: selectedProduct == null\n                          ? null\n                          : Text('${selectedProduct!.sku} · ${selectedProduct!.barcode}'),\n                      trailing: const Icon(Icons.search),\n                      onTap: () async {\n                        final picked = await PagedProductPicker.show(\n                          ctx,\n                          repo: widget.repo,\n                          selected: selectedProduct,\n                        );\n                        if (picked != null) {\n                          setLocal(() {\n                            selectedProduct = picked;\n                            productId = picked.id;\n                          });\n                        }\n                      },\n                    ),\n                  ),\n""",
)
replace_once(
    'lib/screens/admin/purchase_ocr_screen.dart',
    """    if (ok != true || productId == null) return;\n    final product = _products.firstWhere((p) => p.id == productId);\n    final nextLine = line.copyWith(\n""",
    """    if (ok != true || productId == null || selectedProduct == null) return;\n    final product = selectedProduct!;\n    if (!_products.any((p) => p.id == product.id)) {\n      _products = [..._products, product];\n    }\n    final nextLine = line.copyWith(\n""",
)

# ---------------------------------------------------------------------------
# Android release permission.
# ---------------------------------------------------------------------------
replace_once(
    'android/app/src/main/AndroidManifest.xml',
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n',
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET"/>\n',
)

# ---------------------------------------------------------------------------
# Repository pagination regression test (101/50/51 boundaries + master data).
# ---------------------------------------------------------------------------
write('test/pagination_repository_test.dart', r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('repository pagination', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_pagination_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    test('products expose 101 rows as 50/50/1 with no duplicate ids', () async {
      final db = await database.db;
      for (var i = 0; i < 101; i++) {
        final suffix = i.toString().padLeft(3, '0');
        await db.insert(
          'products',
          Product(
            id: 'p-$suffix',
            nameZh: '商品 $suffix',
            nameEn: 'Product $suffix',
            sku: 'SKU-$suffix',
            barcode: '9550000$suffix',
            priceCents: 100,
          ).toMap(),
        );
      }

      expect(await repo.countProducts(''), 101);
      final p1 = await repo.searchProducts('', limit: 50, offset: 0);
      final p2 = await repo.searchProducts('', limit: 50, offset: 50);
      final p3 = await repo.searchProducts('', limit: 50, offset: 100);
      expect(p1, hasLength(50));
      expect(p2, hasLength(50));
      expect(p3, hasLength(1));
      final ids = [...p1, ...p2, ...p3].map((p) => p.id).toSet();
      expect(ids, hasLength(101));
      expect(ids, contains('p-100'));

      final searched = await repo.searchProducts('SKU-100', limit: 50);
      expect(searched.single.id, 'p-100');
    });

    test('customers and suppliers page after row 50', () async {
      final db = await database.db;
      for (var i = 0; i < 51; i++) {
        final suffix = i.toString().padLeft(3, '0');
        await db.insert('customers', {
          'id': 'c-$suffix',
          'name': 'Customer $suffix',
          'phone': '',
          'notes': '',
          'is_deleted': 0,
        });
        await db.insert('suppliers', {
          'id': 's-$suffix',
          'name': 'Supplier $suffix',
          'phone': '',
          'email': '',
          'notes': '',
          'is_deleted': 0,
        });
      }

      expect(await repo.countCustomers(), 51);
      expect(await repo.countSuppliers(), 51);
      expect(
        await repo.listCustomers(limit: 50, offset: 50),
        hasLength(1),
      );
      expect(
        await repo.listSuppliers(limit: 50, offset: 50),
        hasLength(1),
      );
    });
  });
}
''')

# ---------------------------------------------------------------------------
# Mobile CI: Mobile PR/push must run the real Desktop integration suite against
# the exact Mobile code under test, and print both SHAs.
# ---------------------------------------------------------------------------
ci = text('.github/workflows/mobile-ci.yml')
if 'pair-regression:' not in ci:
    ci += r'''

  pair-regression:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - name: Checkout Mobile under integration path
        uses: actions/checkout@v4
        with:
          path: CNKH_POS_Mobile_APK

      - name: Checkout companion Desktop main
        uses: actions/checkout@v4
        with:
          repository: tyz11234/CNKH_POS_Desktop
          ref: main
          path: CNKH_POS_Desktop

      - name: Record exact companion SHAs
        shell: bash
        run: |
          set -euo pipefail
          echo "Mobile ref: ${GITHUB_REF}"
          echo "Mobile tested SHA: $(git -C CNKH_POS_Mobile_APK rev-parse HEAD)"
          echo "Mobile PR head SHA: ${GITHUB_HEAD_SHA:-n/a}"
          echo "Desktop ref: main"
          echo "Desktop tested SHA: $(git -C CNKH_POS_Desktop rev-parse HEAD)"

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Resolve pair-regression dependencies
        working-directory: CNKH_POS_Desktop/integration
        run: flutter pub get

      - name: Analyze pair-regression project
        working-directory: CNKH_POS_Desktop/integration
        run: flutter analyze --no-fatal-infos --no-fatal-warnings

      - name: Test HTTP sync, reconnect, idempotency, void and purchase sync
        working-directory: CNKH_POS_Desktop/integration
        run: flutter test
'''
write('.github/workflows/mobile-ci.yml', ci)

# ---------------------------------------------------------------------------
# README notes only describe implemented behavior; no unverified success claims.
# ---------------------------------------------------------------------------
readme = text('README.md')
marker = '## Large-list pagination and Release network verification'
if marker not in readme:
    readme += r'''

## Large-list pagination and Release network verification

- Product management, customer management, supplier management, stocktake and accumulated record pages use bounded pages instead of silently truncating later rows. Management/history pages use 50 rows per page; the checkout product strip uses 40 products per page.
- Product search and category filters are applied to the full active product set before LIMIT/OFFSET. Paging uses stable ID tie-breakers and keeps cart/business data unchanged.
- Manual purchase product selection opens a full-dataset searchable picker with 50 products per page. New manual-purchase quantity starts at `0`; the existing repository validation still requires a finite quantity greater than zero before inventory can change.
- OCR product matching no longer relies on a fixed 5000-product snapshot. Candidate ranking walks the product table in bounded pages, and OCR/manual matching UI uses the same full-dataset paged picker.
- `android/app/src/main/AndroidManifest.xml` explicitly declares `android.permission.INTERNET`. CI builds the Release APK; release permission inspection must be performed against the generated APK, not inferred from source text alone.
- Mobile CI also checks out the companion Desktop `main` source and runs `CNKH_POS_Desktop/integration`, logging the exact Desktop and Mobile SHAs used for the pair regression.
'''
write('README.md', readme)

print('pagination/release patch applied')
