import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/order_socket_service.dart';

class DriverOfferDialog extends StatefulWidget {
  final Map<String, dynamic> offer;
  final String driverId;

  const DriverOfferDialog({
    super.key,
    required this.offer,
    required this.driverId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> offer,
    required String driverId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DriverOfferDialog(offer: offer, driverId: driverId),
    );
  }

  @override
  State<DriverOfferDialog> createState() => _DriverOfferDialogState();
}

class _DriverOfferDialogState extends State<DriverOfferDialog>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _countdownTimer;
  StreamSubscription? _expiredSubscription;
  bool _isResponding = false;
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    _remainingSeconds = (widget.offer['timeoutSeconds'] as num?)?.toInt() ?? 15;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _rejectAndClose();
      }
    });

    _expiredSubscription =
        OrderSocketService().onDeliveryOfferExpired.listen((event) {
      final expiredOrderId = event['orderId']?.toString();
      final currentOrderId = widget.offer['orderId']?.toString();
      if (expiredOrderId == currentOrderId && mounted) {
        _closeDialog(false);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _expiredSubscription?.cancel();
    super.dispose();
  }

  Future<void> _acceptAndClose() async {
    if (_isResponding) return;
    setState(() => _isResponding = true);

    final orderId = widget.offer['orderId']?.toString() ?? '';
    final success = await OrderSocketService().driverAcceptOffer(
      orderId,
      widget.driverId,
    );

    if (mounted) {
      _closeDialog(success);
    }
  }

  Future<void> _rejectAndClose() async {
    if (_isResponding) return;
    setState(() => _isResponding = true);

    final orderId = widget.offer['orderId']?.toString() ?? '';
    await OrderSocketService().driverRejectOffer(orderId, widget.driverId);

    if (mounted) {
      _closeDialog(false);
    }
  }

  void _closeDialog(bool accepted) {
    _countdownTimer?.cancel();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderCode = widget.offer['orderCode'] ?? '---';
    final restaurantName = widget.offer['restaurantName'] ?? 'Quán ăn';
    final deliveryAddress = widget.offer['deliveryAddress'] ?? 'Địa chỉ khách';
    final deliveryFee = (widget.offer['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final distance = (widget.offer['distanceToRestaurantKm'] as num?)?.toDouble() ?? 0.0;
    final totalTimeout = (widget.offer['timeoutSeconds'] as num?)?.toDouble() ?? 15.0;
    final progress = _remainingSeconds / totalTimeout;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 10,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Tiêu đề & Đếm ngược
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CƠ HỘI GIAO ĐƠN',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Mã đơn: #$orderCode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _remainingSeconds <= 5
                        ? Colors.red.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 5
                          ? Colors.red.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Progress bar đếm ngược
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _remainingSeconds <= 5 ? Colors.red : Colors.deepOrange,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),

            // Thu nhập cước phí
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thu nhập nhận được:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  Text(
                    currencyFormat.format(deliveryFee),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Thông tin Quán lấy hàng
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quán lấy hàng:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                Text(
                  restaurantName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Cách bạn: ${distance.toStringAsFixed(1)} km',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Thông tin Khách nhận hàng
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Giao đến:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                Text(
                  deliveryAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Nút bấm: Từ chối / Nhận đơn
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _isResponding ? null : _rejectAndClose,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Bỏ qua',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isResponding ? null : _acceptAndClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isResponding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'NHẬN ĐƠN NGAY',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
