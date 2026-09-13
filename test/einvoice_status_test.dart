import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/einvoice/einvoice_status_store.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline sale remains intact, status is isolated by host and environment',()async{
    final dir=await Directory.systemTemp.createTemp('cnkh-einvoice-mobile-');
    final database=AppDatabase.forTesting('${dir.path}/pos.db',seed:true);
    try{
      final repo=PosRepository(database:database);
      const product=Product(id:'offline-ei',sku:'EI',barcode:'9550120001',nameZh:'测试',nameEn:'Test',priceCents:100,stock:3);
      await repo.upsertProduct(product);
      final sale=await repo.createSale(cart:CartState(items:[CartItem(product:product)]),paymentMethod:'CASH',paidCents:100,cashier:'staff');
      final db=await database.db,store=EInvoiceStatusStore(await database.db);
      final before=await db.query('sales');
      expect((await store.history('http://pc','production')).single['status'],'pending');
      final status={'document_id':'doc','sale_id':'desktop-id','client_sale_id':sale.id,'receipt_no':sale.receiptNo,'environment':'production','status':'validated','updated_at':'2026-09-13T00:00:00Z'};
      await store.replaceSnapshot('http://pc',[status]);
      expect((await store.history('http://pc','production')).single['status'],'validated');
      expect((await store.history('http://other','production')).single['status'],'pending');
      expect((await store.history('http://pc','sandbox')).single['status'],'pending');
      await expectLater(store.replaceSnapshot('http://pc',[{...status,'status':'bogus'}]),throwsFormatException);
      expect((await store.history('http://pc','production')).single['status'],'validated');
      expect(await db.query('sales'),before);
      expect(await db.query('sync_outbox'),isNotEmpty);
    }finally{await database.close();await dir.delete(recursive:true);}
  });
}
