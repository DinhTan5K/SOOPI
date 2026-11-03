import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soopi/merchant/merchant_data.dart';
import 'package:soopi/merchant/merchant_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Restaurant changes survive reopening with Android storage', (
    tester,
  ) async {
    // This test deliberately uses the real Android MethodChannel, without mocks.
    final original = MerchantData();
    expect(
      original.supportsStorage,
      isTrue,
      reason: 'Run on an Android device.',
    );
    await original.load();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await original.save();
    });

    final data = MerchantData();
    await data.save(
      accepting: true,
      schedule: List.generate(7, (_) => OpeningDay()),
      menu: [
        MenuItem(
          id: 'integration-dish',
          name: 'Integration dish',
          price: 45000,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: MerchantScreen(data: data)));
    await tester.pumpAndSettle();

    // Pause orders and save Monday as a closed day through the actual UI.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Tạm ngưng nhận đơn'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lưu giờ mở cửa'), 250);
    await Scrollable.ensureVisible(
      tester.element(find.text('Lưu giờ mở cửa')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu giờ mở cửa'));
    await tester.pumpAndSettle();
    expect(find.text('Có thay đổi chưa lưu.'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Thực đơn'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Integration dish'), findsOneWidget);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    // Dispose the screen and model, then read persisted data into a fresh model.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final restored = MerchantData();
    await tester.pumpWidget(MaterialApp(home: MerchantScreen(data: restored)));
    await tester.pumpAndSettle();
    expect(restored.acceptingOrders, isFalse);
    expect(restored.hours.first.enabled, isFalse);
    expect(restored.hours.skip(1).every((day) => day.enabled), isTrue);
    expect(restored.items.single.id, 'integration-dish');
    expect(restored.items.single.available, isFalse);
    expect(find.text('Tạm ngưng nhận đơn'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Thực đơn'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Integration dish'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
