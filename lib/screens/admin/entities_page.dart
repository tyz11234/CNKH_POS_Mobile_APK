import 'package:flutter/material.dart';

import '../../db/app_database.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';
import '../../widgets/paged_list_footer.dart';

class EntitiesPage extends StatefulWidget {
  final PosRepository repo;
  final String kind; // customers | suppliers

  const EntitiesPage({super.key, required this.repo, required this.kind})
    : assert(kind == 'customers' || kind == 'suppliers');

  @override
  State<EntitiesPage> createState() => _EntitiesPageState();
}

class _EntitiesPageState extends State<EntitiesPage> {
  List<Object> _items = const [];
  final Set<String> _selected = <String>{};
  bool _selectMode = false;
  bool _busy = false;
  bool _loading = true;
  String? _loadError;
  static const _pageSize = 50;
  int _page = 0;
  bool _hasNext = false;
  int _loadVersion = 0;

  bool get _isCustomers => widget.kind == 'customers';
  String get _title => _isCustomers ? '客户 / Customers' : '供应商 / Suppliers';

  String _idOf(Object item) =>
      item is Customer ? item.id : (item as Supplier).id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
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
        _selected.removeWhere((id) => !_items.any((item) => _idOf(item) == id));
        if (_selected.isEmpty) _selectMode = false;
      });
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() => _loadError = '读取失败，请重试 / Could not load records');
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 0 || (delta > 0 && !_hasNext) || _busy || _loading) return;
    setState(() {
      _page = next;
      _selected.clear();
      _selectMode = false;
    });
    await _load();
  }

  Future<void> _edit([Object? existing]) async {
    if (_busy) return;
    final customer = existing is Customer ? existing : null;
    final supplier = existing is Supplier ? existing : null;
    final name = TextEditingController(
      text: customer?.name ?? supplier?.name ?? '',
    );
    final phone = TextEditingController(
      text: customer?.phone ?? supplier?.phone ?? '',
    );
    final extra = TextEditingController(
      text: _isCustomers ? (customer?.notes ?? '') : (supplier?.email ?? ''),
    );
    final notes = TextEditingController(text: supplier?.notes ?? '');
    String? nameError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? (_isCustomers ? '新增客户' : '新增供应商')
                : (_isCustomers ? '编辑客户' : '编辑供应商'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  onChanged: (_) {
                    if (nameError != null) setLocal(() => nameError = null);
                  },
                  decoration: InputDecoration(
                    labelText: '名称 / Name',
                    errorText: nameError,
                  ),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: '电话 / Phone'),
                ),
                TextField(
                  controller: extra,
                  decoration: InputDecoration(
                    labelText: _isCustomers ? '备注 / Notes' : 'Email',
                  ),
                ),
                if (!_isCustomers)
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: '备注 / Notes'),
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
                if (name.text.trim().isEmpty) {
                  setLocal(() => nameError = '名称不能为空');
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      if (_isCustomers) {
        await widget.repo.upsertCustomer(
          Customer(
            id: customer?.id ?? AppDatabase.newId(),
            name: name.text.trim(),
            phone: phone.text.trim(),
            notes: extra.text.trim(),
          ),
        );
      } else {
        await widget.repo.upsertSupplier(
          Supplier(
            id: supplier?.id ?? AppDatabase.newId(),
            name: name.text.trim(),
            phone: phone.text.trim(),
            email: extra.text.trim(),
            notes: notes.text.trim(),
          ),
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existing == null ? '已新增' : '已保存修改')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDelete(int count, {String? name}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(count == 1 ? '确认删除？' : '确认批量删除？'),
            content: Text(
              count == 1
                  ? '确定删除 ${name ?? ''} 吗？历史销售/进货记录不会被删除。'
                  : '确定删除所选的 $count 个${_isCustomers ? '客户' : '供应商'}吗？历史记录会继续保留。',
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

  Future<void> _deleteOne(Object item) async {
    if (_busy) return;
    final id = _idOf(item);
    final name = item is Customer ? item.name : (item as Supplier).name;
    if (!await _confirmDelete(1, name: name)) return;
    setState(() => _busy = true);
    try {
      if (_isCustomers) {
        await widget.repo.softDeleteCustomer(id);
      } else {
        await widget.repo.softDeleteSupplier(id);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList(growable: false);
    if (_busy || ids.isEmpty) return;
    if (!await _confirmDelete(ids.length)) return;
    setState(() => _busy = true);
    var deleted = 0;
    try {
      for (final id in ids) {
        if (_isCustomers) {
          await widget.repo.softDeleteCustomer(id);
        } else {
          await widget.repo.softDeleteSupplier(id);
        }
        deleted++;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已删除 $deleted 项')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已完成 $deleted 项；其余失败：$e'),
            backgroundColor: CnkhColors.danger,
          ),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(Object item) {
    final id = _idOf(item);
    setState(() {
      _selectMode = true;
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
        _selectMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(_items.map(_idOf));
        _selectMode = _selected.isNotEmpty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selected.length}' : _title),
        leading: _selectMode
            ? IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _selected.clear();
                        _selectMode = false;
                      }),
                icon: const Icon(Icons.close),
              )
            : null,
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
          ] else
            IconButton(
              tooltip: '新增',
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      bottomNavigationBar: PagedListFooter(
        page: _page,
        onPrevious: _page == 0 || _busy || _loading
            ? null
            : () => _changePage(-1),
        onNext: !_hasNext || _busy || _loading ? null : () => _changePage(1),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_loadError != null)
            ListLoadMessage(message: _loadError!, onRetry: _load)
          else if (_items.isEmpty)
            ListLoadMessage(
              message: _isCustomers
                  ? '暂无客户 / No customers'
                  : '暂无供应商 / No suppliers',
            )
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final item = _items[i];
                  final id = _idOf(item);
                  final selected = _selected.contains(id);
                  late final String title;
                  late final String subtitle;
                  if (item is Customer) {
                    title = item.name;
                    subtitle =
                        '${item.phone}${item.notes.isEmpty ? '' : '\n${item.notes}'}';
                  } else {
                    final supplier = item as Supplier;
                    title = supplier.name;
                    subtitle =
                        '${supplier.phone}${supplier.email.isEmpty ? '' : '\n${supplier.email}'}';
                  }
                  return ListTile(
                    leading: _selectMode
                        ? Checkbox(
                            value: selected,
                            onChanged: _busy ? null : (_) => _toggle(item),
                          )
                        : CircleAvatar(
                            child: Text(title.isEmpty ? '?' : title[0]),
                          ),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    selected: selected,
                    onLongPress: _busy ? null : () => _toggle(item),
                    onTap: _busy
                        ? null
                        : () {
                            if (_selectMode) {
                              _toggle(item);
                            } else {
                              _edit(item);
                            }
                          },
                    trailing: _selectMode
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') _edit(item);
                              if (action == 'delete') _deleteOne(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('编辑 / Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除 / Delete'),
                              ),
                            ],
                          ),
                  );
                },
              ),
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
