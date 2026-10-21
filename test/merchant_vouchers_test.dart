import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soopi/merchant/merchant_data.dart';
import 'package:soopi/merchant/merchant_vouchers.dart';
import 'package:soopi/services/merchant_api_service.dart';

void main() {
  final item = MenuItem(
    id: 'food',
    name: 'Cơm gà',
    price: 40000,
    category: 'Cơm',
    description: '',
    available: true,
  );

  testWidgets('Creates a restaurant voucher and toggles its status', (
    tester,
  ) async {
    final rows = <Map<String, dynamic>>[];
    Map<String, dynamic>? created;
    final api = MerchantApiService(
      token: () async => 'token',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        if (request.method == 'POST') {
          created = jsonDecode(request.body) as Map<String, dynamic>;
          rows.add({
            ...created!,
            'id': 'voucher',
            'usedCount': 0,
            'status': 'Active',
          });
          return http.Response(jsonEncode(rows.last), 201);
        }
        if (request.method == 'PATCH') {
          expect(request.url.path, endsWith('/voucher/status'));
          expect(jsonDecode(request.body), {'isActive': false});
          rows.first['isActive'] = false;
          rows.first['status'] = 'Inactive';
          return http.Response(jsonEncode(rows.first), 200);
        }
        return http.Response(jsonEncode(rows), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantVouchers(restaurantId: 'shop', api: api, items: [item]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có voucher'), findsOneWidget);
    await tester.tap(find.text('Tạo voucher'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'com20');
    await tester.enterText(find.byType(TextFormField).at(1), '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo voucher').last);
    await tester.pumpAndSettle();
    expect(created!['code'], 'COM20');
    expect(created!['menuItemId'], isNull);
    expect(created!['discountType'], 'Percent');
    expect(created!['discountValue'], 20);
    expect(find.text('COM20'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã tắt'), findsOneWidget);
  });

  testWidgets(
    'Requires a menu selection for item vouchers and validates percent',
    (tester) async {
      Map<String, dynamic>? created;
      final api = MerchantApiService(
        token: () async => 'token',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            created = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{}', 201);
          }
          return http.Response('[]', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantVouchers(
              restaurantId: 'shop',
              api: api,
              items: [item],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạo voucher'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'FOOD');
      await tester.enterText(find.byType(TextFormField).at(1), '101');
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo voucher').last);
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng chọn món'), findsOneWidget);
      expect(find.text('Phần trăm không vượt quá 100'), findsOneWidget);
      expect(created, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cơm gà').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '25');
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo voucher').last);
      await tester.pumpAndSettle();
      expect(created!['menuItemId'], 'food');
    },
  );

  testWidgets('Shows API errors and supports retry', (tester) async {
    var fail = true;
    final api = MerchantApiService(
      token: () async => 'token',
      client: MockClient((request) async {
        return fail
            ? http.Response('{"title":"Unavailable"}', 503)
            : http.Response('[]', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantVouchers(restaurantId: 'shop', api: api, items: [item]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Unavailable'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có voucher'), findsOneWidget);
  });
}
