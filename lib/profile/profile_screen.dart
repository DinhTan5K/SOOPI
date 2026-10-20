import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_api_service.dart';
import '../services/auth_service.dart';
import '../services/api_config.dart';
import '../auth_screen.dart';
import 'edit_profile_screen.dart';
import 'address_list_screen.dart';
import 'change_password_screen.dart';
import '../order/order_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  const ProfileScreen({super.key, this.onBackToHome});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ProfileApiService();
  UserProfile? _profile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _profile = _apiService.cachedProfile ?? _apiService.getInitialProfile();
    _loadProfile(silent: true);
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent && _profile == null) {
      setState(() => _isLoading = true);
    }
    try {
      final p = await _apiService.getProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đăng xuất', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản SOOPI FOOD?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _apiService.clearCache();
      await AuthService().signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _openEditProfile(UserProfile currentProfile) async {
    final updated = await Navigator.push<UserProfile?>(
      context,
      MaterialPageRoute(builder: (context) => EditProfileScreen(profile: currentProfile)),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _profile == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    final profile = _profile ?? _apiService.getInitialProfile();

    final avatarUrl = profile.avatarUrl.isNotEmpty
        ? profile.avatarUrl
        : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(profile.fullName)}&background=FFA500&color=fff';

    final canPop = Navigator.canPop(context);
    final showBackButton = canPop || widget.onBackToHome != null;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onBackToHome != null) {
          widget.onBackToHome!();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  tooltip: 'Quay lại',
                  onPressed: () {
                    if (canPop) {
                      Navigator.pop(context);
                    } else if (widget.onBackToHome != null) {
                      widget.onBackToHome!();
                    }
                  },
                )
              : null,
          title: const Text('Tài khoản của tôi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi_tethering, color: Colors.orange, size: 22),
            tooltip: 'Cài đặt kết nối máy chủ BE',
            onPressed: () {
              ApiConfig.showConfigDialog(
                context,
                onConnected: () => _loadProfile(silent: false),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange, size: 22),
            tooltip: 'Làm mới',
            onPressed: () => _loadProfile(silent: false),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Colors.orange,
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // 1. COMPACT PROFILE HEADER CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar với nút camera nhỏ
                    GestureDetector(
                      onTap: () => _openEditProfile(profile),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white24,
                              backgroundImage: NetworkImage(avatarUrl),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.orange, size: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Tên + Email / Số điện thoại + Badge thành viên
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName.isNotEmpty ? profile.fullName : 'Khách hàng SOOPI',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.phoneNumber.isNotEmpty
                                ? profile.phoneNumber
                                : (profile.email.isNotEmpty ? profile.email : 'Chưa cập nhật SĐT'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  profile.role.toLowerCase() == 'admin'
                                      ? Icons.admin_panel_settings
                                      : (profile.role.toLowerCase() == 'owner' || profile.role.toLowerCase() == 'restaurantowner')
                                          ? Icons.storefront
                                          : Icons.stars,
                                  color: Colors.amber,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  profile.role.toLowerCase() == 'admin'
                                      ? 'Quản trị viên (Admin)'
                                      : (profile.role.toLowerCase() == 'owner' || profile.role.toLowerCase() == 'restaurantowner')
                                          ? 'Chủ quán (Owner)'
                                          : 'Khách hàng (Customer)',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Nút chỉnh sửa nhỏ gọn
                    IconButton(
                      icon: const Icon(Icons.edit_square, color: Colors.white, size: 20),
                      tooltip: 'Chỉnh sửa hồ sơ',
                      onPressed: () => _openEditProfile(profile),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 2. QUICK ACTIONS BAR (Lối tắt thao tác nhanh: Đơn hàng, Địa chỉ, Đổi MK)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'Đơn hàng',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const OrderListScreen()),
                        );
                      },
                    ),
                    _buildVerticalDivider(),
                    _buildQuickAction(
                      icon: Icons.location_on_outlined,
                      label: 'Địa chỉ',
                      color: Colors.redAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddressListScreen()),
                        );
                      },
                    ),
                    _buildVerticalDivider(),
                    _buildQuickAction(
                      icon: Icons.lock_reset_outlined,
                      label: 'Đổi MK',
                      color: Colors.teal,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                        );
                      },
                    ),
                    _buildVerticalDivider(),
                    _buildQuickAction(
                      icon: Icons.edit_note_outlined,
                      label: 'Hồ sơ',
                      color: Colors.orange,
                      onTap: () => _openEditProfile(profile),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 3. NHÓM QUẢN LÝ TÀI KHOẢN (Gộp menu tinh gọn, không dàn trải)
              _buildSectionTitle('Quản lý thông tin'),
              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: 'Cập nhật thông tin cá nhân',
                  subtitle: 'Họ tên, ảnh Cloudinary, ngày sinh, SĐT',
                  onTap: () => _openEditProfile(profile),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.pin_drop_outlined,
                  title: 'Sổ địa chỉ nhận hàng',
                  subtitle: 'Quản lý các điểm giao món mặc định',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddressListScreen()),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.password_outlined,
                  title: 'Đổi mật khẩu',
                  subtitle: 'Bảo mật tài khoản của bạn',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 14),

              // 4. TIỆN ÍCH & TRỢ GIÚP
              _buildSectionTitle('Hỗ trợ & Ứng dụng'),
              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.notifications_none_outlined,
                  title: 'Thông báo & Ưu đãi',
                  subtitle: 'Cập nhật tin khuyến mãi món ngon',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đang kích hoạt thông báo tự động')),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.support_agent_outlined,
                  title: 'Tổng đài hỗ trợ',
                  subtitle: 'Hotline CSKH: 1900 6868 (8:00 - 22:00)',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hotline CSKH: 1900 6868 (8:00 - 22:00)')),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Đăng xuất tài khoản',
                  titleColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: _handleSignOut,
                ),
              ]),

              const SizedBox(height: 20),

              Text(
                'SOOPI FOOD • Phiên bản 1.0.0',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.grey.shade200,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.orange).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? Colors.orange, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: titleColor ?? Colors.black87),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11))
          : null,
      trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, indent: 52, endIndent: 14, color: Colors.grey.shade100);
  }
}
