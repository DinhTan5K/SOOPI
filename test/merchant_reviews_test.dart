import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soopi/merchant/merchant_reviews.dart';
import 'package:soopi/services/merchant_api_service.dart';

void main() {
  Map<String, dynamic> page(List<Map<String, dynamic>> rows, {int? total}) => {
    'items': rows,
    'total': total ?? rows.length,
    'averageRating': rows.isEmpty ? 0 : 4.5,
  };
  Map<String, dynamic> review(String id) => {
    'id': id,
    'customerName': 'Khách $id',
    'orderCode': 'SP$id',
    'restaurantRating': 4,
    'comment': 'Món ngon $id',
    'createdAt': '2026-10-31T01:00:00Z',
  };

  Future<void> show(WidgetTester tester, MockClient client) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantReviewsScreen(
          restaurantId: 'shop',
          api: MerchantApiService(client: client, token: () async => 'token'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Loads real review fields, paginates and refreshes without duplicates',
    (tester) async {
      var firstPageRequests = 0;
      await show(
        tester,
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token');
          expect(
            request.url.path,
            endsWith('/merchant/restaurants/shop/reviews'),
          );
          expect(request.url.queryParameters['pageSize'], '20');
          final second = request.url.queryParameters['page'] == '2';
          if (!second) firstPageRequests++;
          return http.Response(
            jsonEncode(page([review(second ? '2' : '1')], total: 2)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(find.text('4.5 / 5 sao'), findsOneWidget);
      expect(find.text('Khách 1'), findsOneWidget);
      expect(find.text('Món ngon 1'), findsOneWidget);
      expect(find.textContaining('Đơn #SP1'), findsOneWidget);
      await tester.ensureVisible(find.text('Xem thêm đánh giá'));
      await tester.tap(find.text('Xem thêm đánh giá'));
      await tester.pumpAndSettle();
      expect(find.text('Khách 2'), findsOneWidget);
      expect(find.text('Xem thêm đánh giá'), findsNothing);
      await tester.tap(find.byTooltip('Tải lại đánh giá'));
      await tester.pumpAndSettle();
      expect(firstPageRequests, 2);
      expect(find.text('Khách 1'), findsOneWidget);
      expect(find.text('Khách 2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shows an honest empty state', (tester) async {
    await show(
      tester,
      MockClient(
        (_) async => http.Response(
          jsonEncode(page([])),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    expect(find.text('Quán chưa nhận được đánh giá nào.'), findsOneWidget);
    expect(find.text('Chưa có đánh giá'), findsOneWidget);
    expect(find.text('Xem thêm đánh giá'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API failure can be retried', (tester) async {
    var fail = true;
    await show(
      tester,
      MockClient(
        (_) async => fail
            ? http.Response('{}', 500)
            : http.Response(
                jsonEncode(page([review('1')])),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
      ),
    );
    expect(find.textContaining('Không tải được đánh giá'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Khách 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
