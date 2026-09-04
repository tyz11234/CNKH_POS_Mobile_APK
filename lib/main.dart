import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_user.dart';
import 'models/cart_item.dart';
import 'screens/admin/admin_hub.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/login_screen.dart';
import 'screens/sales_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/pos_repository.dart';
import 'db/app_database.dart';
import 'services/qr_storage.dart';
import 'theme/cnkh_theme.dart';
import 'widgets/e_receipt_actions.dart';
import 'services/bluetooth_printer.dart';
import 'services/lan_sync.dart';
import 'services/e_receipt.dart';
import 'screens/barcode_scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppDatabase.ensureFfi();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Fire-and-forget: drop e-receipt PDFs older than 7 days
  purgeEReceiptCache();
  runApp(const CnkhPosMobileApp());
}

class CnkhPosMobileApp extends StatelessWidget {
  const CnkhPosMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CNKH POS Mobile',
      debugShowCheckedModeBanner: false,
      theme: buildCnkhTheme(),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AppUser? _user;
  final _qr = QrStorage();
  final _repo = PosRepository();

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return LoginScreen(onLoggedIn: (u) => setState(() => _user = u));
    }
    return HomeShell(
      user: user,
      qrStorage: _qr,
      repo: _repo,
      onLogout: () => setState(() => _user = null),
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppUser user;
  final QrStorage qrStorage;
  final PosRepository repo;
  final VoidCallback onLogout;

  const HomeShell({
    super.key,
    required this.user,
    required this.qrStorage,
    required this.repo,
    required this.onLogout,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _dataEpoch = 0; // bumps → Today sales / admin lists refresh
  final CartState _cart = CartState();
  late final LanSyncClient _syncClient = LanSyncClient(widget.repo);
  late final LanLiveSync _live = LanLiveSync(_syncClient);
  SyncLinkState _linkState = SyncLinkState.offline;
  int _pending = 0;
  int _overdueHolds = 0;
  Timer? _holdPoll;

  @override
  void initState() {
    super.initState();
    _live.onRemoteChange = _bumpData;
    _live.onLowStock = (event) {
      if (!mounted) return;
      final name = (event['name'] ?? event['sku'] ?? '商品').toString();
      final stock = event['stock'];
      final thr = event['threshold'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('缺货提醒 / Low stock: $name (库存 $stock ≤ $thr)'),
          backgroundColor: const Color(0xFFB26A00),
          duration: const Duration(seconds: 4),
          action: widget.user.isAdmin
              ? SnackBarAction(
                  label: '商品',
                  textColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      // Admin tab index: POS=0 Today=1 Admin=2 Settings=3
                      _tab = 2;
                    });
                  },
                )
              : null,
        ),
      );
    };
    _live.onStatusChanged = (state, pending) {
      if (!mounted) return;
      setState(() {
        _linkState = state;
        _pending = pending;
      });
    };
    _tryAutoConnect();
    _refreshOverdueHolds();
    // poll held-order age every 60s
    _holdPoll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      _refreshOverdueHolds();
    });
  }

  Future<void> _refreshOverdueHolds() async {
    final mins = await widget.repo.holdTimeoutMinutes();
    final list = await widget.repo.listOverdueHeld(
      cashier: widget.user.username,
      timeoutMinutes: mins,
    );
    if (!mounted) return;
    setState(() => _overdueHolds = list.length);
  }

  @override
  void dispose() {
    _holdPoll?.cancel();
    _live.disconnect();
    super.dispose();
  }

  Future<void> _tryAutoConnect() async {
    final cfg = await _syncClient.loadConfig();
    if (cfg == null) return;
    try {
      await _live.connect(cfg);
    } catch (_) {}
  }

  Future<void> _applyPairing(LanSyncConfig cfg) async {
    try {
      await _live.connect(cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已配对 ${cfg.name} · ${cfg.normalizedBase}'),
          backgroundColor: CnkhColors.success,
        ),
      );
      _bumpData();
    } catch (e) {
      if (!mounted) return;
      final err = _syncClient.lastError ?? '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('配对/同步失败: $err'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    }
  }

  Future<void> _pairByQr() async {
    final cfg = await Navigator.of(context).push<LanSyncConfig>(
      MaterialPageRoute(
        builder: (_) => BarcodeScanScreen(
          repo: widget.repo,
          pairingOnly: true,
        ),
      ),
    );
    if (cfg == null || !mounted) return;
    await _applyPairing(cfg);
  }

  Future<void> _forceReconcile() async {
    try {
      final msg = await _live.forceReconcile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('强制全量对账完成\n$msg'), backgroundColor: CnkhColors.success),
      );
      _bumpData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('对账失败 / Reconcile failed: ${_syncClient.lastError ?? e}'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    }
  }

  Color get _statusDotColor => switch (_linkState) {
        SyncLinkState.connected => const Color(0xFF69F0AE),
        SyncLinkState.pending => const Color(0xFFFFB300),
        SyncLinkState.offline => const Color(0xFF9E9E9E),
      };

  void _bumpData() {
    if (!mounted) return;
    setState(() => _dataEpoch++);
  }

  List<_Nav> get _navs {
    final list = <_Nav>[
      _Nav('收银 POS', Icons.point_of_sale, Icons.point_of_sale_outlined),
      _Nav('今日 Today', Icons.receipt_long, Icons.receipt_long_outlined),
      _Nav('设置 Settings', Icons.settings, Icons.settings_outlined),
    ];
    if (widget.user.isAdmin) {
      list.insert(2, _Nav('管理 Admin', Icons.admin_panel_settings, Icons.admin_panel_settings_outlined));
    }
    return list;
  }

  Future<void> _checkout() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          cart: _cart,
          user: widget.user,
          qrStorage: widget.qrStorage,
          repo: widget.repo,
          onCancel: () => Navigator.of(context).pop(),
          onPaid: (sale) async {
            Navigator.of(context).pop();
            setState(() {
              _cart.items.clear();
              _cart.orderDiscountCents = 0;
              _dataEpoch++; // sync Today sales immediately
            });
            // Near-real-time: push sale to PC if paired
            // ignore: unawaited_futures
            _live.onLocalSale(sale);
            // Optional BT print — never blocks checkout
            // ignore: unawaited_futures
            () async {
              try {
                final bt = BluetoothPrinterService(widget.repo);
                if (!await bt.enabled()) return;
                final msg = await bt.tryPrintSale(sale);
                if (!mounted || msg == 'bt_off' || msg == 'ok') return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              } catch (_) {}
            }();
            await showSaleSuccessSheet(
              context,
              sale: sale,
              repo: widget.repo,
            );
          },
        ),
      ),
    );
  }

  Future<void> _hold() async {
    try {
      final held = await widget.repo.holdCart(
        cart: _cart,
        cashier: widget.user.username,
      );
      setState(() {
        _cart.items.clear();
        _cart.orderDiscountCents = 0;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已挂单 ${held.holdNo}')),
      );
      await _refreshOverdueHolds();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _resume() async {
    final list = await widget.repo.listHeld(cashier: widget.user.username);
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无挂单 / No held orders')),
      );
      return;
    }
    final timeout = await widget.repo.holdTimeoutMinutes();
    final cutoff = DateTime.now().subtract(Duration(minutes: timeout));
    final selected = await showDialog<HeldOrder>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_overdueHolds > 0
            ? '取单 / Resume（超时 $_overdueHolds）'
            : '取单 / Resume'),
        children: [
          for (final h in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text(
                '${h.holdNo} · ${h.heldAt.substring(0, 16).replaceFirst('T', ' ')}'
                '${(DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true) ? '  ⚠超时' : ''}',
                style: TextStyle(
                  color: (DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true)
                      ? const Color(0xFFB26A00)
                      : null,
                  fontWeight: (DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true)
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final restored = await widget.repo.resumeHeld(selected);
    setState(() {
      _cart.items
        ..clear()
        ..addAll(restored.items);
      _cart.orderDiscountCents = restored.orderDiscountCents;
    });
    await _refreshOverdueHolds();
  }

  Future<void> _openOverdueHolds() async {
    setState(() => _tab = 0);
    await _resume();
  }

  @override
  Widget build(BuildContext context) {
    final navs = _navs;
    final pages = <Widget>[
      CartScreen(
        cart: _cart,
        user: widget.user,
        repo: widget.repo,
        onChanged: () => setState(() {}),
        onCheckout: _checkout,
        onHold: _hold,
        onResume: _resume,
        onPairing: (cfg) {
          Navigator.of(context).pop(); // close scanner
          _applyPairing(cfg);
        },
      ),
      SalesListScreen(
        repo: widget.repo,
        todayOnly: true,
        refreshToken: _dataEpoch,
      ),
      if (widget.user.isAdmin)
        AdminHub(
          user: widget.user,
          repo: widget.repo,
          onDataChanged: _bumpData,
        ),
      SettingsScreen(
        qrStorage: widget.qrStorage,
        user: widget.user,
        repo: widget.repo,
      ),
    ];

    final safeTab = _tab.clamp(0, pages.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('黄金发宝号'),
            Text(
              '${widget.user.roleBadge} · ${navs[safeTab].label}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFFC3D2E5),
              ),
            ),
          ],
        ),
        actions: [
          if (_overdueHolds > 0)
            IconButton(
              tooltip: '挂单超时 / Held overdue',
              onPressed: _openOverdueHolds,
              icon: Badge(
                label: Text('$_overdueHolds'),
                backgroundColor: const Color(0xFFFFB300),
                child: const Icon(Icons.pause_circle_filled, color: Color(0xFFFFB300)),
              ),
            ),
          IconButton(
            tooltip: '强制全量对账 / Force reconcile',
            onPressed: _forceReconcile,
            icon: const Icon(Icons.sync),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: '扫码配对 / Scan to pair',
                onPressed: _pairByQr,
                icon: const Icon(Icons.qr_code_scanner),
              ),
              Positioned(
                right: 8,
                top: 10,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusDotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
              if (_pending > 0)
                Positioned(
                  right: 4,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_pending',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.user.isAdmin
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF455A64),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.user.isAdmin ? 'Admin' : 'Staff',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '退出 / Logout',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: safeTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            // Always refresh Today when user opens that tab
            if (i == 1) _dataEpoch++;
          });
        },
        destinations: [
          for (final n in navs)
            NavigationDestination(
              icon: Icon(n.outline),
              selectedIcon: Icon(n.filled),
              label: n.label,
            ),
        ],
      ),
    );
  }
}

class _Nav {
  final String label;
  final IconData filled;
  final IconData outline;
  _Nav(this.label, this.filled, this.outline);
}
