import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart';
import 'package:cnkh_pos_mobile/models/app_user.dart';
import 'package:cnkh_pos_mobile/models/cart_item.dart';
import 'package:cnkh_pos_mobile/services/pos_repository.dart';
import 'package:cnkh_pos_mobile/services/qr_storage.dart';
import 'package:cnkh_pos_mobile/screens/login_screen.dart';
import 'package:cnkh_pos_mobile/screens/cart_screen.dart';
import 'package:cnkh_pos_mobile/screens/checkout_screen.dart';
import 'package:cnkh_pos_mobile/screens/sales_list_screen.dart';
import 'package:cnkh_pos_mobile/screens/settings_screen.dart';
import 'package:cnkh_pos_mobile/screens/barcode_scan_screen.dart';
import 'package:cnkh_pos_mobile/screens/admin/admin_hub.dart';
import 'package:cnkh_pos_mobile/screens/einvoice_status_screen.dart';
import 'package:cnkh_pos_mobile/theme/cnkh_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase db;
  late PosRepository repo;
  const user=AppUser(username:'admin',role:AppRole.admin,displayName:'Training');
  const product=Product(id:'training-product',sku:'TRAINING',barcode:'955123000002',nameZh:'培训商品',nameEn:'Training Product',priceCents:1250,stock:20);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp=await Directory.systemTemp.createTemp('cnkh-training-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_)async=>temp.path);
    db=AppDatabase.forTesting('${temp.path}/pos.db',seed:true);repo=PosRepository(database:db);
    await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    await repo.upsertProduct(product);
    await repo.createSale(cart:CartState(items:[CartItem(product:product)]),paymentMethod:'CASH',paidCents:1250,cashier:'admin');
  });
  tearDown(()async{await db.close();await temp.delete(recursive:true);});
  testWidgets('capture actual application screens for employee training', (tester)async{
    tester.view.physicalSize=const Size(430,932);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    // Use the bundled production CJK font, never Flutter test's Ahem squares.
    final output=Directory('assets/training');
    await tester.runAsync(() async {
      final fontData = await File('.training_desktop/assets/fonts/NotoSansSC-Regular.ttf').readAsBytes().then((b)=>ByteData.sublistView(b));
      // flutter_tester disables asset fonts and uses Ahem for unspecified styles.
      // Register real glyphs for both explicit and inherited production styles.
      for (final family in ['Roboto', 'Ahem', 'monospace']) {
        await (FontLoader(family)..addFont(Future.value(fontData))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await output.create(recursive:true);
    });
    expect(tester.takeException(), isNull);
    final key=GlobalKey();
    Future<void> settle()async{
      for(var i=0;i<5;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:200)));await tester.pump(const Duration(milliseconds:200));}
      expect(tester.takeException(),isNull);
    }
    Future<void> capture(String name, Widget screen, Finder target, {bool history=false, bool scroll=false})async{
      debugPrint('Training capture: $name');
      await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildCnkhTheme(),home:Scaffold(body:screen))));await settle();
      if(history){await tester.tap(find.text('Submission History'));await tester.pump(const Duration(milliseconds:500));await settle();}
      if(scroll){
        await tester.scrollUntilVisible(target.first, 500, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
        await settle();
      }
      expect(target,findsWidgets);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final point=tester.getCenter(target.first);
      final bounds=boundary.size;
      expect(point.dx,inInclusiveRange(0,bounds.width));expect(point.dy,inInclusiveRange(0,bounds.height));
      await tester.runAsync(()async{
        final image=await boundary.toImage(pixelRatio:1);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await File('${output.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        await File('${output.path}/$name.json').writeAsString(jsonEncode({'width':bounds.width,'height':bounds.height,'x':point.dx/bounds.width,'y':point.dy/bounds.height,'source':'actual Flutter widget screenshot','screen':screen.runtimeType.toString()}));
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      debugPrint('Training captured: $name');
      await tester.pumpWidget(const SizedBox.shrink());await settle();
    }
    await capture('login',LoginScreen(repo:repo,onLoggedIn:(_){}),find.byType(TextField));
    await capture('sale',CartScreen(cart:CartState(items:[CartItem(product:product)]),user:user,repo:repo,onChanged:(){},onCheckout:(){},onHold:()async{},onResume:()async{}),find.byType(TextField));
    await capture('payment',CheckoutScreen(cart:CartState(items:[CartItem(product:product)]),user:user,repo:repo,qrStorage:QrStorage(),onPaid:(_){},onCancel:(){}),find.byType(TextField));
    await capture('refund',SalesListScreen(repo:repo,todayOnly:true,canVoid:true),find.text('作废'));
    await capture('stock',StocktakePage(repo:repo,user:user),find.byIcon(Icons.edit));
    await capture('einvoice_status',EInvoiceStatusScreen(repo:repo),find.byType(DropdownButtonFormField<String>));
    await capture('sync',SettingsScreen(repo:repo,user:user,qrStorage:QrStorage()),find.text('局域网同步 / LAN Sync'),scroll:true);
  },timeout:const Timeout(Duration(minutes:5)));
}
