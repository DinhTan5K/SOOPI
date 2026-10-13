import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'profile_api_service.dart';

class OtpSendResult {
  final bool success;
  final String message;
  final int? cooldownSeconds;
  final int? expiresInMinutes;
  final String? devOtp;

  OtpSendResult({
    required this.success,
    required this.message,
    this.cooldownSeconds,
    this.expiresInMinutes,
    this.devOtp,
  });
}

class OtpVerifyResult {
  final bool success;
  final String message;
  final String? verificationToken;
  final int? remainingAttempts;

  OtpVerifyResult({
    required this.success,
    required this.message,
    this.verificationToken,
    this.remainingAttempts,
  });
}

class AuthApiService {
  static final AuthApiService _instance = AuthApiService._internal();
  factory AuthApiService() => _instance;
  AuthApiService._internal();

  String get _baseUrl => ProfileApiService().baseUrl;

  /// Gửi mã xác thực OTP qua email khi đăng ký
  Future<OtpSendResult> sendRegistrationOtp(String email) async {
    try {
      final url = Uri.parse('$_baseUrl/auth/send-registration-otp');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return OtpSendResult(
          success: true,
          message: data['message'] ?? 'Mã xác thực đã được gửi tới email của bạn.',
          cooldownSeconds: data['cooldownSeconds'] as int?,
          expiresInMinutes: data['expiresInMinutes'] as int?,
          devOtp: data['devOtp'] as String?,
        );
      } else if (response.statusCode == 429) {
        return OtpSendResult(
          success: false,
          message: data['message'] ?? 'Bạn đang gửi yêu cầu quá nhanh. Vui lòng chờ.',
          cooldownSeconds: data['cooldownSeconds'] as int?,
        );
      } else {
        return OtpSendResult(
          success: false,
          message: data['message'] ?? 'Gửi mã OTP thất bại. Vui lòng thử lại.',
        );
      }
    } catch (e) {
      debugPrint('[AuthApiService] Lỗi kết nối gửi OTP: $e');
      return OtpSendResult(
        success: false,
        message: 'Không thể kết nối đến máy chủ xác thực email. Vui lòng kiểm tra kết nối mạng backend ($_baseUrl).',
      );
    }
  }

  /// Xác thực mã OTP 6 số
  Future<OtpVerifyResult> verifyRegistrationOtp(String email, String otp) async {
    try {
      final url = Uri.parse('$_baseUrl/auth/verify-registration-otp');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return OtpVerifyResult(
          success: true,
          message: data['message'] ?? 'Xác thực OTP thành công.',
          verificationToken: data['verificationToken'] as String?,
        );
      } else {
        return OtpVerifyResult(
          success: false,
          message: data['message'] ?? 'Mã OTP không hợp lệ hoặc đã hết hạn.',
          remainingAttempts: data['remainingAttempts'] as int?,
        );
      }
    } catch (e) {
      debugPrint('[AuthApiService] Lỗi kết nối xác thực OTP: $e');
      return OtpVerifyResult(
        success: false,
        message: 'Không thể kết nối đến máy chủ xác thực. Vui lòng thử lại.',
      );
    }
  }
}
