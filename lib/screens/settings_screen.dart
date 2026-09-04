import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_user.dart';
import '../services/pos_repository.dart';
import '../services/qr_storage.dart';
import '../services/lan_sync.dart';
import '../services/e_receipt.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/receipt_template_editor.dart';
import 'training_page.dart';

class SettingsScreen extends StatefulWidget {
  final QrStorage qrStorage;
  final AppUser user;
  final PosRepository repo;

  const SettingsScreen({
    super.key,
    required this.qrStorage,
    required this.user,
    required this.repo,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _path;
  bool _loading = true;
  final _syncHost = TextEditingController();
  final _syncToken = TextEditingController();
  String _lastSync = '';
  bool _syncBusy = false;
  String _stockPolicy = 'warn';
  String _scanFeedback = 'beep';
  final _holdTimeout = TextEditingController(text: '30');
  final _lowStock = TextEditingController(text: '10');
  bool _btEnabled = false;
  bool _imagesEnabled = false;
  String _cachePathDisplay = '';
  String _cacheCustom = '';
  String _cacheDefault = '';
  bool _resetBusy = false;

  bool get canEdit => widget.user.canEditQr;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final p = await widget.qrStorage.getLocalPath();
    final host = await widget.repo.getSetting('lan_sync_host');
    final token = await widget.repo.getSetting('lan_sync_token');
    final last = await widget.repo.getSetting('lan_sync_last_full');
    final stock = await widget.repo.getSetting('stock_policy', fallback: 'warn');
    final holdMin =
        await widget.repo.getSetting('hold_timeout_minutes', fallback: '30');
    final scanFb =
        await widget.repo.getSetting('scan_feedback', fallback: 'beep');
    final thr =
        await widget.repo.getSetting('low_stock_threshold', fallback: '10');
    final bt = await widget.repo.btPrinterEnabled();
    final imgs = await widget.repo.productImagesEnabled();
    final custom =
        (await widget.repo.getSetting(kEReceiptCacheDirKey)).trim();
    final def = await defaultEReceiptCachePath();
    final active = await eReceiptCacheDir();
    if (!mounted) return;
    setState(() {
      _path = p;
      _syncHost.text = host;
      _syncToken.text = token;
      _lastSync = last;
      _stockPolicy = stock == 'block' ? 'block' : 'warn';
      _holdTimeout.text = holdMin;
      _scanFeedback =
          (scanFb == 'vibrate' || scanFb == 'mute') ? scanFb : 'beep';
      _lowStock.text = thr;
      _btEnabled = bt;
      _imagesEnabled = imgs;
      _cacheCustom = custom;
      _cacheDefault = def;
      _cachePathDisplay = active.path;
      _loading = false;
    });
  }

  Future<void> _pick() async {
    if (!canEdit) return;
    try {
      final picker = ImagePicker();
      final file =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (file == null) return;
      final saved = await widget.qrStorage.saveFromPicker(file.path);
      if (!mounted) return;
      setState(() => _path = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存本机 DuitNow QR')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导入失败: $e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _clear() async {
    if (!canEdit) return;
    await widget.qrStorage.clear();
    if (!mounted) return;
    setState(() => _path = null);
  }

  @override
  void dispose() {
    _syncHost.dispose();
    _syncToken.dispose();
    _holdTimeout.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  LanSyncConfig get _cfg => LanSyncConfig(
        baseUrl: _syncHost.text.trim(),
        token: _syncToken.text.trim(),
      );

  Future<void> _saveSyncCfg() async {
    await widget.repo.setSetting('lan_sync_host', _syncHost.text.trim());
    await widget.repo.setSetting('lan_sync_token', _syncToken.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('同步地址已保存 / Sync endpoint saved')),
    );
  }

  Future<void> _runSync(Future<String> Function(LanSyncClient c) op) async {
    if (_syncBusy) return;
    if (_cfg.normalizedBase.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写 PC IP:端口 / Enter PC host:port'),
          backgroundColor: CnkhColors.danger,
        ),
      );
      return;
    }
    setState(() => _syncBusy = true);
    try {
      await _saveSyncCfg();
      final client = LanSyncClient(widget.repo);
      final msg = await op(client);
      final last = await widget.repo.getSetting('lan_sync_last_full');
      if (!mounted) return;
      setState(() => _lastSync = last);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _pickCacheDir() async {
    if (!canEdit) return;
    try {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择电子收据缓存文件夹',
      );
      if (picked == null || picked.trim().isEmpty) return;
      await widget.repo.setSetting(kEReceiptCacheDirKey, picked.trim());
      // Ensure directory exists
      await Directory(picked.trim()).create(recursive: true);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('缓存目录已更新\n$picked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('选择失败: $e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _resetCacheDir() async {
    if (!canEdit) return;
    await widget.repo.setSetting(kEReceiptCacheDirKey, '');
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认缓存目录')),
    );
  }

  Future<void> _factoryReset() async {
    if (!canEdit || _resetBusy) return;
    final confirmCtrl = TextEditingController();
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠ 初始化 / 清空全部数据',
            style: TextStyle(color: CnkhColors.danger)),
        content: const Text(
          '将删除本机全部业务数据（销售、挂单、商品、客户、供应商、审计、设置等），'
          '并清空电子收据 PDF 缓存。\n\n'
          '完成后会重新载入演示种子数据与 demo 账号（admin / staff）。\n\n'
          '此操作不可撤销！',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('我了解风险，继续'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('最终确认 / Final confirm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '请输入「初始化」以确认清空：',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '初始化',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
            onPressed: () {
              if (confirmCtrl.text.trim() == '初始化') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    confirmCtrl.dispose();
    if (step2 != true || !mounted) return;

    setState(() => _resetBusy = true);
    try {
      await widget.repo.factoryResetLocalData();
      final deleted = await clearEReceiptCache();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已初始化本地数据，并清空 $deleted 个电子收据缓存'),
          backgroundColor: CnkhColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('初始化失败: $e'), backgroundColor: CnkhColors.danger),
      );
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _path != null && File(_path!).existsSync();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('设置 / Settings',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          canEdit ? '管理员可改收款码与小票格式' : '员工只读收款码与小票格式 · Staff view-only',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ReceiptTemplateEditor(repo: widget.repo, canEdit: canEdit),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('DuitNow 收款码',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: CnkhColors.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CnkhColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : has
                          ? Image.file(File(_path!), fit: BoxFit.contain)
                          : const Center(
                              child: Text('暂无图片',
                                  style: TextStyle(color: CnkhColors.muted))),
                ),
                const SizedBox(height: 12),
                if (canEdit) ...[
                  FilledButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册导入 / Import from gallery'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: has ? _clear : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除本机 QR / Clear local QR'),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CnkhColors.border),
                    ),
                    child: const Text(
                      '仅管理员可更改收款码\nOnly Admin can change payment QR',
                      style: TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('运营设置 / Ops',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('库存不足策略 / Stock gate',
                    style: Theme.of(context).textTheme.bodySmall),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('警告可继续 warn'),
                      selected: _stockPolicy == 'warn',
                      onSelected: widget.user.canEditQr
                          ? (_) async {
                              setState(() => _stockPolicy = 'warn');
                              await widget.repo
                                  .setSetting('stock_policy', 'warn');
                            }
                          : null,
                    ),
                    ChoiceChip(
                      label: const Text('阻止 block'),
                      selected: _stockPolicy == 'block',
                      onSelected: widget.user.canEditQr
                          ? (_) async {
                              setState(() => _stockPolicy = 'block');
                              await widget.repo
                                  .setSetting('stock_policy', 'block');
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _holdTimeout,
                  enabled: widget.user.canEditQr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '挂单超时提醒(分钟) / Hold timeout',
                    hintText: '30',
                  ),
                  onEditingComplete: () async {
                    await widget.repo.setSetting(
                      'hold_timeout_minutes',
                      _holdTimeout.text.trim().isEmpty
                          ? '30'
                          : _holdTimeout.text.trim(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text('扫码反馈 / Scan feedback',
                    style: Theme.of(context).textTheme.bodySmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in [
                      ('beep', '提示音'),
                      ('vibrate', '震动'),
                      ('mute', '静音')
                    ])
                      ChoiceChip(
                        label: Text(m.$2),
                        selected: _scanFeedback == m.$1,
                        onSelected: (_) async {
                          setState(() => _scanFeedback = m.$1);
                          await widget.repo.setSetting('scan_feedback', m.$1);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('缺货推送阈值 / Low-stock threshold',
                    style: Theme.of(context).textTheme.bodySmall),
                TextField(
                  controller: _lowStock,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '10'),
                  onEditingComplete: () async {
                    await widget.repo.setSetting(
                      'low_stock_threshold',
                      _lowStock.text.trim().isEmpty
                          ? '10'
                          : _lowStock.text.trim(),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('蓝牙小票机 / BT receipt printer'),
                  subtitle: const Text('默认关；失败不阻挡结账。Linux/桌面不可用。'),
                  value: _btEnabled,
                  onChanged: canEdit
                      ? (v) async {
                          setState(() => _btEnabled = v);
                          await widget.repo.setSetting(
                              'bt_printer_enabled', v ? '1' : '0');
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('商品图片 / Product images'),
                  subtitle: const Text('Admin 开启后才显示上传与缩略图'),
                  value: _imagesEnabled,
                  onChanged: canEdit
                      ? (v) async {
                          setState(() => _imagesEnabled = v);
                          await widget.repo.setSetting(
                              'product_images_enabled', v ? '1' : '0');
                        }
                      : null,
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const TrainingPage()),
                    );
                  },
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('培训 / Training（配对→扫码→发收据）'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('局域网同步 / LAN Sync',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  '同一 Wi‑Fi 连接电脑同步服务（无云端）。PC Admin → Settings → LAN Sync。',
                  style: TextStyle(color: CnkhColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _syncHost,
                  decoration: const InputDecoration(
                    labelText: 'PC 地址 / Host',
                    hintText: 'http://192.168.0.10:8787',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _syncToken,
                  decoration: const InputDecoration(
                    labelText: '密钥 / Token（可选）',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _lastSync.isEmpty
                      ? '尚未同步 / Never synced'
                      : '上次同步 / Last: $_lastSync',
                  style:
                      const TextStyle(fontSize: 12, color: CnkhColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _syncBusy ? null : _saveSyncCfg,
                      child: const Text('保存'),
                    ),
                    OutlinedButton(
                      onPressed: _syncBusy
                          ? null
                          : () => _runSync((c) async {
                                final h = await c.health(_cfg);
                                return 'OK · ${h['service']} · ${h['time']}';
                              }),
                      child: const Text('测试连接'),
                    ),
                    FilledButton(
                      onPressed: _syncBusy
                          ? null
                          : () => _runSync((c) => c.pullCatalog(_cfg)),
                      child: const Text('拉取商品'),
                    ),
                    FilledButton(
                      onPressed: _syncBusy
                          ? null
                          : () => _runSync((c) => c.pushSales(_cfg)),
                      child: const Text('推送销售'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: CnkhColors.navy),
                      onPressed: _syncBusy
                          ? null
                          : () => _runSync((c) => c.fullSync(_cfg)),
                      child: Text(_syncBusy ? '同步中…' : '强制全量对账'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          color: Color(0xFFFFF7E6),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'PC-only：条码标签硬件打印、Windows 备份/还原。请在桌面 Admin 使用。',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: Color(0xFF7A5A10)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('电子收据缓存 / E-receipt cache',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'PDF 缓存最多保留 7 天；发送后不立即删除。可自定义目录。',
                  style: TextStyle(color: CnkhColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CnkhColors.canvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CnkhColors.border),
                  ),
                  child: SelectableText(
                    _cachePathDisplay.isEmpty ? '…' : _cachePathDisplay,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
                if (_cacheCustom.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '自定义路径（默认: $_cacheDefault）',
                    style: const TextStyle(
                        fontSize: 11, color: CnkhColors.muted),
                  ),
                ],
                const SizedBox(height: 10),
                if (canEdit)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: CnkhColors.navy),
                        onPressed: _pickCacheDir,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择文件夹'),
                      ),
                      OutlinedButton(
                        onPressed: _cacheCustom.isEmpty ? null : _resetCacheDir,
                        child: const Text('恢复默认'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final n = await countEReceiptCache();
                          if (!context.mounted) return;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清空电子收据缓存？'),
                              content:
                                  Text('当前约 $n 个 PDF。清空后无法从本机重发旧缓存。'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('清空')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          final deleted = await clearEReceiptCache();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已删除 $deleted 个缓存 PDF')),
                          );
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清空缓存 PDF'),
                      ),
                    ],
                  )
                else
                  const Text('仅管理员可更改缓存目录',
                      style: TextStyle(color: CnkhColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFFFF1F1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('危险区域 / Danger zone',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: CnkhColors.danger,
                          )),
                  const SizedBox(height: 6),
                  const Text(
                    '初始化会清空本机 SQLite 业务数据与电子收据缓存，并重新载入演示种子。',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: CnkhColors.danger),
                    onPressed: _resetBusy ? null : _factoryReset,
                    icon: _resetBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.restart_alt),
                    label: Text(
                        _resetBusy ? '初始化中…' : '初始化 / 清空全部数据'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.info_outline, color: CnkhColors.primary),
            title: const Text('关于 / About'),
            subtitle: const Text(
                'CNKH POS Mobile 1.6.0 · Receipt template · 黄金发宝号'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'CNKH POS Mobile',
              applicationVersion: '1.6.0',
              applicationLegalese: '黄金发宝号 companion',
            ),
          ),
        ),
      ],
    );
  }
}
