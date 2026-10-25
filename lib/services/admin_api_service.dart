import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'profile_api_service.dart';

class AdminApiService {
  AdminApiService({http.Client? client, Future<String?> Function()? token})
      : _client = client ?? http.Client(),
        _token = token ?? (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  final http.Client _client;
  final Future<String?> Function() _token;

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await _token();
    if (token == null) {
      throw Exception('Vui lòng đăng nhập tài khoản Quản trị viên (Admin).');
    }

    final uri = Uri.parse('${ProfileApiService().baseUrl}/admin/$path');
    final request = http.Request(method, uri);
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'bypass-tunnel-reminder': 'true',
    });

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    );

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 204) return null;

    final data = response.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = data is Map
          ? (data['error'] ?? data['title'] ?? data['detail'] ?? 'Lỗi máy chủ (${response.statusCode})')
          : 'Yêu cầu thất bại (${response.statusCode}).';
      throw Exception(msg);
    }
    return data;
  }

  // --- DASHBOARD ---
  Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await request('GET', 'dashboard/stats');
    return Map<String, dynamic>.from(res as Map);
  }

  // --- RESTAURANTS ---
  Future<Map<String, dynamic>> getRestaurants({
    String? query,
    String? status,
    bool? locked,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (locked != null) params['locked'] = locked.toString();

    final queryString = Uri(queryParameters: params).query;
    final res = await request('GET', 'restaurants?$queryString');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> getRestaurantDetail(String id) async {
    final res = await request('GET', 'restaurants/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> approveRestaurant(String id) async {
    await request('POST', 'restaurants/$id/approve');
  }

  Future<void> rejectRestaurant(String id, String reason) async {
    await request('POST', 'restaurants/$id/reject', {'reason': reason});
  }

  Future<void> lockRestaurant(String id, bool locked, String? reason) async {
    await request('PATCH', 'restaurants/$id/lock', {
      'locked': locked,
      'reason': reason,
    });
  }

  // --- USERS ---
  Future<Map<String, dynamic>> getUsers({
    String? query,
    String? role,
    bool? locked,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (role != null && role.isNotEmpty) params['role'] = role;
    if (locked != null) params['locked'] = locked.toString();

    final queryString = Uri(queryParameters: params).query;
    final res = await request('GET', 'users?$queryString');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> getUserDetail(String id) async {
    final res = await request('GET', 'users/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> lockUser(String id, bool locked, String? reason) async {
    await request('PATCH', 'users/$id/lock', {
      'locked': locked,
      'reason': reason,
    });
  }

  Future<void> updateUserRole(String id, String role) async {
    await request('PATCH', 'users/$id/role', {'role': role});
  }

  // --- ORDERS ---
  Future<Map<String, dynamic>> getOrders({
    String? query,
    String? status,
    String? restaurantId,
    String? shipperId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (restaurantId != null && restaurantId.isNotEmpty) params['restaurantId'] = restaurantId;
    if (shipperId != null && shipperId.isNotEmpty) params['shipperId'] = shipperId;

    final queryString = Uri(queryParameters: params).query;
    final res = await request('GET', 'orders?$queryString');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> getOrderDetail(String id) async {
    final res = await request('GET', 'orders/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  // --- VOUCHERS ---
  Future<List<dynamic>> getGlobalVouchers() async {
    final res = await request('GET', 'vouchers');
    return res is List ? res : [];
  }

  Future<Map<String, dynamic>> createGlobalVoucher(Map<String, dynamic> data) async {
    final res = await request('POST', 'vouchers', data);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> toggleGlobalVoucherStatus(String id, bool isActive) async {
    await request('PATCH', 'vouchers/$id/status', {'isActive': isActive});
  }

  // --- AUDITS ---
  Future<Map<String, dynamic>> getAudits({
    String? targetType,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (targetType != null && targetType.isNotEmpty) params['targetType'] = targetType;

    final queryString = Uri(queryParameters: params).query;
    final res = await request('GET', 'audits?$queryString');
    return Map<String, dynamic>.from(res as Map);
  }
}
