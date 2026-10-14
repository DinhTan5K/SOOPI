import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_api_service.dart';

class OtpVerificationDialog extends StatefulWidget {
  final String email;
  final int initialCooldown;
  final String? initialDevOtp;
  final Future<bool> Function(String otp) onVerify;
  final Future<OtpSendResult> Function() onResend;

  const OtpVerificationDialog({
    super.key,
    required this.email,
    this.initialCooldown = 60,
    this.initialDevOtp,
    required this.onVerify,
    required this.onResend,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String email,
    int initialCooldown = 60,
    String? initialDevOtp,
    required Future<bool> Function(String otp) onVerify,
    required Future<OtpSendResult> Function() onResend,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OtpVerificationDialog(
        email: email,
        initialCooldown: initialCooldown,
        initialDevOtp: initialDevOtp,
        onVerify: onVerify,
        onResend: onResend,
      ),
    );
  }

  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  late int _countdownSeconds;
  Timer? _timer;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _currentDevOtp;

  @override
  void initState() {
    super.initState();
    _countdownSeconds = widget.initialCooldown;
    _currentDevOtp = widget.initialDevOtp;
    _startCountdown();

    // Auto focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _otpFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    if (_countdownSeconds <= 0) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleResend() async {
    if (_isResending || _countdownSeconds > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final result = await widget.onResend();

    if (!mounted) return;

    setState(() {
      _isResending = false;
      if (result.success) {
        _countdownSeconds = result.cooldownSeconds ?? 60;
        _currentDevOtp = result.devOtp;
        _otpController.clear();
        _startCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _errorMessage = result.message;
      }
    });
  }

  Future<void> _handleConfirm() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Vui lòng nhập đủ 6 chữ số mã OTP.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onVerify(otp);
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _isVerifying = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: bottomInset > 0 ? bottomInset + 20 : 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header Icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 38,
                  color: Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Xác thực Email',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle with Email
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                children: [
                  const TextSpan(text: 'Mã xác thực 6 chữ số đã được gửi đến:\n'),
                  TextSpan(
                    text: widget.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '(Vui lòng kiểm tra cả hòm thư Spam/Quảng cáo)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),

            // Dev Mode Badge (nếu có devOtp)
            if (_currentDevOtp != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, size: 20, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dev OTP: $_currentDevOtp (Click để điền)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.brown,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          _otpController.text = _currentDevOtp!;
                          _errorMessage = null;
                        });
                      },
                      child: const Text('Điền mã', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 6-digit PIN Boxes
            _buildOtpInputBoxes(),

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Countdown & Resend Button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_countdownSeconds > 0) ...[
                  Icon(Icons.timer_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Gửi lại mã sau ${_countdownSeconds}s',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ] else ...[
                  _isResending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                        )
                      : TextButton.icon(
                          onPressed: _handleResend,
                          icon: const Icon(Icons.refresh, size: 18, color: Colors.orange),
                          label: const Text(
                            'Gửi lại mã OTP',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                ],
              ],
            ),

            const SizedBox(height: 20),

            // Button Confirm
            ElevatedButton(
              onPressed: _isVerifying ? null : _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 1,
              ),
              child: _isVerifying
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      'XÁC NHẬN & TẠO TÀI KHOẢN',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),

            const SizedBox(height: 12),

            // Cancel / Change Email
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Thay đổi địa chỉ email',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpInputBoxes() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Invisible input field catching keyboard events
        Opacity(
          opacity: 0.0,
          child: TextField(
            controller: _otpController,
            focusNode: _otpFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (val) {
              setState(() {
                _errorMessage = null;
              });
              if (val.length == 6) {
                _handleConfirm();
              }
            },
          ),
        ),

        // Visual 6-box display
        GestureDetector(
          onTap: () {
            _otpFocusNode.requestFocus();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (index) {
              final text = _otpController.text;
              final digit = index < text.length ? text[index] : '';
              final isFocused = _otpFocusNode.hasFocus && (index == text.length || (index == 5 && text.length == 6));

              return Container(
                width: 46,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFocused
                        ? Colors.orange
                        : (_errorMessage != null
                            ? Colors.red.shade300
                            : (digit.isNotEmpty ? Colors.orange.shade300 : Colors.grey.shade300)),
                    width: isFocused ? 2 : 1.2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
