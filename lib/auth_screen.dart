import 'package:flutter/material.dart';
import 'merchant/merchant_login_screen.dart';
import 'main.dart'; // Import để điều hướng sang MainScreen

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

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
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
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
                ),
              if (!_isLogin) const SizedBox(height: 16),
              
              _buildTextField(
                hintText: 'Email hoặc Số điện thoại',
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'Mật khẩu',
                icon: Icons.lock_outline,
                isPassword: true,
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
                onPressed: () {
                  // Chuyển hướng sang màn hình Home khi đăng nhập thành công
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MainScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
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
                  _buildSocialButton('Facebook', Colors.blue, icon: Icons.facebook),
                ],
              ),
              
              const SizedBox(height: 40),
              
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

  Widget _buildTextField({required String hintText, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        obscureText: isPassword,
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
