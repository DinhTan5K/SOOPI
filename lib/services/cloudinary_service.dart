import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';

import 'api_config.dart';
import 'profile_api_service.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  // Cloudinary credentials (đồng bộ cấu hình appsettings.json)
  static const String cloudName = 'di3r34ji1';
  static const String apiKey = '369758839977844';
  static const String apiSecret = 'YvnO1TC-QNf2t1JMoigxEg76NnI';
  static const String uploadFolder = 'soopifood';

  final ImagePicker _picker = ImagePicker();

  /// Cho phép người dùng chụp ảnh từ camera hoặc chọn từ thư viện điện thoại
  Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      debugPrint('[CloudinaryService] Lỗi khi chọn ảnh: $e');
      return null;
    }
  }

  /// Tải ảnh lên Cloudinary
  /// Ưu tiên 1: Thông qua Backend C# API (POST /api/upload/image)
  /// Dự phòng 2: Tải trực tiếp lên Cloudinary REST API với chữ ký bảo mật (Signed Upload)
  Future<String?> uploadImage(dynamic imageFile) async {
    if (imageFile == null) return null;

    // 1. Thử upload qua Backend API trước
    try {
      final backendUrl = await _uploadViaBackend(imageFile);
      if (backendUrl != null && backendUrl.isNotEmpty) {
        debugPrint('[CloudinaryService] Upload thành công qua Backend: $backendUrl');
        return backendUrl;
      }
    } catch (e) {
      debugPrint('[CloudinaryService] Upload qua Backend không thành công ($e), chuyển sang Direct Cloudinary.');
    }

    // 2. Dự phòng: Upload trực tiếp lên Cloudinary
    try {
      final directUrl = await _uploadDirectToCloudinary(imageFile);
      if (directUrl != null && directUrl.isNotEmpty) {
        debugPrint('[CloudinaryService] Upload thành công trực tiếp lên Cloudinary: $directUrl');
        return directUrl;
      }
    } catch (e) {
      debugPrint('[CloudinaryService] Lỗi upload trực tiếp lên Cloudinary: $e');
    }

    return null;
  }

  /// Upload thông qua Backend API
  Future<String?> _uploadViaBackend(dynamic imageFile) async {
    final baseUrl = ApiConfig().baseUrl;
    final uri = Uri.parse('$baseUrl/upload/image?folder=$uploadFolder');

    final request = http.MultipartRequest('POST', uri);

    // Đính kèm Token Firebase và Dev headers
    final headers = await ProfileApiService().getHeaders();
    request.headers.addAll(headers);

    if (imageFile is XFile) {
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: imageFile.name.isNotEmpty ? imageFile.name : 'avatar.jpg',
      ));
    } else if (imageFile is String) {
      request.files.add(await http.MultipartFile.fromPath('file', imageFile));
    } else if (imageFile is List<int>) {
      request.files.add(http.MultipartFile.fromBytes('file', imageFile, filename: 'avatar.jpg'));
    } else {
      return null;
    }

    final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['imageUrl']?.toString();
    } else {
      debugPrint('[CloudinaryService] Backend phản hồi mã lỗi: ${response.statusCode} - ${response.body}');
      return null;
    }
  }

  /// Upload trực tiếp lên Cloudinary với SHA1 Signature
  Future<String?> _uploadDirectToCloudinary(dynamic imageFile) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // Tính chữ ký bảo mật SHA1 theo chuẩn Cloudinary: folder=...&timestamp=... + apiSecret
    final stringToSign = 'folder=$uploadFolder&timestamp=$timestamp$apiSecret';
    final signature = sha1.convert(utf8.encode(stringToSign)).toString();

    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['folder'] = uploadFolder
      ..fields['signature'] = signature;

    if (imageFile is XFile) {
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: imageFile.name.isNotEmpty ? imageFile.name : 'avatar.jpg',
      ));
    } else if (imageFile is String) {
      request.files.add(await http.MultipartFile.fromPath('file', imageFile));
    } else if (imageFile is List<int>) {
      request.files.add(http.MultipartFile.fromBytes('file', imageFile, filename: 'avatar.jpg'));
    } else {
      return null;
    }

    final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['secure_url']?.toString() ?? json['url']?.toString();
    } else {
      debugPrint('[CloudinaryService] Cloudinary phản hồi lỗi: ${response.statusCode} - ${response.body}');
      return null;
    }
  }
}
