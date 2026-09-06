import '../models/product.dart';

class ProductMatchCandidate {
  final Product product;
  final double confidence;
  final String source;

  const ProductMatchCandidate({
    required this.product,
    required this.confidence,
    required this.source,
  });
}

class ProductMatchService {
  const ProductMatchService();

  String normalizeName(String input) {
    var s = input.toLowerCase().trim();
    s = s
        .replaceAll(RegExp(r'\bctn\b'), ' carton ')
        .replaceAll(RegExp(r'\bpcs?\b'), ' pcs ')
        .replaceAll(RegExp(r'\bpk\b'), ' pack ')
        .replaceAll(RegExp(r'\bbtl\b'), ' bottle ');
    final chars = s.split('');
    for (var i = 1; i < chars.length - 1; i++) {
      final left = chars[i - 1];
      final right = chars[i + 1];
      final surroundedByLetters = _isLetter(left) && _isLetter(right);
      if (surroundedByLetters && chars[i] == '0') chars[i] = 'o';
      if (surroundedByLetters && chars[i] == '1') chars[i] = 'i';
    }
    s = chars.join();
    s = s.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff.]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  List<ProductMatchCandidate> rank(
    String rawName,
    List<Product> products, {
    int limit = 5,
  }) {
    final target = normalizeName(rawName);
    if (target.isEmpty) return const [];
    final candidates = <ProductMatchCandidate>[];
    for (final product in products) {
      final zh = normalizeName(product.nameZh);
      final en = normalizeName(product.nameEn);
      final sku = normalizeName(product.sku);
      final barcode = product.barcode.trim().toLowerCase();
      if (rawName.trim().toLowerCase() == barcode && barcode.isNotEmpty) {
        candidates.add(ProductMatchCandidate(
          product: product,
          confidence: 1,
          source: 'barcode',
        ));
        continue;
      }
      if (target == sku && sku.isNotEmpty) {
        candidates.add(ProductMatchCandidate(
          product: product,
          confidence: 0.995,
          source: 'sku',
        ));
        continue;
      }
      if (target == zh || target == en) {
        candidates.add(ProductMatchCandidate(
          product: product,
          confidence: 0.99,
          source: 'exact_name',
        ));
        continue;
      }
      final score = [similarity(target, zh), similarity(target, en)]
          .reduce((a, b) => a > b ? a : b);
      if (score >= 0.45) {
        candidates.add(ProductMatchCandidate(
          product: product,
          confidence: score,
          source: 'fuzzy_name',
        ));
      }
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(limit).toList();
  }

  double similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    final lev = 1 - dist / maxLen;
    final ta = a.split(' ').where((e) => e.isNotEmpty).toSet();
    final tb = b.split(' ').where((e) => e.isNotEmpty).toSet();
    final union = ta.union(tb).length;
    final token = union == 0 ? 0.0 : ta.intersection(tb).length / union;
    final contains = a.contains(b) || b.contains(a) ? 0.9 : 0.0;
    final score = [lev * 0.72 + token * 0.28, contains]
        .reduce((x, y) => x > y ? x : y);
    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _isLetter(String c) => RegExp(r'[a-zA-Z]').hasMatch(c);

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final replace = previous[j] + cost;
        current[j + 1] = [insert, delete, replace].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
