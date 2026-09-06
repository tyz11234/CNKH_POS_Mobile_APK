from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding='utf-8')


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
