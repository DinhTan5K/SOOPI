import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_api_service.dart';

class ShipperEarningsScreen extends StatefulWidget {
  const ShipperEarningsScreen({super.key});

  @override
  State<ShipperEarningsScreen> createState() => _ShipperEarningsScreenState();
}

class _ShipperEarningsScreenState extends State<ShipperEarningsScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  String _shipperName = 'Tài xế SOOPI';
  String _shipperPhone = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await ProfileApiService().getProfile();
    if (mounted && profile.id.isNotEmpty) {
      setState(() {
        _shipperName = profile.fullName;
        _shipperPhone = profile.phoneNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thẻ Thông tin Tài xế & Ví
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B00), Color(0xFFFF9500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.delivery_dining, color: Colors.deepOrange, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shipperName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            Text(
                              _shipperPhone.isNotEmpty ? _shipperPhone : 'Đối tác giao vận SOOPI',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Tổng thu nhập hôm nay', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(95000),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Thống kê nhanh: Cuốc hoàn thành, Đánh giá
          Row(
            children: [
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: const [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
                        SizedBox(height: 8),
                        Text('6 cuốc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Đã hoàn thành', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: const [
                        Icon(Icons.star, color: Colors.amber, size: 28),
                        SizedBox(height: 8),
                        Text('4.9 ⭐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Đánh giá', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Cài đặt & Hỗ trợ
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.deepOrange),
                  title: const Text('Lịch sử cuốc xe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.green),
                  title: const Text('Rút tiền về tài khoản ngân hàng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.headset_mic_outlined, color: Colors.blue),
                  title: const Text('Hỗ trợ tài xế'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Nút đăng xuất tài khoản Tài xế
          ElevatedButton.icon(
            onPressed: () async {
              ProfileApiService().clearCache();
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất tài khoản'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
