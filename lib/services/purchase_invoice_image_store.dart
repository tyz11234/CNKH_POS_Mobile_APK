import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PurchaseInvoiceImages {
  final String originalPath;
  final String previewPath;

  const PurchaseInvoiceImages({
    required this.originalPath,
    required this.previewPath,
  });
}

class PurchaseInvoiceImageStore {
  const PurchaseInvoiceImageStore();

  Future<Directory> _root() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'purchase_invoices'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  String _safeExtension(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,6}$').hasMatch(ext)) return ext;
    return '.img';
  }

  /// Copies the picked invoice byte-for-byte. This is the audit/OCR source and
  /// must never be resized, re-oriented or JPEG re-encoded.
  Future<String> saveOriginal(String sourcePath, String draftId) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('进货单原图不存在');
    final root = await _root();
    final folder = Directory(p.join(root.path, 'original'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final destination = File(
      p.join(folder.path, '$draftId${_safeExtension(sourcePath)}'),
    );
    await source.copy(destination.path);
    return destination.path;
  }

  /// Creates the UI preview from the preserved original. OCR must use the
  /// original path instead of this compressed copy.
  Future<String> savePreview(String originalPath, String draftId) async {
    final bytes = await File(originalPath).readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) throw StateError('无法读取进货单图片');
    decoded = img.bakeOrientation(decoded);
    const maxSide = 1800;
    if (decoded.width > maxSide || decoded.height > maxSide) {
      final landscape = decoded.width >= decoded.height;
      decoded = img.copyResize(
        decoded,
        width: landscape ? maxSide : null,
        height: landscape ? null : maxSide,
        interpolation: img.Interpolation.average,
      );
    }
    final root = await _root();
    final folder = Directory(p.join(root.path, 'preview'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final path = p.join(folder.path, '$draftId.jpg');
    await File(path).writeAsBytes(
      img.encodeJpg(decoded, quality: 82),
      flush: true,
    );
    return path;
  }

  Future<PurchaseInvoiceImages> saveOriginalAndPreview(
    String sourcePath,
    String draftId,
  ) async {
    final original = await saveOriginal(sourcePath, draftId);
    try {
      final preview = await savePreview(original, draftId);
      return PurchaseInvoiceImages(
        originalPath: original,
        previewPath: preview,
      );
    } catch (_) {
      await deleteIfExists(original);
      rethrow;
    }
  }

  /// Backwards-compatible helper for older call sites. New OCR flows should use
  /// saveOriginalAndPreview and recognize the returned originalPath.
  Future<String> saveCompressed(String sourcePath, String draftId) async {
    final images = await saveOriginalAndPreview(sourcePath, draftId);
    return images.previewPath;
  }

  Future<void> deleteIfExists(String path) async {
    if (path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> deletePair({
    required String originalPath,
    required String previewPath,
  }) async {
    await deleteIfExists(previewPath);
    if (originalPath != previewPath) await deleteIfExists(originalPath);
  }
}
