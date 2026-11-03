import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/merchant/merchant_orders.dart';

void main() {
  for (final accepting in [true, false]) {
    testWidgets(
      'Orders has no demo data or actions when accepting=$accepting',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MerchantOrders(acceptingOrders: accepting)),
          ),
        );
        expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.textContaining('SP102'), findsNothing);
        expect(find.textContaining('demo'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
