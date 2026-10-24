import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../models/user_address.dart';
import 'api_config.dart';

class ProfileApiService {
  static final ProfileApiService _instance = ProfileApiService._internal();
  factory ProfileApiService() => _instance;
  ProfileApiService._internal();

  String get baseUrl => ApiConfig().baseUrl;
  set baseUrl(String value) => ApiConfig().baseUrl = value;

  static List<String> get candidateBaseUrls => ApiConfig.defaultCandidates;

  // Bộ nhớ đệm tạm thời (In-memory Fallback) khi Backend .NET chưa chạy
  UserProfile? _localProfileCache;
  final List<UserAddress> _localAddressesCache = [];
  bool isConnectedToBackend = false;

  UserProfile? get cachedProfile => _localProfileCache;

  UserProfile getInitialProfile() {
    if (_localProfileCache != null) return _localProfileCache!;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = user?.email ?? '';
    final displayName = user?.displayName ?? '';
    return UserProfile(
      id: '',
      firebaseUid: uid,
      fullName: displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email.split('@')[0] : 'Người dùng'),
      email: email,
      phoneNumber: user?.phoneNumber ?? '',
      avatarUrl: user?.photoURL ?? '',
      gender: 'Nam',
      dateOfBirth: null,
      createdAt: DateTime.now(),
    );
  }

  void clearCache() {
    _localProfileCache = null;
    _localAddressesCache.clear();
    isConnectedToBackend = false;
  }

  Future<void> cacheUserRole(String role) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('soopi.user_role.$uid', role);
    } catch (_) {}
  }

  Future<String?> getCachedUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('soopi.user_role.$uid');
    } catch (_) {
      return null;
    }
  }

  Future<String> resolveUserRole() async {
    final cachedRole = await getCachedUserRole();
    try {
      final profile = await getProfile();
      if (isConnectedToBackend && profile.role.isNotEmpty) {
        await cacheUserRole(profile.role);
        return profile.role;
      }
    } catch (_) {}
    if (cachedRole != null && cachedRole.isNotEmpty) {
      return cachedRole;
    }
    return _localProfileCache?.role ?? 'Customer';
  }

  /// Lấy Firebase ID Token để đính kèm vào Header Authorization
  Future<Map<String, String>> getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'bypass-tunnel-reminder': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
      if (user != null) 'X-Firebase-Uid': user.uid,
      if (user?.email != null) 'X-Firebase-Email': user!.email!,
      if (user?.displayName != null && user!.displayName!.isNotEmpty)
        'X-Firebase-Name': Uri.encodeComponent(user.displayName!),
    };
  }

  /// Lấy thông tin Profile người dùng
  Future<UserProfile> getProfile() async {
    try {
      final headers = await getHeaders();

      final response = await http
          .get(Uri.parse('$baseUrl/user/profile'), headers: headers)
          .timeout(const Duration(milliseconds: 2500));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        _localProfileCache = UserProfile.fromJson(data);
        await cacheUserRole(_localProfileCache!.role);
        return _localProfileCache!;
      }
    } catch (_) {
      // Thử failover qua các candidate URL khác
      for (final candidate in candidateBaseUrls) {
        if (candidate == baseUrl) continue;
        try {
          final headers = await getHeaders();
          final response = await http
              .get(Uri.parse('$candidate/user/profile'), headers: headers)
              .timeout(const Duration(milliseconds: 1500));
          if (response.statusCode == 200) {
            baseUrl = candidate;
            isConnectedToBackend = true;
            final data = jsonDecode(response.body);
            _localProfileCache = UserProfile.fromJson(data);
            await cacheUserRole(_localProfileCache!.role);
            return _localProfileCache!;
          }
        } catch (_) {}
      }
      isConnectedToBackend = false;
    }

    // Fallback: Sử dụng dữ liệu Firebase hoặc cache hiện tại
    final savedRole = await getCachedUserRole();
    _localProfileCache ??= getInitialProfile().copyWith(
      role: (savedRole != null && savedRole.isNotEmpty) ? savedRole : 'Customer',
    );
    return _localProfileCache!;
  }

  /// Cập nhật thông tin Profile người dùng
  Future<UserProfile> updateProfile(UserProfile profile) async {
    try {
      final headers = await getHeaders();

      final response = await http
          .put(
            Uri.parse('$baseUrl/user/profile'),
            headers: headers,
            body: jsonEncode(profile.toJson()),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        _localProfileCache = UserProfile.fromJson(data);
        debugPrint('[ProfileApiService] Cập nhật thành công vào Database PostgreSQL: ${_localProfileCache?.avatarUrl}');
        // Cập nhật ngược lại Firebase displayName / photoURL nếu có
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          if (profile.fullName.isNotEmpty) {
            await currentUser.updateDisplayName(profile.fullName);
          }
          if (profile.avatarUrl.isNotEmpty) {
            await currentUser.updatePhotoURL(profile.avatarUrl);
          }
        }
        return _localProfileCache!;
      } else {
        debugPrint('[ProfileApiService] Backend phản hồi lỗi ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Cập nhật thất bại qua .NET Backend ($baseUrl): $e');
    }

    // Thử failover qua các candidateBaseUrls khác nếu baseUrl chính thất bại
    for (final candidate in candidateBaseUrls) {
      if (candidate == baseUrl) continue;
      try {
        final headers = await getHeaders();
        final res = await http.put(
          Uri.parse('$candidate/user/profile'),
          headers: headers,
          body: jsonEncode(profile.toJson()),
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          baseUrl = candidate;
          isConnectedToBackend = true;
          final data = jsonDecode(res.body);
          _localProfileCache = UserProfile.fromJson(data);
          debugPrint('[ProfileApiService] Cập nhật thành công qua candidate $candidate: ${_localProfileCache?.avatarUrl}');
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            if (profile.fullName.isNotEmpty) await currentUser.updateDisplayName(profile.fullName);
            if (profile.avatarUrl.isNotEmpty) await currentUser.updatePhotoURL(profile.avatarUrl);
          }
          return _localProfileCache!;
        }
      } catch (_) {}
    }
    isConnectedToBackend = false;
    throw Exception('Không thể kết nối đến máy chủ Backend ($baseUrl) để lưu vào cơ sở dữ liệu. Hãy kiểm tra kết nối mạng máy tính hoặc cắm cáp USB.');
  }

  /// Lấy danh sách địa chỉ giao hàng (Chỉ lấy dữ liệu thật từ Backend PostgreSQL)
  Future<List<UserAddress>> getAddresses() async {
    try {
      final headers = await getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/user/addresses'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
        final List<dynamic> data = jsonDecode(response.body);
        final list = data.map((e) => UserAddress.fromJson(e)).toList();
        _localAddressesCache.clear();
        _localAddressesCache.addAll(list);
        return list;
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Lấy địa chỉ qua backend thất bại: $e');
      for (final candidate in candidateBaseUrls) {
        if (candidate == baseUrl) continue;
        try {
          final headers = await getHeaders();
          final res = await http
              .get(Uri.parse('$candidate/user/addresses'), headers: headers)
              .timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) {
            baseUrl = candidate;
            isConnectedToBackend = true;
            final List<dynamic> data = jsonDecode(res.body);
            final list = data.map((e) => UserAddress.fromJson(e)).toList();
            _localAddressesCache.clear();
            _localAddressesCache.addAll(list);
            return list;
          }
        } catch (_) {}
      }
      isConnectedToBackend = false;
    }

    // Không còn mock data: Trả về danh sách thật từ cache hoặc rỗng
    return List.from(_localAddressesCache);
  }

  /// Thêm địa chỉ mới vào Database Backend
  Future<UserAddress> addAddress(UserAddress address) async {
    final headers = await getHeaders();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/user/addresses'),
            headers: headers,
            body: jsonEncode(address.toJson()),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        final created = UserAddress.fromJson(data);
        _localAddressesCache.add(created);
        return created;
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Thêm địa chỉ qua backend thất bại: $e');
      for (final candidate in candidateBaseUrls) {
        if (candidate == baseUrl) continue;
        try {
          final res = await http.post(
            Uri.parse('$candidate/user/addresses'),
            headers: headers,
            body: jsonEncode(address.toJson()),
          ).timeout(const Duration(seconds: 3));
          if (res.statusCode == 200 || res.statusCode == 201) {
            baseUrl = candidate;
            isConnectedToBackend = true;
            final data = jsonDecode(res.body);
            final created = UserAddress.fromJson(data);
            _localAddressesCache.add(created);
            return created;
          }
        } catch (_) {}
      }
    }

    throw Exception('Không thể lưu địa chỉ vào cơ sở dữ liệu. Vui lòng kiểm tra lại kết nối máy chủ.');
  }

  /// Cập nhật địa chỉ
  Future<UserAddress> updateAddress(UserAddress address) async {
    try {
      final headers = await getHeaders();
      final response = await http
          .put(
            Uri.parse('$baseUrl/user/addresses/${address.id}'),
            headers: headers,
            body: jsonEncode(address.toJson()),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        return UserAddress.fromJson(data);
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Cập nhật địa chỉ qua backend thất bại: $e');
    }

    // Local fallback
    final index = _localAddressesCache.indexWhere(
      (element) => element.id == address.id,
    );
    if (index != -1) {
      if (address.isDefault) {
        for (int i = 0; i < _localAddressesCache.length; i++) {
          _localAddressesCache[i] = _localAddressesCache[i].copyWith(
            isDefault: false,
          );
        }
      }
      _localAddressesCache[index] = address;
    }
    return address;
  }

  /// Xóa địa chỉ
  Future<void> deleteAddress(String id) async {
    try {
      final headers = await getHeaders();
      final response = await http
          .delete(Uri.parse('$baseUrl/user/addresses/$id'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 204) {
        isConnectedToBackend = true;
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Xóa địa chỉ qua backend thất bại: $e');
    }

    _localAddressesCache.removeWhere((element) => element.id == id);
    if (_localAddressesCache.isNotEmpty &&
        !_localAddressesCache.any((element) => element.isDefault)) {
      _localAddressesCache[0] = _localAddressesCache[0].copyWith(
        isDefault: true,
      );
    }
  }

  /// Đặt làm địa chỉ mặc định
  Future<void> setDefaultAddress(String id) async {
    try {
      final headers = await getHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/user/addresses/$id/set-default'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Đặt mặc định qua backend thất bại: $e');
    }

    for (int i = 0; i < _localAddressesCache.length; i++) {
      _localAddressesCache[i] = _localAddressesCache[i].copyWith(
        isDefault: _localAddressesCache[i].id == id,
      );
    }
  }
}
