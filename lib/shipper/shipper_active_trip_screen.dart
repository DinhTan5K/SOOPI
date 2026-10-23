import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_config.dart';
import '../services/order_socket_service.dart';
import '../services/profile_api_service.dart';

enum TripStep {
  goingToShop,
  atShopWaiting,
  deliveringToCustomer,
  completed,
}

class ShipperActiveTripScreen extends StatefulWidget {
  final Map<String, dynamic>? initialTrip;
  final VoidCallback? onTripFinished;

  const ShipperActiveTripScreen({
    super.key,
    this.initialTrip,
    this.onTripFinished,
  });

  @override
  State<ShipperActiveTripScreen> createState() => _ShipperActiveTripScreenState();
}

class _ShipperActiveTripScreenState extends State<ShipperActiveTripScreen> {
  TripStep _currentStep = TripStep.goingToShop;
  Map<String, dynamic>? _tripData;
  bool _isLoading = false;
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    _tripData = widget.initialTrip;
  }

  @override
  void didUpdateWidget(covariant ShipperActiveTripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTrip != oldWidget.initialTrip && widget.initialTrip != null) {
      setState(() {
        _tripData = widget.initialTrip;
        _currentStep = TripStep.goingToShop;
      });
    }
  }

  Future<void> _updateOrderStatus(String status) async {
    final orderId = _tripData?['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      String driverId = 'd16e5d6a-903e-40fa-8b01-cf146ecd55ac';
      try {
        final profile = await ProfileApiService().getProfile();
        if (profile.id.isNotEmpty) {
          driverId = profile.id;
        }
      } catch (_) {}

      // 1. Cập nhật trực tiếp qua SignalR Hub (Real-time đồng bộ cả 3 bên)
      bool success = await OrderSocketService().driverUpdateOrderStatus(
        orderId,
        driverId,
        status,
      );

      // 2. Fallback qua HTTP REST nếu SignalR đang kết nối lại
      if (!success) {
        final base = ApiConfig().baseUrl;
        final url = Uri.parse('$base/orders/$orderId/delivery');
        final res = await http.patch(
          url,
          headers: {
            'Content-Type': 'application/json',
            'X-User-Id': driverId,
          },
          body: jsonEncode({
            'status': status,
            'note': 'Shipper cập nhật trạng thái',
          }),
        );
        success = res.statusCode >= 200 && res.statusCode < 300;
      }

      if (success && mounted) {
        if (status == 'Delivering') {
          setState(() => _currentStep = TripStep.deliveringToCustomer);
        } else if (status == 'Delivered') {
          setState(() => _currentStep = TripStep.completed);
          _showCompletionDialog();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể cập nhật trạng thái đơn hàng. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật đơn: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GIAO HÀNG THÀNH CÔNG',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              'Thu nhập cuốc: ${currencyFormat.format((_tripData?['deliveryFee'] as num?)?.toDouble() ?? 15000)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onTripFinished?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Về màn hình chính'),
          ),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tripData == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Chưa có cuốc xe nào đang chạy',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
              SizedBox(height: 8),
              Text(
                'Chuyển sang tab Bản đồ và bật Trực tuyến để nhận đơn hàng mới.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final orderCode = _tripData!['orderCode'] ?? '---';
    final restaurantName = _tripData!['restaurantName'] ?? 'Quán ăn';
    final deliveryAddress = _tripData!['deliveryAddress'] ?? 'Địa chỉ khách';
    final deliveryFee = (_tripData!['deliveryFee'] as num?)?.toDouble() ?? 15000.0;
    final totalAmount = (_tripData!['totalAmount'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thẻ Trạng thái tiến trình
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ĐƠN HÀNG #$orderCode',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Text(
                          currencyFormat.format(deliveryFee),
                          style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Timeline tiến trình 3 bước
                  Row(
                    children: [
                      _buildStepIndicator(
                        title: 'Đến quán',
                        isActive: _currentStep == TripStep.goingToShop,
                        isDone: _currentStep.index > TripStep.goingToShop.index,
                      ),
                      Expanded(
                        child: Divider(
                          color: _currentStep.index > TripStep.goingToShop.index ? Colors.green : Colors.grey.shade300,
                          thickness: 2,
                        ),
                      ),
                      _buildStepIndicator(
                        title: 'Lấy món',
                        isActive: _currentStep == TripStep.atShopWaiting,
                        isDone: _currentStep.index > TripStep.atShopWaiting.index,
                      ),
                      Expanded(
                        child: Divider(
                          color: _currentStep.index > TripStep.atShopWaiting.index ? Colors.green : Colors.grey.shade300,
                          thickness: 2,
                        ),
                      ),
                      _buildStepIndicator(
                        title: 'Giao khách',
                        isActive: _currentStep == TripStep.deliveringToCustomer,
                        isDone: _currentStep == TripStep.completed,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // NỘI DUNG TỪNG CHẶNG
          if (_currentStep == TripStep.goingToShop) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHẶNG 1: ĐẾN QUÁN LẤY MÓN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    const SizedBox(height: 12),
                    Text(restaurantName.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('Vui lòng đọc mã đơn khi đến quán', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _makePhoneCall('0905123456'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        side: const BorderSide(color: Colors.blue),
                        foregroundColor: Colors.blue,
                      ),
                      child: const Text('Gọi điện cho khách hàng'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _currentStep = TripStep.atShopWaiting),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('TÔI ĐÃ ĐẾN QUÁN', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_currentStep == TripStep.atShopWaiting) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHẶNG 2: KIỂM TRA & NHẬN MÓN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Đọc mã cho quán: #$orderCode',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _updateOrderStatus('Delivering'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('ĐÃ LẤY MÓN - BẮT ĐẦU GIAO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_currentStep == TripStep.deliveringToCustomer) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHẶNG 3: GIAO ĐẾN KHÁCH HÀNG', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    const SizedBox(height: 12),
                    const Text('Địa chỉ giao hàng:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(deliveryAddress.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tiền thu hộ (COD):', style: TextStyle(fontSize: 14)),
                        Text(
                          currencyFormat.format(totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _makePhoneCall('0905123456'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        side: const BorderSide(color: Colors.blue),
                        foregroundColor: Colors.blue,
                      ),
                      child: const Text('Gọi điện cho khách hàng'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _updateOrderStatus('Delivered'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('XÁC NHẬN GIAO THÀNH CÔNG', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepIndicator({
    required String title,
    required bool isActive,
    required bool isDone,
  }) {
    Color color = Colors.grey.shade400;
    if (isDone) color = Colors.green;
    if (isActive) color = Colors.deepOrange;

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
