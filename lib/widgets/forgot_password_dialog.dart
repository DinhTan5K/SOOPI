import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordDialog extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordDialog({
    super.key,
    this.initialEmail,
  });

  /// Hiển thị hộp thoại Quên mật khẩu
  static Future<void> show(BuildContext context, {String? initialEmail}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ForgotPasswordDialog(initialEmail: initialEmail),
    );
  }

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;
  String _sentToEmail = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail?.trim() ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Gửi email đặt lại mật khẩu qua Firebase Auth với timeout 15s
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _sentToEmail = email;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Quá thời gian kết nối. Vui lòng kiểm tra lại mạng Wi-Fi/4G của bạn!';
        });
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Đã có lỗi xảy ra. Vui lòng thử lại sau.';
      switch (e.code) {
        case 'user-not-found':
          msg = 'Không tìm thấy tài khoản nào khớp với email này.';
          break;
        case 'invalid-email':
          msg = 'Địa chỉ email không đúng định dạng.';
          break;
        case 'too-many-requests':
          msg = 'Bạn đã gửi yêu cầu quá nhiều lần. Vui lòng đợi vài phút rồi thử lại.';
          break;
        case 'network-request-failed':
          msg = 'Lỗi kết nối mạng. Vui lòng kiểm tra lại Internet hoặc Wi-Fi.';
          break;
        default:
          if (e.message != null && e.message!.isNotEmpty) {
            msg = e.message!;
          }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Lỗi không xác định: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Điều chỉnh khoảng cách khi bàn phím ảo hiển thị
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thanh kéo drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_isSuccess) _buildSuccessContent() else _buildFormContent(),
            ],
          ),
        ),
      ),
    );
  }

  /// Giao diện khi người dùng nhập email yêu cầu reset mật khẩu
  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon minh họa
          Center(
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                size: 40,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Quên mật khẩu?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'Nhập địa chỉ email tài khoản của bạn. SOOPI sẽ gửi liên kết an toàn để bạn đặt lại mật khẩu mới.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Ô nhập Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleSendResetLink(),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập địa chỉ email';
              }
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(value.trim())) {
                return 'Địa chỉ email không đúng định dạng';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Địa chỉ Email',
              hintText: 'vidu@gmail.com',
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.orange),
              suffixIcon: _emailController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _emailController.clear();
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.orange, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Nút xác nhận gửi
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSendResetLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Gửi liên kết khôi phục',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),

          const SizedBox(height: 12),

          // Nút hủy/quay lại
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Quay lại',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Giao diện khi đã gửi email thành công
  Widget _buildSuccessContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 44,
              color: Colors.green,
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Đã gửi email khôi phục!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
            children: [
              const TextSpan(text: 'Chúng tôi đã gửi hướng dẫn đặt lại mật khẩu đến:\n'),
              TextSpan(
                text: _sentToEmail,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.amber.shade900),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Vui lòng kiểm tra Hộp thư đến (hoặc thư mục Spam / Thư rác) và bấm vào liên kết trong email để tạo mật khẩu mới.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.amber.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Tôi đã hiểu, quay lại đăng nhập',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: () {
            setState(() {
              _isSuccess = false;
              _errorMessage = null;
            });
          },
          child: const Text(
            'Chưa nhận được email? Thử lại',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
