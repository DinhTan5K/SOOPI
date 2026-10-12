import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/merchant/merchant_orders.dart';

void main() {
  testWidgets('New mock order opens modal, plays sound and can be accepted', (
    tester,
  ) async {
    var alerts = 0;
    const channel = MethodChannel('soopi/order_alert');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'play') alerts++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MerchantOrders(acceptingOrders: true)),
      ),
    );
    await tester.tap(find.text('Tạo đơn mới (demo)'));
    await tester.pumpAndSettle();
    expect(find.text('Bạn có đơn hàng mới!'), findsOneWidget);
    expect(alerts, 1);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Nhận đơn'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Đang chuẩn bị (2)'), findsOneWidget);
    await tester.tap(find.text('Âm thanh thông báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo đơn mới (demo)'));
    await tester.pumpAndSettle();
    expect(alerts, 1);
    await tester.tap(find.text('Xem sau'));
    await tester.pumpAndSettle();
    expect(find.text('Chờ xác nhận (3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Accepts an order and moves it through fulfillment', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MerchantOrders(acceptingOrders: true)),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chờ xác nhận (2)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Nhận đơn').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhận đơn').first);
    await tester.pumpAndSettle();
    expect(find.text('Chờ xác nhận (1)'), findsOneWidget);
    await tester.ensureVisible(find.text('Đang chuẩn bị (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Đang chuẩn bị (2)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Món đã sẵn sàng').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Món đã sẵn sàng').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sẵn sàng (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sẵn sàng (2)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hoàn tất đơn').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn tất đơn').first);
    await tester.pumpAndSettle();
    expect(find.text('Hoàn tất (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Paused shop disables accepting new orders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MerchantOrders(acceptingOrders: false)),
      ),
    );
    await tester.ensureVisible(find.text('Nhận đơn').first);
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Nhận đơn').first,
    );
    expect(button.onPressed, isNull);
  });
}
