import 'package:flutter/material.dart';

class MerchantOrders extends StatelessWidget {
  const MerchantOrders({super.key, required this.acceptingOrders});
  final bool acceptingOrders;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Đơn hàng',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      if (!acceptingOrders) ...[
        const SizedBox(height: 12),
        const Text(
          'Quán đang tạm ngưng nhận đơn.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
      const SizedBox(height: 64),
      const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.black38),
      const SizedBox(height: 16),
      const Text(
        'Chưa có đơn hàng',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
