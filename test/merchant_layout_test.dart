import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/merchant/merchant_data.dart';
import 'package:soopi/merchant/merchant_login_screen.dart';
import 'package:soopi/merchant/merchant_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('soopi/merchant_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('Owner forms and tabs fit a $width phone with larger text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget app(Widget child) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: child,
      );
      await tester.pumpWidget(app(const MerchantLoginScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final register = find.text('Chưa có tài khoản? Đăng ký chủ quán');
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Đăng ký tài khoản chủ quán'));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(MerchantScreen(data: MerchantData())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Thực đơn', 'Đơn hàng', 'Voucher']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
    });
  }
}
