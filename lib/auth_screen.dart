import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home.dart'; // Import để điều hướng sang HomeScreen
import 'services/auth_service.dart'; // Import AuthService

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Khởi tạo AuthService
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        // Sử dụng AuthService để đăng nhập
        await _authService.signInWithEmailPassword(email, password);
      } else {
        // Sử dụng AuthService để đăng ký
        await _authService.signUpWithEmailPassword(email, password);
      }
      
      // Thành công, chuyển sang HomeScreen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Đã có lỗi xảy ra. Vui lòng thử lại sau.';
      if (e.code == 'user-not-found') {
        message = 'Không tìm thấy người dùng với email này.';
      } else if (e.code == 'wrong-password') {
        message = 'Sai mật khẩu.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email này đã được sử dụng.';
      } else if (e.code == 'weak-password') {
        message = 'Mật khẩu quá yếu.';
      } else if (e.code == 'invalid-email') {
        message = 'Email không hợp lệ.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset("img/logo.png"),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _isLogin ? 'Đăng nhập để tiếp tục' : 'Tạo tài khoản mới',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
              const SizedBox(height: 40),
              
              // Các trường nhập liệu
              if (!_isLogin)
                _buildTextField(
                  hintText: 'Họ và tên',
                  icon: Icons.person_outline,
                  controller: _nameController,
                ),
              if (!_isLogin) const SizedBox(height: 16),
              
              _buildTextField(
                hintText: 'Email',
                icon: Icons.email_outlined,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'Mật khẩu',
                icon: Icons.lock_outline,
                isPassword: true,
                controller: _passwordController,
              ),
              
              if (_isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Quên mật khẩu?', style: TextStyle(color: Colors.orange)),
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
                  elevation: 0,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton('Google', Colors.red),
                  const SizedBox(width: 16),
                  _buildSocialButton('Facebook', Colors.blue, icon: Icons.facebook),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // Chuyển đổi giữa Đăng nhập / Đăng ký
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isLogin ? 'Chưa có tài khoản? ' : 'Đã có tài khoản? ',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isLogin = !_isLogin;
                      });
                    },
                    child: Text(
                      _isLogin ? 'Đăng ký ngay' : 'Đăng nhập',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String hintText, 
    required IconData icon, 
    bool isPassword = false, 
    TextEditingController? controller,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          prefixIcon: Icon(icon, color: Colors.grey),
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          suffixIcon: isPassword 
            ? const Icon(Icons.visibility_off_outlined, color: Colors.grey)
            : null,
        ),
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
