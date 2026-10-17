import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'profile_api_service.dart';

class MerchantApiService {
  MerchantApiService({http.Client? client, Future<String?> Function()? token})
    : _client = client ?? http.Client(),
      _token =
          token ??
          (() async => FirebaseAuth.instance.currentUser?.getIdToken());
  final http.Client _client;
  final Future<String?> Function() _token;

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await _token();
    if (token == null) {
      throw Exception('Vui lòng đăng nhập tài khoản chủ quán.');
    }
    final request = http.Request(
      method,
      Uri.parse('${ProfileApiService().baseUrl}/merchant/$path'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    );
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final data = response.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data is Map
            ? data['error'] ??
                  data['title'] ??
                  'Yêu cầu thất bại (${response.statusCode}).'
            : 'Yêu cầu thất bại (${response.statusCode}).',
      );
    }
    return data;
  }

  Future<String> upload(String restaurantId, String encoded) async {
    final token = await _token();
    if (token == null) throw Exception('Vui lòng đăng nhập.');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${ProfileApiService().baseUrl}/merchant/restaurants/$restaurantId/images',
      ),
    );
    request.headers['Authorization'] = 'Bearer $token';
    final bytes = base64Decode(encoded);
    final subtype = bytes.length >= 8 && bytes[0] == 137
        ? 'png'
        : bytes.length >= 12 && bytes[0] == 82
        ? 'webp'
        : 'jpeg';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'menu.$subtype',
        contentType: MediaType('image', subtype),
      ),
    );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 30)),
    );
    return _decode(response)['imageUrl'] as String;
  }
}
