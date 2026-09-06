import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PurchaseInvoiceImageStore {
  const PurchaseInvoiceImageStore();

  Future<String> saveCompressed(String sourcePath, String draftId) async {
    final bytes = await File(sourcePath).readAsBytes();
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
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'purchase_invoices'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final path = p.join(folder.path, '$draftId.jpg');
    await File(path).writeAsBytes(img.encodeJpg(decoded, quality: 82), flush: true);
    return path;
  }

  Future<void> deleteIfExists(String path) async {
    if (path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
