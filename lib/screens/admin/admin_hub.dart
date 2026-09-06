import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';
import '../sales_list_screen.dart';
import 'admin_hub_legacy.dart' as legacy;
import 'enhanced_purchases_page.dart';
import 'products_admin.dart';

export 'admin_hub_legacy.dart'
    show
        DashboardPage,
        EntitiesPage,
        PurchasesPage,
        StocktakePage,
        UsersPage,
        ReportsPage,
        DailyClosePage,
        MaintenancePage,
        AuditLogPage;

class AdminHub extends StatelessWidget {
  final AppUser user;
  final PosRepository repo;
  final VoidCallback? onDataChanged;

  const AdminHub({
    super.key,
    required this.user,
    required this.repo,
    this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <_Tile>[
      _Tile('主页 Dashboard', Icons.dashboard_outlined,
          () => _open(context, legacy.DashboardPage(repo: repo))),
      _Tile('商品 Products', Icons.inventory_2_outlined,
          () => _open(context, ProductsAdminPage(repo: repo, user: user))),
      _Tile('分类 Categories', Icons.category_outlined,
          () => _open(context, CategoriesAdminPage(repo: repo))),
      _Tile('条码队列 Barcode Queue', Icons.qr_code_2,
          () => _open(context, BarcodeQueuePage(repo: repo))),
      _Tile(
        '销售 Sales',
        Icons.receipt_long,
        () => _open(
          context,
          Scaffold(
            appBar: AppBar(title: const Text('销售记录 / Sales')),
            body: SalesListScreen(
              repo: repo,
              todayOnly: false,
              canVoid: true,
            ),
          ),
        ),
      ),
      _Tile('客户 Customers', Icons.people_outline,
          () => _open(context, legacy.EntitiesPage(repo: repo, kind: 'customers'))),
      _Tile('供应商 Suppliers', Icons.local_shipping_outlined,
          () => _open(context, legacy.EntitiesPage(repo: repo, kind: 'suppliers'))),
      _Tile(
        '进货 Purchases',
        Icons.shopping_bag_outlined,
        () => _open(
          context,
          EnhancedPurchasesPage(repo: repo, user: user),
        ),
      ),
      _Tile('盘点 Stocktake', Icons.fact_check_outlined,
          () => _open(context, legacy.StocktakePage(repo: repo, user: user))),
      _Tile('员工 Users', Icons.badge_outlined,
          () => _open(context, legacy.UsersPage(repo: repo))),
      _Tile('报表 Reports', Icons.bar_chart,
          () => _open(context, legacy.ReportsPage(repo: repo))),
      _Tile('日结 Daily Close', Icons.point_of_sale,
          () => _open(context, legacy.DailyClosePage(repo: repo, user: user))),
      _Tile('维护 Maintenance', Icons.build_outlined,
          () => _open(context, legacy.MaintenancePage(repo: repo))),
      _Tile('折扣审计 Audit', Icons.history,
          () => _open(context, legacy.AuditLogPage(repo: repo))),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('管理 / Admin', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        const Text(
          '本地演示数据 · Local-first parity screens',
          style: TextStyle(color: CnkhColors.muted),
        ),
        const SizedBox(height: 12),
        ...tiles.map(
          (tile) => Card(
            child: ListTile(
              leading: Icon(tile.icon, color: CnkhColors.primary),
              title: Text(
                tile.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: tile.onTap,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Card(
          color: Color(0xFFFFF7E6),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'PC-only（本版不做）：条码标签硬件打印、Windows 备份/还原二进制格式。\n'
              'PC-only: barcode label hardware printing; Windows backup/restore binary format.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFF7A5A10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) {
      onDataChanged?.call();
    });
  }
}

class _Tile {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  _Tile(this.title, this.icon, this.onTap);
}
