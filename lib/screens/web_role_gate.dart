import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/pos_repository.dart';
import '../utils/role_url.dart';
import 'login_screen.dart';
import 'role_picker_page.dart';

/// Web entry gate: the root address first shows a role picker; picking a
/// role moves the browser URL to /admin or /staff and only then shows
/// that role's PIN login. A direct visit to /admin or /staff goes
/// straight to the PIN screen. On non-web platforms this is exactly the
/// classic LoginScreen.
class WebRoleGate extends StatefulWidget {
  final PosRepository repo;
  final ValueChanged<AppUser> onLoggedIn;

  const WebRoleGate({super.key, required this.repo, required this.onLoggedIn});

  @override
  State<WebRoleGate> createState() => _WebRoleGateState();
}

class _WebRoleGateState extends State<WebRoleGate> {
  AppRole? _role;

  static AppRole? _roleFromSlug(String? slug) {
    if (slug == 'admin') return AppRole.admin;
    if (slug == 'staff') return AppRole.staff;
    return null;
  }

  static String _slugFor(AppRole role) =>
      role == AppRole.admin ? 'admin' : 'staff';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _role = _roleFromSlug(roleSlugFromUrl());
      addRolePopStateListener(() {
        if (!mounted) return;
        setState(() => _role = _roleFromSlug(roleSlugFromUrl()));
      });
    }
  }

  void _pick(AppRole role) {
    navigateToRoleSlug(_slugFor(role));
    setState(() => _role = role);
  }

  void _backToPicker() {
    navigateToRoleSlug(null);
    setState(() => _role = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return LoginScreen(repo: widget.repo, onLoggedIn: widget.onLoggedIn);
    }
    final role = _role;
    if (role == null) {
      return RolePickerPage(onPick: _pick);
    }
    return LoginScreen(
      repo: widget.repo,
      onLoggedIn: widget.onLoggedIn,
      fixedRole: role,
      onChangeRole: _backToPicker,
    );
  }
}
