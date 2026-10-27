// ignore_for_file: deprecated_member_use

library;

import 'dart:html' as html;

const _roleSlugs = {'admin', 'staff'};

/// Returns the trailing role segment of the current path
/// (for example "admin" for /admin or /app/admin), or null.
String? roleSlugFromUrl() {
  final path = html.window.location.pathname ?? '/';
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  final last = segments.last.toLowerCase();
  return _roleSlugs.contains(last) ? last : null;
}

String _basePath() {
  final path = html.window.location.pathname ?? '/';
  return (path == '/app' || path.startsWith('/app/')) ? '/app' : '';
}

/// Points the browser URL at /<slug> (or back to the root when slug is
/// null) without reloading the page, preserving an /app prefix.
void navigateToRoleSlug(String? slug) {
  final base = _basePath();
  final target = slug == null ? (base.isEmpty ? '/' : '$base/') : '$base/$slug';
  html.window.history.pushState(null, '', target);
}

/// Calls [callback] whenever the user navigates with Back / Forward.
void addRolePopStateListener(void Function() callback) {
  html.window.onPopState.listen((_) => callback());
}
