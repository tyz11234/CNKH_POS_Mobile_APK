library;

/// Non-web platforms have no URL: no role is ever pre-selected.
String? roleSlugFromUrl() => null;

/// Non-web platforms have no URL to change.
void navigateToRoleSlug(String? slug) {}

/// Non-web platforms have no history events.
void addRolePopStateListener(void Function() callback) {}
