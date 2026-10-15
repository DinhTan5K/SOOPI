import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_api_service.dart';
import '../services/auth_service.dart';
import '../auth_screen.dart';
import 'edit_profile_screen.dart';
import 'address_list_screen.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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
    // Hiển thị ngay lập tức từ cache hoặc thông tin Firebase để người dùng không phải chờ
    _profile = _apiService.cachedProfile ?? _apiService.getInitialProfile();
    // Tải dữ liệu mới nhất ngầm từ backend
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
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản SOOPI FOOD?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Tài khoản & Hồ sơ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        color: Colors.orange,
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Profile Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 34,
                        backgroundImage: NetworkImage(avatarUrl),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.email,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 13),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Thành viên Vàng',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      onPressed: () async {
                        final res = await Navigator.push<UserProfile?>(
                          context,
                          MaterialPageRoute(builder: (context) => EditProfileScreen(profile: profile)),
                        );
                        if (res != null) setState(() => _profile = res);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nhóm: Quản lý thông tin
              _buildSectionTitle('Quản lý tài khoản'),
              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: 'Chỉnh sửa thông tin cá nhân',
                  subtitle: 'Họ tên, ngày sinh, số điện thoại',
                  onTap: () async {
                    final res = await Navigator.push<UserProfile?>(
                      context,
                      MaterialPageRoute(builder: (context) => EditProfileScreen(profile: profile)),
                    );
                    if (res != null) setState(() => _profile = res);
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.location_on_outlined,
                  title: 'Sổ địa chỉ nhận hàng',
                  subtitle: 'Quản lý địa chỉ giao món mặc định',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddressListScreen()),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.lock_outline,
                  title: 'Đổi mật khẩu',
                  subtitle: 'Bảo mật tài khoản Firebase của bạn',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 20),

              // Nhóm: Cài đặt ứng dụng
              _buildSectionTitle('Cài đặt ứng dụng'),
              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.notifications_none_outlined,
                  title: 'Cài đặt thông báo',
                  subtitle: 'Ưu đãi và cập nhật trạng thái đơn hàng',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đang kích hoạt thông báo tự động')),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 20),

              // Nhóm: Hỗ trợ & Khác
              _buildSectionTitle('Hỗ trợ & Thông tin'),
              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.headset_mic_outlined,
                  title: 'Trung tâm trợ giúp',
                  subtitle: 'Giải đáp thắc mắc và liên hệ CSKH',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hotline CSKH: 1900 6868 (8:00 - 22:00)')),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.policy_outlined,
                  title: 'Chính sách & Điều khoản',
                  onTap: () {},
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Đăng xuất',
                  titleColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: _handleSignOut,
                ),
              ]),
              const SizedBox(height: 30),

              Text(
                'SOOPI FOOD v1.0.0',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
    Widget? trailing,
    Color? titleColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.orange).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? Colors.orange, size: 22),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: titleColor ?? Colors.black87),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
          : null,
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, indent: 60, endIndent: 20, color: Colors.grey.shade100);
  }
}
