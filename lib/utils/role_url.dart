/// Reads and changes the role segment of the browser URL (web only).
/// Returns null / does nothing on non-web platforms.
library;

export 'role_url_stub.dart'
    if (dart.library.html) 'role_url_web.dart';
