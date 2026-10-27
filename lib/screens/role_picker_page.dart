import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/cnkh_theme.dart';

/// First screen on the web: pick a role, then continue to that role's
/// PIN screen at /admin or /staff (see WebRoleGate).
class RolePickerPage extends StatelessWidget {
  final ValueChanged<AppRole> onPick;

  const RolePickerPage({super.key, required this.onPick});

  Widget _roleCard(
    BuildContext context, {
    required AppRole role,
    required IconData icon,
    required String titleZh,
    required String titleEn,
    required String desc,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onPick(role),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: CnkhColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 30, color: CnkhColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$titleZh / $titleEn',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: const TextStyle(
                        color: CnkhColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: CnkhColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [CnkhColors.deepNavy, CnkhColors.topBar, Color(0xFF123A66)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(
                        child: Text(
                          '◆',
                          style: TextStyle(color: Colors.white, fontSize: 34),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '黄金发宝号',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mobile Companion  ·  手机收银助手',
                      style: TextStyle(
                        color: Color(0xFFAFC2DB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      '请选择角色 / Select your role',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _roleCard(
                      context,
                      role: AppRole.admin,
                      icon: Icons.admin_panel_settings_outlined,
                      titleZh: '管理员',
                      titleEn: 'Admin',
                      desc: '店主 / 管理：全部功能与设置',
                    ),
                    const SizedBox(height: 12),
                    _roleCard(
                      context,
                      role: AppRole.staff,
                      icon: Icons.badge_outlined,
                      titleZh: '员工',
                      titleEn: 'Staff',
                      desc: '收银员：日常收银与销售',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '选择角色后再输入 PIN 登录\n'
                      'Pick a role first, then enter your PIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFC3D2E5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
