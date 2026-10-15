import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'merchant_screen.dart';
import '../services/auth_api_service.dart';
import '../services/profile_api_service.dart';
import '../widgets/otp_verification_dialog.dart';

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
            .createUserWithEmailAndPassword(email: email, password: password);
        // Account creation succeeded even if updating the display name fails.
        try {
          await credential.user?.updateDisplayName(_name.text.trim());
        } catch (_) {}
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      ProfileApiService().clearCache();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MerchantScreen()),
      );
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dành cho chủ quán')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset('img/logo.png', width: 96, height: 96),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Quán của bạn,\ntrong tầm tay.',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _registering
                        ? 'Tạo tài khoản để đăng ký và quản lý quán ăn.'
                        : 'Đăng nhập để quản lý quán và thực đơn.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  if (_registering) ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_loading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Họ tên chủ quán',
                        border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
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
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                        onPressed: () => setState(() => _hidden = !_hidden),
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
                        border: OutlineInputBorder(),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
  );
}
