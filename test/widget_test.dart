import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/main.dart';
import 'package:soopi/merchant/merchant_login_screen.dart';
import 'package:soopi/merchant/merchant_screen.dart';
import 'package:soopi/merchant/merchant_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
  });
  const storage = MethodChannel('soopi/merchant_storage');
  String? saved;
  setUp(() async {
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          if (call.method == 'load') return saved;
          if (call.method == 'save') saved = call.arguments as String;
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });

  test(
    'Merchant data reloads schedule, menu and status from Android storage',
    () async {
      final data = MerchantData();
      final hours = List.generate(7, (_) => OpeningDay(open: 1200, close: 120));
      hours[6].enabled = false;
      await data.save(
        accepting: false,
        schedule: hours,
        menu: [
          MenuItem(
            id: 'test',
            name: 'Món đã lưu',
            price: 50000,
            available: false,
            imageBase64: 'aW1hZ2U=',
          ),
        ],
      );
      final restored = MerchantData();
      await restored.load();
      expect(restored.acceptingOrders, isFalse);
      expect(restored.hours.first.open, 1200);
      expect(restored.hours.first.close, 120);
      expect(restored.hours.last.enabled, isFalse);
      expect(restored.items.single.name, 'Món đã lưu');
      expect(restored.items.single.available, isFalse);
      expect(restored.items.single.imageBase64, 'aW1hZ2U=');
      expect(
        restored.items.single.withAvailability(true).imageBase64,
        'aW1hZ2U=',
      );
    },
  );

  test('Failed save keeps the previous state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          throw PlatformException(code: 'SAVE_FAILED');
        });
    final data = MerchantData();
    await expectLater(
      data.save(accepting: false, menu: []),
      throwsA(isA<PlatformException>()),
    );
    expect(data.acceptingOrders, isTrue);
    expect(data.items, hasLength(4));
  });

  testWidgets('Leaving an unsaved schedule asks before discarding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: MerchantScreen(data: MerchantData())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch chưa được lưu'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục chỉnh'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantScreen), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
  });
  testWidgets('Customer entry opens merchant login', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp());
    await tester.ensureVisible(find.text('Dành cho chủ quán'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dành cho chủ quán'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantLoginScreen), findsOneWidget);
  });

  testWidgets('Merchant login validates required credentials', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MerchantLoginScreen()));
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantScreen), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('Merchant registration validates name and matching passwords', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: MerchantLoginScreen()));
    final toggle = find.text('Chưa có tài khoản? Đăng ký chủ quán');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '123');
    await tester.enterText(find.byType(TextFormField).at(3), 'different');
    final submit = find.text('Đăng ký tài khoản chủ quán');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Nhập họ tên.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có ít nhất 6 ký tự.'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp.'), findsOneWidget);
    final login = find.text('Đã có tài khoản? Đăng nhập');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Nhập họ tên.'), findsNothing);
  });

  testWidgets('Menu supports validation, CRUD, stock and filtering', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: MerchantScreen(data: MerchantData())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thực đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm món'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu món'));
    await tester.tap(find.text('Lưu món'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên món.'), findsOneWidget);
    expect(find.text('Nhập giá lớn hơn 0 bằng số nguyên VND.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Bánh thử nghiệm');
    await tester.enterText(find.byType(TextFormField).at(1), '45000');
    await tester.ensureVisible(find.text('Lưu món'));
    await tester.tap(find.text('Lưu món'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Bánh thử nghiệm');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Bánh thử nghiệm'),
      findsOneWidget,
    );
    expect(find.text('45.000 đ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa món'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '55000');
    await tester.ensureVisible(find.text('Lưu món'));
    await tester.tap(find.text('Lưu món'));
    await tester.pumpAndSettle();
    expect(find.text('55.000 đ'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Còn hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy món phù hợp.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hết hàng'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Bánh thử nghiệm'),
      findsOneWidget,
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa món'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Bánh thử nghiệm'),
      findsOneWidget,
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa món'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Bánh thử nghiệm'),
      findsNothing,
    );
  });

  testWidgets('Shop status and saved schedule survive tab changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: MerchantScreen(data: MerchantData())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Tạm ngưng nhận đơn'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áp dụng thứ Hai cho cả tuần'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lưu giờ mở cửa'), 300);
    await tester.tap(find.text('Lưu giờ mở cửa'));
    await tester.pumpAndSettle();
    expect(find.text('Có thay đổi chưa lưu.'), findsNothing);
    await tester.tap(find.text('Thực đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quán của tôi'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tạm ngưng nhận đơn'), -300);
    expect(find.text('Tạm ngưng nhận đơn'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
  });
}
