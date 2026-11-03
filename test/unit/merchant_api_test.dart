import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soopi/merchant/merchant_data.dart';
import 'package:soopi/services/merchant_api_service.dart';

void main() {
  test(
    'Image upload sends a PNG with matching MIME type and bearer token',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/merchant/restaurants/shop/images');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        expect(
          latin1.decode(request.bodyBytes),
          contains('content-type: image/png'),
        );
        return http.Response(
          '{"imageUrl":"https://example.com/menu.png"}',
          200,
        );
      });
      final api = MerchantApiService(
        client: client,
        token: () async => 'token',
      );
      expect(
        await api.upload(
          'shop',
          base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
        ),
        'https://example.com/menu.png',
      );
    },
  );
  test(
    'Merchant requests require authentication and surface server errors',
    () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({'error': 'Restaurant is locked.'}),
          403,
        );
      });
      final anonymous = MerchantApiService(
        client: client,
        token: () async => null,
      );
      await expectLater(anonymous.request('GET', 'me'), throwsException);
      expect(called, isFalse);
      final api = MerchantApiService(
        client: client,
        token: () async => 'test-token',
      );
      await expectLater(
        api.request('GET', 'me'),
        throwsA(
          predicate((e) => e.toString().contains('Restaurant is locked.')),
        ),
      );
    },
  );

  test(
    'Remote merchant maps hours and persists server IDs and availability',
    () async {
      var available = true;
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'PATCH') {
          expect(path, '/api/merchant/restaurants/shop/menu/dish/availability');
          available = jsonDecode(request.body)['isAvailable'];
          return http.Response('', 204);
        }
        if (request.method == 'PUT') {
          expect(path, contains('/hours/'));
          return http.Response('', 204);
        }
        if (path.endsWith('/me')) return http.Response('{}', 200);
        if (path.endsWith('/restaurants')) {
          return http.Response('{"items":[{"id":"shop"}],"total":1}', 200);
        }
        return http.Response(
          jsonEncode({
            'id': 'shop',
            'name': 'Shop',
            'approvalStatus': 'Approved',
            'isActive': true,
            'isAcceptingOrders': true,
            'categories': [
              {
                'id': 'category',
                'name': 'Food',
                'items': [
                  {
                    'id': 'dish',
                    'name': 'Dish',
                    'price': 45000,
                    'isAvailable': available,
                  },
                ],
              },
            ],
            'openingHours': [
              {
                'dayOfWeek': 0,
                'opensAt': '20:00:00',
                'closesAt': '02:00:00',
                'isClosed': false,
              },
            ],
          }),
          200,
        );
      });
      final data = MerchantData(
        remote: true,
        api: MerchantApiService(client: client, token: () async => 'token'),
      );
      await data.load();
      expect(data.items.single.id, 'dish');
      expect(data.categories, ['Food']);
      expect(data.hours.last.open, 1200);
      expect(data.hours.last.close, 120);
      expect(data.hours.first.enabled, isFalse);
      await data.save(menu: [data.items.single.withAvailability(false)]);
      expect(data.items.single.available, isFalse);
      await data.save(schedule: data.hours);
      final hours = requests.where((r) => r.method == 'PUT').toList();
      expect(hours.length, 7);
      expect(hours.first.url.path, endsWith('/hours/1'));
      expect(hours.last.url.path, endsWith('/hours/0'));
      expect(jsonDecode(hours.last.body)['closesAt'], '02:00:00');
    },
  );
}
