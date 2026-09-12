import 'package:flutter/material.dart';
import '../theme/cnkh_theme.dart';

class TrainingPage extends StatelessWidget {
  const TrainingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final steps = <(String, IconData, String)>[
      ('1. 配对 / Pair', Icons.qr_code_2,
          'PC 顶栏「同步/配对」显示二维码。\n手机 AppBar「扫码配对」扫描。\n同一 Wi‑Fi；配对码约 7 分钟有效。'),
      ('2. 扫码 / Scan', Icons.qr_code_scanner,
          '收银页「扫码加购」。\n对准条码/QR → 加购 1 件。\n也可扫电脑配对码。'),
      ('3. 发收据 / E-receipt', Icons.picture_as_pdf,
          '结账成功后点「电子收据 PDF」。\n分享 PDF 到 WhatsApp。\n销售列表可重发。'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('培训 / Training')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('三步上手 / 3-step guide',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('配对 → 扫码 → 发收据', style: TextStyle(color: CnkhColors.muted)),
          const SizedBox(height: 16),
          for (final s in steps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: CnkhColors.softBlue,
                      child: Icon(s.$2, color: CnkhColors.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(s.$3, style: const TextStyle(height: 1.4)),
                        ],
                      ),
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
