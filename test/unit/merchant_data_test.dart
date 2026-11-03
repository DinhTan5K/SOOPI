import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/merchant/merchant_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

}
