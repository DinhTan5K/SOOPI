import 'dart:async';

import 'package:flutter/material.dart';

import 'merchant_style.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'merchant_screen.dart';
import '../services/auth_api_service.dart';
import '../services/profile_api_service.dart';
import '../services/merchant_api_service.dart';
import '../widgets/otp_verification_dialog.dart';
import '../widgets/forgot_password_dialog.dart';

class MerchantLoginScreen extends StatefulWidget {
  const MerchantLoginScreen({super.key});
  @override
  State<MerchantLoginScreen> createState() => _MerchantLoginScreenState();
}

class _MerchantLoginScreenState extends State<MerchantLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _registering = false;
  bool _hidden = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  bool _loading = false;
  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (_registering) {
        final api = AuthApiService();
        final sent = await api.sendRegistrationOtp(email);
        if (!mounted) return;
        if (!sent.success) {
          setState(() => _error = sent.message);
          return;
        }
        final verified = await OtpVerificationDialog.show(
          context,
          email: email,
          initialCooldown: sent.cooldownSeconds ?? 60,
          initialDevOtp: sent.devOtp,
          onVerify: (otp) async {
            final result = await api.verifyRegistrationOtp(email, otp);
            if (!result.success) throw Exception(result.message);
            return true;
          },
          onResend: () => api.sendRegistrationOtp(email),
        );
        if (verified != true || !mounted) return;
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 15));
        // Account creation succeeded even if updating the display name fails.
        try {
          await credential.user?.updateDisplayName(_name.text.trim());
        } catch (_) {}

        // Đăng ký quyền Chủ quán (Role = Owner) lên Backend
        try {
          await MerchantApiService().request('POST', 'register');
          await ProfileApiService().cacheUserRole('Owner');
        } catch (e) {
          debugPrint('Lỗi kích hoạt quyền Chủ quán: $e');
        }
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 15));

        // Kiểm tra phân quyền (Role): Chỉ tài khoản Owner hoặc Admin mới được phép vào Cổng Chủ quán!
        ProfileApiService().clearCache();
        try {
          final profile = await ProfileApiService().getProfile();
          final role = profile.role.toLowerCase();
          if (role != 'owner' && role != 'restaurantowner' && role != 'admin') {
            await FirebaseAuth.instance.signOut();
            ProfileApiService().clearCache();
            if (!mounted) return;
            setState(() {
              _error = 'Tài khoản của bạn là Khách hàng (Customer), không có quyền truy cập Cổng Quản lý Chủ quán.\n\nVui lòng đăng nhập bằng tài khoản Chủ quán hoặc đăng ký tài khoản Chủ quán mới!';
            });
            return;
          }
          await ProfileApiService().cacheUserRole(profile.role);
        } catch (e) {
          await FirebaseAuth.instance.signOut();
          ProfileApiService().clearCache();
          if (!mounted) return;
          setState(() {
            _error = 'Không thể xác thực quyền truy cập Chủ quán: $e';
          });
          return;
        }
      }
      ProfileApiService().clearCache();
      await ProfileApiService().cacheUserRole('Owner');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MerchantScreen()),
        (route) => false,
      );
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'Quá thời gian kết nối. Vui lòng kiểm tra lại mạng Wi-Fi/4G của bạn.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'email-already-in-use' =>
              'Email đã được đăng ký. Hãy chuyển sang đăng nhập.',
            'weak-password' => 'Mật khẩu phải có ít nhất 6 ký tự.',
            'invalid-credential' ||
            'wrong-password' ||
            'user-not-found' => 'Email hoặc mật khẩu không đúng.',
            'network-request-failed' =>
              'Không thể kết nối. Vui lòng kiểm tra mạng.',
            _ => error.message ?? 'Không thể xác thực tài khoản.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không thể xác thực tài khoản. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => MerchantAppearance(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Dành cho chủ quán'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: MerchantStyle.gradient),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const MerchantSectionHeader(
                          title: 'Quán của bạn,\ntrong tầm tay.',
                          subtitle: 'Đồng hành cùng SOOPI FOOD',
                          icon: Icons.storefront_rounded,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _registering
                              ? 'Tạo tài khoản để đăng ký và quản lý quán ăn.'
                              : 'Đăng nhập để quản lý quán và thực đơn.',
                          style: const TextStyle(color: MerchantStyle.muted),
                        ),
                        const SizedBox(height: 28),
                        if (_registering) ...[
                          TextFormField(
                            controller: _name,
                            enabled: !_loading,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Họ tên chủ quán',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Nhập họ tên.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _email,
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email chủ quán',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) =>
                              v == null ||
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(v.trim())
                              ? 'Nhập email hợp lệ.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !_loading,
                          obscureText: _hidden,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: const Icon(Icons.lock_outline),

                            suffixIcon: IconButton(
                              tooltip: _hidden
                                  ? 'Hiện mật khẩu'
                                  : 'Ẩn mật khẩu',
                              onPressed: () =>
                                  setState(() => _hidden = !_hidden),
                              icon: Icon(
                                _hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Nhập mật khẩu.'
                              : _registering && v.length < 6
                              ? 'Mật khẩu phải có ít nhất 6 ký tự.'
                              : null,
                        ),
                        if (_registering) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPassword,
                            enabled: !_loading,
                            obscureText: _hidden,
                            decoration: const InputDecoration(
                              labelText: 'Nhập lại mật khẩu',
                            ),
                            validator: (value) =>
                                value != _password.text ||
                                    value == null ||
                                    value.isEmpty
                                ? 'Mật khẩu nhập lại không khớp.'
                                : null,
                            onFieldSubmitted: (_) => _login(),
                          ),
                        ],
                        if (!_registering)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => ForgotPasswordDialog.show(
                                      context,
                                      initialEmail: _email.text.trim(),
                                    ),
                              child: const Text('Quên mật khẩu?'),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loading ? null : _login,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _registering
                                        ? 'Đăng ký tài khoản chủ quán'
                                        : 'Đăng nhập quản lý',
                                  ),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _registering = !_registering;
                                  _error = null;
                                  _form.currentState?.reset();
                                  _password.clear();
                                  _confirmPassword.clear();
                                }),
                          child: Text(
                            _registering
                                ? 'Đã có tài khoản? Đăng nhập'
                                : 'Chưa có tài khoản? Đăng ký chủ quán',
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
