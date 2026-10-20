import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home.dart';
import 'services/auth_service.dart';
import 'services/auth_api_service.dart';
import 'services/profile_api_service.dart';
import 'services/api_config.dart';
import 'widgets/otp_verification_dialog.dart';
import 'widgets/forgot_password_dialog.dart';
import 'merchant/merchant_login_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final AuthService _authService = AuthService();
  final AuthApiService _authApiService = AuthApiService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchAuthMode(bool isLogin) {
    if (_isLogin == isLogin) return;
    setState(() {
      _isLogin = isLogin;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _nameController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await _authService
            .signInWithEmailPassword(email, password)
            .timeout(const Duration(seconds: 15));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        // Gửi mã OTP xác thực email
        final otpSendResult = await _authApiService.sendRegistrationOtp(email);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }

        if (!otpSendResult.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(otpSendResult.message),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return;
        }

        if (!mounted) return;

        // Mở dialog nhập OTP
        final isVerified = await OtpVerificationDialog.show(
          context,
          email: email,
          initialCooldown: otpSendResult.cooldownSeconds ?? 60,
          initialDevOtp: otpSendResult.devOtp,
          onVerify: (otp) async {
            final verifyResult = await _authApiService.verifyRegistrationOtp(email, otp);
            if (!verifyResult.success) {
              throw Exception(verifyResult.message);
            }
            return true;
          },
          onResend: () async {
            return await _authApiService.sendRegistrationOtp(email);
          },
        );

        if (isVerified != true) {
          return;
        }

        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }

        final cred = await _authService
            .signUpWithEmailPassword(email, password)
            .timeout(const Duration(seconds: 15));
        if (fullName.isNotEmpty) {
          await cred.user?.updateDisplayName(fullName);
        }

        try {
          await ProfileApiService().getProfile();
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Xác thực thành công! Chào mừng bạn đến với SOOPI FOOD.'),
              backgroundColor: Colors.green,
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quá thời gian kết nối. Vui lòng kiểm tra lại kết nối Wi-Fi/4G!'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Đã có lỗi xảy ra. Vui lòng thử lại sau.';
      if (e.code == 'user-not-found') {
        message = 'Không tìm thấy tài khoản với email này.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Email hoặc mật khẩu không chính xác.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email này đã được sử dụng cho tài khoản khác.';
      } else if (e.code == 'weak-password') {
        message = 'Mật khẩu quá yếu (phải có ít nhất 6 ký tự).';
      } else if (e.code == 'invalid-email') {
        message = 'Định dạng email không hợp lệ.';
      } else if (e.code == 'network-request-failed') {
        message = 'Lỗi kết nối mạng. Vui lòng kiểm tra lại Internet.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showForgotPasswordDialog() {
    ForgotPasswordDialog.show(
      context,
      initialEmail: _emailController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFC),
      body: Stack(
        children: [
          // 1. Background Header Gradient với họa tiết thương hiệu
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isKeyboardOpen ? 180 : 280,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF5722),
                    Color(0xFFFF7A00),
                    Color(0xFFFFA000),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Các bóng tròn trang trí mờ nghệ thuật
                  Positioned(
                    top: -40,
                    right: -30,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Nội dung cuộn chính
          SafeArea(
            child: Column(
              children: [
                // Thanh công cụ phụ ở trên cùng (Dành cho Chủ quán & Cấu hình IP máy chủ)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Chip Cài đặt IP máy chủ BE
                      InkWell(
                        onTap: () => ApiConfig.showConfigDialog(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dns_outlined, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'Cài đặt IP BE',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Chip Chuyển sang Cổng Quản lý Chủ quán
                      InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const MerchantLoginScreen(),
                        )),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, color: Color(0xFFFF6D00), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Đối tác Chủ quán',
                                style: TextStyle(
                                  color: Color(0xFFFF6D00),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.chevron_right, color: Color(0xFFFF6D00), size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Logo & Tiêu đề chào mừng (Ẩn bớt logo khi bàn phím mở để không bị chật)
                if (!isKeyboardOpen) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 82,
                      height: 82,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          "img/logo.png",
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.fastfood_rounded,
                            color: Colors.orange,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SOOPI FOOD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Giao món nhanh • Nóng hổi • Đậm vị',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  const SizedBox(height: 10),
                ],

                // 3. Card trắng chứa Form Đăng nhập / Đăng ký
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Segmented Tab Switcher (Đăng nhập / Đăng ký)
                              _buildSegmentedTab(),

                              const SizedBox(height: 24),

                              // Form Fields
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                child: Column(
                                  children: [
                                    // Trường Họ và tên (chỉ hiện khi Đăng ký)
                                    if (!_isLogin) ...[
                                      _buildModernInput(
                                        label: 'Họ và tên',
                                        hintText: 'Nhập họ và tên của bạn',
                                        icon: Icons.person_outline_rounded,
                                        controller: _nameController,
                                        validator: (val) {
                                          if (!_isLogin) {
                                            if (val == null || val.trim().isEmpty) return 'Vui lòng nhập họ và tên';
                                            if (val.trim().length < 2) return 'Họ tên phải từ 2 ký tự';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    // Trường Email
                                    _buildModernInput(
                                      label: 'Địa chỉ Email',
                                      hintText: 'name@example.com',
                                      icon: Icons.mail_outline_rounded,
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (val) {
                                        if (val == null || val.trim().isEmpty) return 'Vui lòng nhập địa chỉ email';
                                        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                        if (!emailRegex.hasMatch(val.trim())) {
                                          return 'Email không hợp lệ (Ví dụ: name@gmail.com)';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // Trường Mật khẩu
                                    _buildModernInput(
                                      label: 'Mật khẩu',
                                      hintText: '••••••••',
                                      icon: Icons.lock_outline_rounded,
                                      isPassword: true,
                                      obscureText: _obscurePassword,
                                      onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                                      controller: _passwordController,
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return 'Vui lòng nhập mật khẩu';
                                        if (val.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
                                        return null;
                                      },
                                    ),

                                    // Trường Xác nhận mật khẩu (chỉ hiện khi Đăng ký)
                                    if (!_isLogin) ...[
                                      const SizedBox(height: 16),
                                      _buildModernInput(
                                        label: 'Xác nhận lại mật khẩu',
                                        hintText: '••••••••',
                                        icon: Icons.shield_outlined,
                                        isPassword: true,
                                        obscureText: _obscureConfirmPassword,
                                        onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                        controller: _confirmPasswordController,
                                        validator: (val) {
                                          if (!_isLogin) {
                                            if (val == null || val.isEmpty) return 'Vui lòng nhập lại mật khẩu';
                                            if (val != _passwordController.text) return 'Mật khẩu xác nhận không khớp';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Tùy chọn Quên mật khẩu & Ghi nhớ
                              const SizedBox(height: 8),
                              if (_isLogin)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                            activeColor: const Color(0xFFFF6D00),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Ghi nhớ tôi',
                                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    TextButton(
                                      onPressed: _showForgotPasswordDialog,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Quên mật khẩu?',
                                        style: TextStyle(
                                          color: Color(0xFFFF6D00),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Bằng việc đăng ký, bạn đồng ý với Điều khoản dịch vụ & Chính sách bảo mật của SOOPI FOOD.',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.3),
                                  ),
                                ),

                              const SizedBox(height: 22),

                              // Nút CTA chính (Gradient Button)
                              Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF5722), Color(0xFFFF8A00)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF6D00).withValues(alpha: 0.35),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submitAuth,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _isLogin ? 'ĐĂNG NHẬP NGAY' : 'TIẾP TỤC ĐĂNG KÝ',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                                          ],
                                        ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Đường phân cách "Hoặc tiếp tục với"
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: Text(
                                      'HOẶC TIẾP TỤC VỚI',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // Nút Đăng nhập Mạng xã hội hiện đại
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSocialPill(
                                      label: 'Google',
                                      iconWidget: _buildGoogleGIcon(),
                                      onTap: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Tính năng Google Sign-In đang được kết nối.')),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _buildSocialPill(
                                      label: 'Facebook',
                                      iconWidget: const Icon(Icons.facebook, color: Color(0xFF1877F2), size: 24),
                                      onTap: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Tính năng Facebook Sign-In đang được kết nối.')),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Chuyển đổi Đăng nhập / Đăng ký ở chân trang
                              Center(
                                child: GestureDetector(
                                  onTap: () => _switchAuthMode(!_isLogin),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                      children: [
                                        TextSpan(text: _isLogin ? 'Chưa có tài khoản? ' : 'Đã có tài khoản? '),
                                        TextSpan(
                                          text: _isLogin ? 'Đăng ký ngay' : 'Đăng nhập',
                                          style: const TextStyle(
                                            color: Color(0xFFFF6D00),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Segmented Tab Switcher đẹp mắt
  Widget _buildSegmentedTab() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _switchAuthMode(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isLogin
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Đăng nhập',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _isLogin ? FontWeight.bold : FontWeight.w600,
                    color: _isLogin ? const Color(0xFFFF6D00) : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _switchAuthMode(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: !_isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !_isLogin
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Đăng ký mới',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: !_isLogin ? FontWeight.bold : FontWeight.w600,
                    color: !_isLogin ? const Color(0xFFFF6D00) : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Input TextField hiện đại với Label nổi
  Widget _buildModernInput({
    required String label,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    TextEditingController? controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isPassword ? obscureText : false,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            prefixIcon: Icon(icon, color: const Color(0xFFFF7A00), size: 20),
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF6D00), width: 1.8),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Nút Social Login dạng Pill thanh lịch
  Widget _buildSocialPill({
    required String label,
    required Widget iconWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Icon Google vẽ bằng ký tự chuẩn màu Google
  Widget _buildGoogleGIcon() {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFFEA4335),
          fontWeight: FontWeight.w900,
          fontSize: 20,
          fontFamily: 'sans-serif',
        ),
      ),
    );
  }
}
