import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';
import '../models/user_address.dart';

class ProfileApiService {
  static final ProfileApiService _instance = ProfileApiService._internal();
  factory ProfileApiService() => _instance;
  ProfileApiService._internal();

  /// Default API URL: 10.0.2.2 for Android Emulator, localhost for Windows/Web
  /// Có thể đổi thành IP LAN máy tính khi chạy trên điện thoại thật (vd: http://192.168.1.15:5000/api)
  // IP máy tính chạy .NET 8 (cổng 5000)
  String baseUrl = 'http://192.168.2.154:5000/api';

  // Bộ nhớ đệm tạm thời (In-memory Fallback) khi Backend .NET chưa chạy
  UserProfile? _localProfileCache;
  final List<UserAddress> _localAddressesCache = [];
  bool isConnectedToBackend = false;

  /// Lấy Firebase ID Token để đính kèm vào Header Authorization
  Future<Map<String, String>> _getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (user != null) 'X-Firebase-Uid': user.uid,
      if (user?.email != null) 'X-Firebase-Email': user!.email!,
      if (user?.displayName != null && user!.displayName!.isNotEmpty)
        'X-Firebase-Name': Uri.encodeComponent(user.displayName!),
    };
  }

  /// Lấy thông tin Profile người dùng
  Future<UserProfile> getProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest_user';
    final email = user?.email ?? 'user@soopi.vn';
    final displayName = user?.displayName ?? 'Khách hàng SOOPI';

    try {
      final headers = await _getHeaders();

      final response = await http
          .get(Uri.parse('$baseUrl/user/profile'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        _localProfileCache = UserProfile.fromJson(data);
        return _localProfileCache!;
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Không kết nối được .NET Backend ($baseUrl): $e');
      isConnectedToBackend = false;
    }

    // Fallback: Sử dụng dữ liệu Firebase hoặc cache hiện tại
    _localProfileCache ??= UserProfile(
      id: '1',
      firebaseUid: uid,
      fullName: displayName.isNotEmpty ? displayName : 'Nguyễn Văn A',
      email: email,
      phoneNumber: user?.phoneNumber ?? '0987654321',
      avatarUrl: user?.photoURL ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(displayName)}&background=FFA500&color=fff',
      gender: 'Nam',
      dateOfBirth: DateTime(2000, 1, 1),
      createdAt: DateTime.now(),
    );
    return _localProfileCache!;
  }

  /// Cập nhật thông tin Profile người dùng
  Future<UserProfile> updateProfile(UserProfile profile) async {
    try {
      final headers = await _getHeaders();

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
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Cập nhật thất bại qua .NET Backend, lưu fallback local: $e');
      isConnectedToBackend = false;
    }

    // Cập nhật Firebase Auth
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        if (profile.fullName.isNotEmpty) {
          await currentUser.updateDisplayName(profile.fullName);
        }
        if (profile.avatarUrl.isNotEmpty) {
          await currentUser.updatePhotoURL(profile.avatarUrl);
        }
      } catch (_) {}
    }

    _localProfileCache = profile.copyWith(updatedAt: DateTime.now());
    return _localProfileCache!;
  }

  /// Lấy danh sách địa chỉ giao hàng
  Future<List<UserAddress>> getAddresses() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest_user';

    try {
      final headers = await _getHeaders();
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
      debugPrint('[ProfileApiService] Lấy địa chỉ qua backend thất bại, dùng local: $e');
      isConnectedToBackend = false;
    }

    // Khởi tạo mock address nếu chưa có
    if (_localAddressesCache.isEmpty) {
      _localAddressesCache.addAll([
        UserAddress(
          id: 'addr_1',
          firebaseUid: uid,
          label: 'Nhà riêng',
          recipientName: _localProfileCache?.fullName ?? 'Nguyễn Văn A',
          phoneNumber: _localProfileCache?.phoneNumber ?? '0987654321',
          fullAddress: 'Số 123 Đường Cầu Giấy, Phường Quan Hoa, Quận Cầu Giấy, Hà Nội',
          note: 'Bấm chuông tầng 2',
          isDefault: true,
        ),
        UserAddress(
          id: 'addr_2',
          firebaseUid: uid,
          label: 'Văn phòng',
          recipientName: _localProfileCache?.fullName ?? 'Nguyễn Văn A',
          phoneNumber: _localProfileCache?.phoneNumber ?? '0987654321',
          fullAddress: 'Tòa nhà Landmark 72, Phạm Hùng, Nam Từ Liêm, Hà Nội',
          note: 'Gọi trước khi đến',
          isDefault: false,
        ),
      ]);
    }
    return List.from(_localAddressesCache);
  }

  /// Thêm địa chỉ mới
  Future<UserAddress> addAddress(UserAddress address) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest_user';

    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/user/addresses'),
            headers: headers,
            body: jsonEncode(address.toJson()),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        isConnectedToBackend = true;
        final data = jsonDecode(response.body);
        return UserAddress.fromJson(data);
      }
    } catch (e) {
      debugPrint('[ProfileApiService] Thêm địa chỉ qua backend thất bại: $e');
    }

    // Local fallback
    final newId = 'addr_${DateTime.now().millisecondsSinceEpoch}';
    var newAddr = address.copyWith(id: newId, firebaseUid: uid);

    if (newAddr.isDefault) {
      for (int i = 0; i < _localAddressesCache.length; i++) {
        _localAddressesCache[i] = _localAddressesCache[i].copyWith(isDefault: false);
      }
    } else if (_localAddressesCache.isEmpty) {
      newAddr = newAddr.copyWith(isDefault: true);
    }

    _localAddressesCache.add(newAddr);
    return newAddr;
  }

  /// Cập nhật địa chỉ
  Future<UserAddress> updateAddress(UserAddress address) async {
    try {
      final headers = await _getHeaders();
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
    final index = _localAddressesCache.indexWhere((element) => element.id == address.id);
    if (index != -1) {
      if (address.isDefault) {
        for (int i = 0; i < _localAddressesCache.length; i++) {
          _localAddressesCache[i] = _localAddressesCache[i].copyWith(isDefault: false);
        }
      }
      _localAddressesCache[index] = address;
    }
    return address;
  }

  /// Xóa địa chỉ
  Future<void> deleteAddress(String id) async {
    try {
      final headers = await _getHeaders();
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
    if (_localAddressesCache.isNotEmpty && !_localAddressesCache.any((element) => element.isDefault)) {
      _localAddressesCache[0] = _localAddressesCache[0].copyWith(isDefault: true);
    }
  }

  /// Đặt làm địa chỉ mặc định
  Future<void> setDefaultAddress(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .patch(Uri.parse('$baseUrl/user/addresses/$id/set-default'), headers: headers)
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
