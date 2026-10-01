import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_mobile/models/product.dart';
import 'package:cnkh_pos_mobile/models/purchase_ocr.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/purchase_invoice_parser.dart';
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F06 real parser, preparation, saves, reopen and later commit keep distinct stable IDs', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-ocr-identities-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    final ocr = PurchaseOcrRepository(repo);
    try {
      await repo.upsertProduct(const Product(id: 'p', nameZh: 'Coca Cola', nameEn: 'Coca Cola',
        sku: 'CC', barcode: '10001', priceCents: 500, costCents: 300, stock: 10));
      await repo.upsertSupplier(const Supplier(id: 'supplier', name: 'ABC Trading'));
      final original = await File('${temp.path}/original.jpg').writeAsBytes([1,2,3,4]);
      Future<PurchaseDraft> parse(String id) async => ocr.prepareDraft(
        const PurchaseInvoiceParser().parse('ABC Trading\nInvoice No: INV-$id\nCoca Cola 2 PCS 3.00 6.00\nGrand Total 6.00',
          draftId: id, createdBy: 'admin').copyWith(originalImagePath: original.path));
      final first = await parse('one');
      final second = await parse('two');
      expect(first.lines.single.id, isNot(second.lines.single.id));
      await ocr.saveDraft(first); await ocr.saveDraft(second); await ocr.saveDraft(first);
      expect((await ocr.loadDraft('one'))!.lines.single.id, first.lines.single.id);
      expect((await ocr.loadDraft('two'))!.lines.single.id, second.lines.single.id);
      final purchase = await ocr.commitDraft(first, operator: 'admin');
      expect(await ocr.commitDraft(first, operator: 'admin'), purchase);
      final third = await parse('three');
      await ocr.saveDraft(third); await ocr.saveDraft(third);
      final db = await database.db;
      expect(await db.query('purchase_draft_lines'), hasLength(3));
      expect(await db.query('purchase_attachments'), hasLength(1));
      expect(await db.query('purchase_commit_keys'), hasLength(1));
      expect(await db.query('supplier_product_aliases'), isNotEmpty);
      // Preserve legacy IDs and attachments; no rewrite of old draft identity.
      await db.update('purchase_draft_lines', {'id': 'ocr-line-2'},
          where: 'draft_id=?', whereArgs: ['two']);
      await db.execute('PRAGMA user_version = 9'); await database.close();
      final upgraded = await database.db;
      await ensureOcrPurchaseSchema(upgraded); await ensureOcrPurchaseSchema(upgraded);
      final old = (await ocr.loadDraft('two'))!;
      expect(old.lines.single.id, 'ocr-line-2');
      expect(old.originalImagePath, original.path);
      await ocr.saveDraft(old);
      await ocr.saveDraft(await parse('four'));
      expect(await upgraded.query('purchase_draft_lines'), hasLength(4));
      expect(await upgraded.query('purchase_commit_keys'), hasLength(1));
      expect(await upgraded.query('purchase_attachments'), hasLength(1));
      expect((await repo.getProduct('p'))!.stock, 12);
    } finally { await database.close(); await temp.delete(recursive: true); }
  });
}
