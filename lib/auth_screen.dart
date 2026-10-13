import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home.dart';
import 'services/auth_service.dart';
import 'services/auth_api_service.dart';
import 'services/profile_api_service.dart';
import 'widgets/otp_verification_dialog.dart';
import 'merchant/merchant_login_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  // Khởi tạo AuthService và AuthApiService
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

  void _switchAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submitAuth() async {
    // Kích hoạt validate toàn bộ các trường trong Form
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
        await _authService.signInWithEmailPassword(email, password);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        // 1. Gửi mã xác thực OTP qua Email chống spam
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

        // 2. Mở hộp thoại nhập mã OTP 6 số
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
          // Người dùng đã hủy hoặc đóng hộp thoại xác thực OTP
          return;
        }

        // 3. Đã xác thực OTP thành công -> Tiến hành tạo tài khoản
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }

        final cred = await _authService.signUpWithEmailPassword(email, password);
        if (fullName.isNotEmpty) {
          await cred.user?.updateDisplayName(fullName);
        }
        // Tự động đồng bộ tạo hồ sơ người dùng trong Database PostgreSQL
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
    } on FirebaseAuthException catch (e) {
      String message = 'Đã có lỗi xảy ra. Vui lòng thử lại sau.';
      if (e.code == 'user-not-found') {
        message = 'Không tìm thấy tài khoản với email này.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Mật khẩu không chính xác.';
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
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    final forgotFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.orange),
            SizedBox(width: 8),
            Text('Quên mật khẩu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: forgotFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập email tài khoản của bạn để nhận liên kết khôi phục mật khẩu:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Vui lòng nhập email';
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(val.trim())) return 'Email không đúng định dạng';
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'vidu@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (!forgotFormKey.currentState!.validate()) return;
              final targetEmail = resetEmailController.text.trim();
              Navigator.pop(ctx);

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: targetEmail);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã gửi email khôi phục tới $targetEmail!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi: ${e.message}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Gửi email'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const MerchantLoginScreen(),
                  )),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Dành cho chủ quán'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Image.asset("img/logo.png"),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tên App
                Center(
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1),
                      children: [
                        TextSpan(text: 'SOOPI '),
                        TextSpan(text: 'FOOD', style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _isLogin ? 'Đăng nhập để tiếp tục' : 'Tạo tài khoản mới',
                    style: const TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Trường: Họ và tên (chỉ hiện khi Đăng ký)
                if (!_isLogin) ...[
                  _buildTextFormField(
                    hintText: 'Họ và tên *',
                    icon: Icons.person_outline,
                    controller: _nameController,
                    validator: (val) {
                      if (!_isLogin) {
                        if (val == null || val.trim().isEmpty) return 'Vui lòng nhập họ và tên';
                        if (val.trim().length < 2) return 'Họ và tên phải từ 2 ký tự trở lên';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Trường: Email
                _buildTextFormField(
                  hintText: 'Email *',
                  icon: Icons.email_outlined,
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

                // Trường: Mật khẩu
                _buildTextFormField(
                  hintText: 'Mật khẩu *',
                  icon: Icons.lock_outline,
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

                // Trường: Xác nhận mật khẩu (chỉ hiện khi Đăng ký)
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  _buildTextFormField(
                    hintText: 'Xác nhận lại mật khẩu *',
                    icon: Icons.lock_reset_outlined,
                    isPassword: true,
                    obscureText: _obscureConfirmPassword,
                    onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    controller: _confirmPasswordController,
                    validator: (val) {
                      if (!_isLogin) {
                        if (val == null || val.isEmpty) return 'Vui lòng nhập lại mật khẩu';
                        if (val != _passwordController.text) return 'Mật khẩu xác nhận không trùng khớp';
                      }
                      return null;
                    },
                  ),
                ],
                
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text('Quên mật khẩu?', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                
                // Nút Đăng nhập / Đăng ký
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 1,
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                    : Text(
                        _isLogin ? 'ĐĂNG NHẬP' : 'ĐĂNG KÝ',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                ),
                
                const SizedBox(height: 24),
                
                // Đường kẻ chia
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('HOẶC', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Đăng nhập qua mạng xã hội
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _buildSocialButton('Google', Colors.red),
                    const SizedBox(width: 16),
                    _buildSocialButton('Facebook', Colors.blue, icon: Icons.facebook),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Chuyển đổi giữa Đăng nhập / Đăng ký
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    Text(
                      _isLogin ? 'Chưa có tài khoản? ' : 'Đã có tài khoản? ',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    GestureDetector(
                      onTap: _switchAuthMode,
                      child: Text(
                        _isLogin ? 'Đăng ký ngay' : 'Đăng nhập',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFormField({
    required String hintText, 
    required IconData icon, 
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    TextEditingController? controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? obscureText : false,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        suffixIcon: isPassword 
          ? IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.grey.shade600,
              ),
              onPressed: onToggleObscure,
            )
          : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 12, height: 1.2),
      ),
    );
  }

  Widget _buildSocialButton(String name, Color color, {IconData? icon}) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) 
              Icon(icon, color: color)
            else 
              Text('G', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
