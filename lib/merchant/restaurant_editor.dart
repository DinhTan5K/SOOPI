import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'merchant_style.dart';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../services/geocoding_service.dart';

Future<Map<String, dynamic>?> editRestaurant(
  BuildContext context, {
  Map<String, dynamic>? initial,
}) async {
  return showMerchantDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RestaurantEditorDialog(initial: initial),
  );
}

class _RestaurantEditorDialog extends StatefulWidget {
  const _RestaurantEditorDialog({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_RestaurantEditorDialog> createState() =>
      _RestaurantEditorDialogState();
}

class _RestaurantEditorDialogState extends State<_RestaurantEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _description;

  double? _latitude;
  double? _longitude;
  bool _isLocatingGps = false;
  bool _isSearchingAddress = false;
  bool _isSaving = false;
  List<_AddressSuggestion> _suggestions = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _name = TextEditingController(text: init?['name'] as String? ?? '');
    _phone = TextEditingController(text: init?['phone'] as String? ?? '');
    _address = TextEditingController(text: init?['address'] as String? ?? '');
    _city = TextEditingController(text: init?['city'] as String? ?? '');
    _description = TextEditingController(
      text: init?['description'] as String? ?? '',
    );

    _latitude = (init?['latitude'] as num?)?.toDouble();
    _longitude = (init?['longitude'] as num?)?.toDouble();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _description.dispose();
    super.dispose();
  }

  // --- LẤY TỌA ĐỘ GPS THỰC TẾ CỦA THIẾT BỊ ---
  Future<void> _getCurrentGpsLocation() async {
    if (_isLocatingGps) return;
    setState(() => _isLocatingGps = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
          'Vui lòng bật dịch vụ Định vị/GPS trên thiết bị rồi thử lại.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Quyền vị trí bị từ chối vĩnh viễn. Vui lòng mở Cài đặt để cấp quyền.',
              ),
            ),
          );
        }
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Ứng dụng chưa được cấp quyền truy cập vị trí.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _suggestions = [];
        });

        // Tự động gọi reverse geocode để điền địa chỉ & thành phố
        await _reverseGeocode(position.latitude, position.longitude);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã lấy tọa độ GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi định vị: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  // --- REVERSE GEOCODE: TỌA ĐỘ -> ĐỊA CHỈ & THÀNH PHỐ ---
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final result = await GeocodingService.reverseGeocodeResult(lat, lng);
      if (mounted && result.displayName.isNotEmpty) {
        setState(() {
          if (_address.text.trim().isEmpty || _address.text.contains('GPS')) {
            _address.text = result.displayName;
          }
          if (_city.text.trim().isEmpty && result.city.isNotEmpty) {
            _city.text = result.city;
          }
        });
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }
  }

  // --- TÌM KIẾM GỢI Ý ĐỊA CHỈ KHI GÕ ---
  void _onAddressChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _isSearchingAddress = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearchingAddress = true);
      try {
        final uri = Uri.https('photon.komoot.io', '/api/', {
          'q': value.trim(),
          'limit': '5',
          'countrycode': 'VN',
        });
        final response = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'User-Agent':
                    'SoopiFood/1.0 (merchant restaurant address search)',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final features = payload['features'] as List<dynamic>? ?? [];
          final list = features
              .map(
                (item) =>
                    _AddressSuggestion.fromJson(item as Map<String, dynamic>),
              )
              .where(
                (item) =>
                    item.displayName.isNotEmpty &&
                    item.latitude != 0 &&
                    item.longitude != 0,
              )
              .toList();

          if (mounted) {
            setState(() {
              _suggestions = list;
              _isSearchingAddress = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Address search error: $e');
        if (mounted) setState(() => _isSearchingAddress = false);
      }
    });
  }

  // --- CHỌN 1 ĐỊA CHỈ GỢI Ý TỪ BẢN ĐỒ ---
  void _selectSuggestion(_AddressSuggestion s) {
    setState(() {
      _address.text = s.displayName;
      if (s.city.isNotEmpty) {
        _city.text = s.city;
      }
      _latitude = s.latitude;
      _longitude = s.longitude;
      _suggestions = [];
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // --- FALLBACK GEOCODE KHI BẤM LƯU (NẾU CHƯA CÓ TỌA ĐỘ) ---
  Future<bool> _resolveCoordinatesIfMissing() async {
    if (_latitude != null && _longitude != null) return true;
    final query = '${_address.text.trim()}, ${_city.text.trim()}';
    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'limit': '1',
        'countrycode': 'VN',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (merchant restaurant address)',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final features = payload['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          final s = _AddressSuggestion.fromJson(
            features.first as Map<String, dynamic>,
          );
          if (s.latitude != 0 && s.longitude != 0) {
            _latitude = s.latitude;
            _longitude = s.longitude;
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Fallback geocode error: $e');
    }
    return false;
  }

  // --- XỬ LÝ LƯU THÔNG TIN ---
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final hasCoords = await _resolveCoordinatesIfMissing();
    if (mounted) setState(() => _isSaving = false);

    if (!hasCoords || _latitude == null || _longitude == null) {
      if (!mounted) return;
      showMerchantDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cần tọa độ vị trí quán'),
          content: const Text(
            'Không thể xác định vị trí thực tế của quán từ địa chỉ đã nhập.\n\n'
            'Vui lòng bấm nút "Lấy vị trí GPS hiện tại" hoặc chọn địa chỉ từ gợi ý bản đồ để khách hàng quanh đây có thể tìm thấy quán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, <String, dynamic>{
      ...?widget.initial,
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'city': _city.text.trim(),
      'description': _description.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCoordinates = _latitude != null && _longitude != null;

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Đăng ký quán ăn' : 'Thông tin quán',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Tên quán
                TextFormField(
                  controller: _name,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Tên quán',
                    prefixIcon: Icon(Icons.storefront, color: Colors.orange),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập tên quán.'
                      : null,
                ),
                const SizedBox(height: 8),

                // 2. Số điện thoại
                TextFormField(
                  controller: _phone,
                  maxLength: 20,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    prefixIcon: Icon(Icons.phone, color: Colors.orange),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập số điện thoại.'
                      : null,
                ),
                const SizedBox(height: 8),

                // 3. Nút bấm lấy GPS thực tế
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: OutlinedButton.icon(
                    onPressed: _isLocatingGps ? null : _getCurrentGpsLocation,
                    icon: _isLocatingGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MerchantStyle.primary,
                            ),
                          )
                        : const Icon(Icons.my_location, color: Colors.orange),
                    label: Text(
                      _isLocatingGps
                          ? 'Đang lấy vị trí GPS...'
                          : 'Lấy vị trí GPS hiện tại của quán',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: MerchantStyle.primary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: MerchantStyle.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // 4. Banner trạng thái tọa độ GPS
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasCoordinates
                        ? Colors.green.shade50
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasCoordinates
                          ? Colors.green.shade300
                          : Colors.amber.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasCoordinates
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: hasCoordinates
                            ? Colors.green
                            : Colors.amber.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasCoordinates
                              ? 'Tọa độ GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)} (Hợp lệ)'
                              : 'Chưa có tọa độ. Bấm nút GPS hoặc chọn gợi ý bản đồ để lưu vị trí thật.',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasCoordinates
                                ? Colors.green.shade900
                                : Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Địa chỉ quán với Live Autocomplete
                TextFormField(
                  controller: _address,
                  maxLength: 500,
                  onChanged: _onAddressChanged,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ',
                    prefixIcon: const Icon(
                      Icons.location_on,
                      color: MerchantStyle.primary,
                    ),
                    suffixIcon: _isSearchingAddress
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập địa chỉ.'
                      : null,
                ),

                // Danh sách gợi ý địa chỉ khi gõ
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final s = _suggestions[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.pin_drop,
                            color: MerchantStyle.primary,
                            size: 20,
                          ),
                          title: Text(
                            s.displayName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            'Tọa độ: ${s.latitude.toStringAsFixed(4)}, ${s.longitude.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          onTap: () => _selectSuggestion(s),
                        );
                      },
                    ),
                  ),

                // 6. Thành phố
                TextFormField(
                  controller: _city,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Thành phố / Tỉnh',
                    prefixIcon: Icon(Icons.location_city, color: Colors.orange),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập thành phố.'
                      : null,
                ),
                const SizedBox(height: 8),

                // 7. Mô tả quán
                TextFormField(
                  controller: _description,
                  maxLength: 1000,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (tùy chọn)',
                    prefixIcon: Icon(Icons.description, color: Colors.orange),
                  ),
                ),
                const SizedBox(height: 8),

                const Text(
                  'Quán cần được duyệt trước khi nhận đơn. Thay đổi thông tin quán đã duyệt sẽ gửi duyệt lại.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: MerchantStyle.primary),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}

class _AddressSuggestion {
  final String displayName;
  final String street;
  final String district;
  final String city;
  final double latitude;
  final double longitude;

  const _AddressSuggestion({
    required this.displayName,
    required this.street,
    required this.district,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory _AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    final coordinates =
        (json['geometry'] as Map<String, dynamic>?)?['coordinates']
            as List<dynamic>? ??
        [];
    final houseNumber = properties['housenumber']?.toString() ?? '';
    final road = properties['street']?.toString() ?? '';
    final street = [houseNumber, road].where((p) => p.isNotEmpty).join(' ');
    final district =
        properties['district'] ??
        properties['county'] ??
        properties['suburb'] ??
        '';
    final city = properties['city'] ?? properties['state'] ?? '';
    final addressParts = <String>[
      properties['name']?.toString() ?? '',
      street,
      district.toString(),
      city.toString(),
    ].where((p) => p.isNotEmpty).toSet().toList();
    final displayName = addressParts.isNotEmpty
        ? addressParts.join(', ')
        : (properties['name']?.toString() ?? 'Địa chỉ');
    final double lon = coordinates.isNotEmpty
        ? (coordinates[0] as num).toDouble()
        : 0.0;
    final double lat = coordinates.length > 1
        ? (coordinates[1] as num).toDouble()
        : 0.0;
    return _AddressSuggestion(
      displayName: displayName,
      street: street,
      district: district.toString(),
      city: city.toString(),
      latitude: lat,
      longitude: lon,
    );
  }
}
