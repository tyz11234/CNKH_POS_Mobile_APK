from pathlib import Path

p = Path('lib/screens/admin/enhanced_purchases_page.dart')
s = p.read_text(encoding='utf-8')

old_supplier = """                  value: supplierRows.any((s) => s.id == supplier.id)
                      ? supplier
                      : null,
"""
new_supplier = """                  value: supplierRows.any((s) => s.id == supplier.id)
                      ? supplierRows.firstWhere((s) => s.id == supplier.id)
                      : null,
"""
old_product = """                  value: productRows.any((p) => p.id == product.id)
                      ? product
                      : null,
"""
new_product = """                  value: productRows.any((p) => p.id == product.id)
                      ? productRows.firstWhere((p) => p.id == product.id)
                      : null,
"""

if old_supplier not in s:
    raise SystemExit('supplier dropdown pattern not found')
if old_product not in s:
    raise SystemExit('product dropdown pattern not found')

s = s.replace(old_supplier, new_supplier, 1)
s = s.replace(old_product, new_product, 1)
p.write_text(s, encoding='utf-8')
