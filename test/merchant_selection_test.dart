import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soopi/merchant/merchant_data.dart';
import 'package:soopi/merchant/merchant_screen.dart';
import 'package:soopi/services/merchant_api_service.dart';

MerchantData merchant(
  List<Map<String, dynamic>> restaurants,
  List<String> details, {
  bool paginated = false,
}) {
  return MerchantData(
    remote: true,
    api: MerchantApiService(
      token: () async => 'token',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/me')) return http.Response('{}', 200);
        if (request.url.path.endsWith('/orders')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/restaurants')) {
          final page = int.parse(request.url.queryParameters['page']!);
          final items = paginated
              ? restaurants.skip(page - 1).take(1).toList()
              : restaurants;
          return http.Response(
            jsonEncode({'items': items, 'total': restaurants.length}),
            200,
          );
        }
        final id = request.url.pathSegments.last;
        details.add(id);
        final restaurant = restaurants.singleWhere((r) => r['id'] == id);
        return http.Response(
          jsonEncode({
            ...restaurant,
            'approvalStatus': 'Approved',
            'isActive': true,
            'isAcceptingOrders': true,
            'categories': [],
            'openingHours': [],
          }),
          200,
        );
      }),
    ),
  );
}

void main() {
  final restaurants = [
    {
      'id': 'first',
      'name': 'First restaurant',
      'address': 'First address',
      'approvalStatus': 'Approved',
    },
    {
      'id': 'second',
      'name': 'Second restaurant',
      'address': 'Second address',
      'approvalStatus': 'Pending',
    },
  ];

  testWidgets(
    'Multiple restaurants require a choice before loading management',
    (tester) async {
      final details = <String>[];
      final data = merchant(restaurants, details, paginated: true);
      await tester.pumpWidget(MaterialApp(home: MerchantScreen(data: data)));
      await tester.pumpAndSettle();
      expect(find.text('Chọn quán để quản lý'), findsOneWidget);
      expect(find.text('First restaurant'), findsOneWidget);
      expect(find.text('Second restaurant'), findsOneWidget);
      expect(data.restaurantId, isNull);
      expect(details, isEmpty);
      await tester.tap(find.text('Second restaurant'));
      await tester.pumpAndSettle();
      expect(data.restaurantId, 'second');
      expect(details, ['second']);
      expect(find.text('Chọn quán để quản lý'), findsNothing);
      expect(find.textContaining('Second restaurant'), findsOneWidget);

      await tester.tap(find.byTooltip('Chọn quán'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First restaurant • Approved'));
      await tester.pumpAndSettle();
      expect(data.restaurantId, 'first');
      expect(details, ['second', 'first']);
    },
  );

  testWidgets('A single restaurant opens directly', (tester) async {
    final details = <String>[];
    final data = merchant([restaurants.first], details);
    await tester.pumpWidget(MaterialApp(home: MerchantScreen(data: data)));
    await tester.pumpAndSettle();
    expect(data.restaurantId, 'first');
    expect(details, ['first']);
    expect(find.text('Chọn quán để quản lý'), findsNothing);
  });

  testWidgets('No restaurants keeps registration available', (tester) async {
    final data = merchant([], []);
    await tester.pumpWidget(MaterialApp(home: MerchantScreen(data: data)));
    await tester.pumpAndSettle();
    expect(find.text('Đăng ký quán ăn'), findsOneWidget);
    expect(data.restaurantId, isNull);
    expect(tester.takeException(), isNull);
  });
}
