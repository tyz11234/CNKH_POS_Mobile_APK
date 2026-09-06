from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    s = read(path)
    if old not in s:
        raise RuntimeError(f'expected text not found: {path}')
    write(path, s.replace(old, new, 1))


# Fix the only syntax error introduced by the pagination patch.
legacy = 'lib/screens/admin/admin_hub_legacy.dart'
s = read(legacy)
bad = """                              '${a.occurredAt.replaceFirst('T', ' ').substring(0, 19)}
'
"""
good = r"""                              '${a.occurredAt.replaceFirst('T', ' ').substring(0, 19)}\n'
"""
if bad not in s:
    raise RuntimeError('audit newline syntax pattern not found')
write(legacy, s.replace(bad, good, 1))

# Remove the old in-memory sales filter now that filtering is SQL-backed.
sales = 'lib/screens/sales_list_screen.dart'
s = read(sales)
s, n = re.subn(
    r"\n  bool _match\(SaleRecord s, String q\) \{.*?\n  Future<void> _pickFrom",
    "\n  Future<void> _pickFrom",
    s,
    count=1,
    flags=re.S,
)
if n != 1:
    raise RuntimeError('unused sales _match method not found')
write(sales, s)

# Make release permission verification permanent in normal Mobile CI.
workflow = '.github/workflows/mobile-ci.yml'
s = read(workflow)
anchor = """      - name: Build Android release APK
        run: flutter build apk --release

      - name: Stage APKs
"""
verify = """      - name: Build Android release APK
        run: flutter build apk --release

      - name: Verify Release INTERNET permission and identity
        shell: bash
        run: |
          set -euo pipefail
          echo "Mobile source SHA: $(git rev-parse HEAD)"
          grep '^version:' pubspec.yaml
          apk='build/app/outputs/flutter-apk/app-release.apk'
          test -f "$apk"

          manifest=$(find build/app/intermediates \
            \( -path '*merged_manifest*release*AndroidManifest.xml' \
               -o -path '*merged_manifests*release*AndroidManifest.xml' \) \
            -print | head -n 1 || true)
          if [ -z "$manifest" ]; then
            echo 'Release merged AndroidManifest.xml not found' >&2
            exit 1
          fi
          echo "Merged manifest: $manifest"
          grep -n 'android.permission.INTERNET' "$manifest"

          sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
          tool=$(find "$sdk_root/build-tools" -type f -name aapt 2>/dev/null | sort -V | tail -n 1 || true)
          if [ -z "$tool" ]; then
            echo 'aapt not found in Android SDK build-tools' >&2
            exit 1
          fi
          echo "Permission tool: $tool"
          "$tool" dump permissions "$apk" | tee /tmp/apk-permissions.txt
          grep -q 'android.permission.INTERNET' /tmp/apk-permissions.txt
          sha256sum "$apk" | tee /tmp/app-release.sha256

      - name: Stage APKs
"""
if anchor not in s:
    raise RuntimeError('Mobile CI build anchor not found')
write(workflow, s.replace(anchor, verify, 1))
