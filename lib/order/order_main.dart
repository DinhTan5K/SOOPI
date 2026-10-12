import 'package:flutter/material.dart';
import 'order_list_screen.dart';

/// File chạy độc lập dành riêng để test/demo UC06, UC07, UC08
/// Chạy lệnh: flutter run -t lib/order/order_main.dart
void main() {
  runApp(const OrderApp());
}

class OrderApp extends StatelessWidget {
  const OrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOOPI Order Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const OrderListScreen(),
    );
  }
}
