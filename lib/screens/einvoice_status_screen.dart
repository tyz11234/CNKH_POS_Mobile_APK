import 'package:flutter/material.dart';
import '../services/pos_repository.dart';
import '../services/lan_sync.dart';
import '../services/einvoice/einvoice_status_store.dart';
class EInvoiceStatusScreen extends StatefulWidget {
  const EInvoiceStatusScreen({super.key, required this.repo});
  final PosRepository repo;
  @override State<EInvoiceStatusScreen> createState() => _EInvoiceStatusScreenState();
}
class _EInvoiceStatusScreenState extends State<EInvoiceStatusScreen> {
  String environment = 'production', message = '';
  List<Map<String, Object?>> rows = [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final base = await widget.repo.getSetting('lan_sync_host');
      final host = LanSyncConfig(baseUrl: base).normalizedBase;
      rows = await EInvoiceStatusStore(await widget.repo.database.db).history(host, environment);
      message = await widget.repo.getSetting('einvoice_status_sync_error');
    } catch (_) { message = '状态读取失败，请重试'; }
    if (mounted) setState(() {});
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('e-Invoice 状态'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]), body: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('手机离线销售会保留 Pending。连接电脑并完成 LAN 同步后，由电脑提交 e-Invoice，状态同步回手机。此处显示最后一次同步结果。'),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(initialValue: environment, items: const [DropdownMenuItem(value: 'production', child: Text('Production 正式')), DropdownMenuItem(value: 'sandbox', child: Text('Sandbox 测试'))], onChanged: (v) { environment = v!; _load(); }),
    if (message.isNotEmpty) Text(message),
    for (final row in rows) Card(child: ListTile(title: Text('${row['receipt_no']}'), subtitle: Text('${row['updated_at'] ?? '等待 Desktop 处理'}${row['voided'] == 1 ? '\n销售已作废，请向管理员核对 e-Invoice' : ''}'), trailing: Text({'pending':'Pending','submitting':'Pending · 核对中','submitted':'Submitted','validated':'Validated','rejected':'Rejected','cancelled':'Cancelled','needs_review':'待核对'}[row['status']] ?? '${row['status']}'))),
  ]));
}
