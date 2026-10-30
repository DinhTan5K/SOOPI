import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig extends ChangeNotifier {
  static final ApiConfig _instance = ApiConfig._internal();
  factory ApiConfig() => _instance;
  ApiConfig._internal();

  static const String _prefKey = 'custom_server_base_url';

  // IP máy tính hiện tại và các candidate phổ biến
  static const String currentPcWifiIp = '10.12.96.104';

  static const List<String> defaultCandidates = [
    'http://127.0.0.1:5000/api',          // USB cắm cáp (adb reverse) & Windows Desktop
    'http://localhost:5000/api',           // Localhost
    'http://10.12.96.104:5000/api',       // Wi-Fi máy tính hiện tại (192.168.1.69)
    'http://10.12.104.120:5000/api',      // Wi-Fi phụ
    'http://192.168.1.190:5000/api',      // Wi-Fi máy tính phụ
    'https://soopifood-dev.loca.lt/api',  // Cloud Tunnel (Hoạt động trên 4G & mọi Wi-Fi)
    'http://10.0.2.2:5000/api',            // Android Emulator
    'http://192.168.43.1:5000/api',        // Khi điện thoại phát Wi-Fi Hotspot cho máy tính
    'http://172.20.10.1:5000/api',         // iPhone Hotspot
  ];

  String _baseUrl = 'http://127.0.0.1:5000/api';
  bool _isInitialized = false;
  bool _isAutoDetecting = false;

  String get baseUrl => _baseUrl;
  bool get isAutoDetecting => _isAutoDetecting;

  set baseUrl(String url) {
    _baseUrl = _normalizeUrl(url);
    _saveBaseUrl(_baseUrl);
    notifyListeners();
  }

  /// Khởi tạo khi app vừa mở: khôi phục URL đã lưu hoặc tự động dò
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _baseUrl = _normalizeUrl(saved);
        // Kiểm tra nhanh URL đã lưu
        final ok = await testConnection(_baseUrl, timeout: const Duration(milliseconds: 1500));
        if (ok) {
          debugPrint('[ApiConfig] Đã kết nối URL đã lưu: $_baseUrl');
          return;
        }
      }
    } catch (e) {
      debugPrint('[ApiConfig] Lỗi đọc SharedPreferences: $e');
    }

    // Nếu URL hiện tại không chạy được, tự động dò tìm song song
    await autoDetect();
  }

  /// Chuẩn hóa định dạng URL (thêm http://, port :5000, /api nếu người dùng nhập thiếu)
  static String _normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return 'http://127.0.0.1:5000/api';

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }

    // Nếu người dùng chỉ nhập IP (vd: 192.168.1.13)
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      final port = uri.hasPort ? uri.port : 5000;
      final path = uri.path.endsWith('/api')
          ? uri.path
          : (uri.path.isEmpty || uri.path == '/' ? '/api' : '${uri.path}/api');
      return '${uri.scheme}://${uri.host}:$port$path';
    }

    if (!url.endsWith('/api')) {
      url = url.endsWith('/') ? '${url}api' : '$url/api';
    }
    return url;
  }

  /// Kiểm tra xem URL có phản hồi từ máy chủ BE không
  Future<bool> testConnection(String url, {Duration timeout = const Duration(seconds: 2)}) async {
    final clean = _normalizeUrl(url);
    try {
      final uri = Uri.parse('$clean/restaurants');
      final res = await http.get(uri, headers: const {'bypass-tunnel-reminder': 'true'}).timeout(timeout);
      return res.statusCode == 200 || res.statusCode == 404;
    } catch (_) {
      try {
        final root = clean.endsWith('/api') ? clean.substring(0, clean.length - 4) : clean;
        final res = await http.get(Uri.parse(root)).timeout(const Duration(milliseconds: 1500));
        return res.statusCode >= 200 && res.statusCode < 500;
      } catch (_) {
        return false;
      }
    }
  }

  /// Quét siêu tốc (50-200ms) toàn bộ dải subnet Wi-Fi của điện thoại để tìm máy tính chạy Backend port 5000
  Future<String?> _scanSubnetsForBackend(int port) async {
    if (kIsWeb) return null;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final prefixes = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      }

      debugPrint('[ApiConfig] Dò tìm máy tính trên các dải subnet Wi-Fi: $prefixes');

      for (final prefix in prefixes) {
        final completer = Completer<String?>();
        var pending = 254;

        for (int i = 1; i <= 254; i++) {
          final ip = '$prefix.$i';
          Socket.connect(ip, port, timeout: const Duration(milliseconds: 350)).then((socket) {
            socket.destroy();
            if (!completer.isCompleted) {
              completer.complete(ip);
            }
          }).catchError((_) {
            pending--;
            if (pending <= 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          });
        }

        final foundIp = await completer.future.timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () => null,
        );

        if (foundIp != null) {
          final candidateUrl = 'http://$foundIp:$port/api';
          final isValid = await testConnection(candidateUrl, timeout: const Duration(seconds: 1));
          if (isValid) {
            return candidateUrl;
          }
        }
      }
    } catch (e) {
      debugPrint('[ApiConfig] Lỗi quét subnet: $e');
    }
    return null;
  }

  /// Tự động dò tìm song song tất cả IP khả dĩ (USB adb reverse -> Quét subnet Wi-Fi -> Danh sách mặc định)
  Future<bool> autoDetect() async {
    _isAutoDetecting = true;
    notifyListeners();

    try {
      // 1. Kiểm tra nhanh URL hiện tại hoặc USB adb reverse (timeout 2s)
      if (await testConnection(_baseUrl, timeout: const Duration(seconds: 2))) {
        debugPrint('[ApiConfig] URL hiện tại vẫn hoạt động tốt: $_baseUrl');
        return true;
      }
      if (await testConnection('http://127.0.0.1:5000/api', timeout: const Duration(seconds: 2))) {
        _baseUrl = 'http://127.0.0.1:5000/api';
        await _saveBaseUrl(_baseUrl);
        debugPrint('[ApiConfig] Đã kết nối qua cáp USB (adb reverse): $_baseUrl');
        return true;
      }

      // 2. Tự động quét dải mạng Wi-Fi hiện tại của điện thoại để tìm máy tính (siêu nhanh ~100ms)
      final subnetFound = await _scanSubnetsForBackend(5000);
      if (subnetFound != null) {
        _baseUrl = _normalizeUrl(subnetFound);
        await _saveBaseUrl(_baseUrl);
        debugPrint('[ApiConfig] Đã tự động dò thấy máy tính trong mạng Wi-Fi: $_baseUrl');
        return true;
      }

      // 3. Fallback: Dò các IP dự phòng phổ biến
      final candidates = <String>{
        ...defaultCandidates,
      }.toList();

      debugPrint('[ApiConfig] Đang dò tìm máy chủ BE qua ${candidates.length} địa chỉ dự phòng...');

      final completer = Completer<String?>();
      var pending = candidates.length;

      for (final candidate in candidates) {
        testConnection(candidate, timeout: const Duration(milliseconds: 1500)).then((ok) {
          if (ok && !completer.isCompleted) {
            completer.complete(candidate);
          } else {
            pending--;
            if (pending <= 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          }
        });
      }

      final winner = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );

      if (winner != null) {
        _baseUrl = _normalizeUrl(winner);
        await _saveBaseUrl(_baseUrl);
        debugPrint('[ApiConfig] Đã kết nối máy chủ BE: $_baseUrl');
        return true;
      }
    } catch (e) {
      debugPrint('[ApiConfig] Dò tìm tự động thất bại: $e');
    } finally {
      _isAutoDetecting = false;
      notifyListeners();
    }
    return false;
  }

  /// Lưu URL tùy chỉnh do người dùng nhập hoặc vừa tìm thấy
  Future<bool> setCustomUrl(String newUrl) async {
    final clean = _normalizeUrl(newUrl);
    final ok = await testConnection(clean, timeout: const Duration(seconds: 3));
    if (ok) {
      _baseUrl = clean;
      await _saveBaseUrl(clean);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _saveBaseUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, url);
    } catch (e) {
      debugPrint('[ApiConfig] Không thể lưu SharedPreferences: $e');
    }
  }

  /// Hiển thị hộp thoại cài đặt máy chủ BE ngay trong App
  static void showConfigDialog(BuildContext context, {VoidCallback? onConnected}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ServerConfigSheet(onConnected: onConnected),
    );
  }
}

class _ServerConfigSheet extends StatefulWidget {
  final VoidCallback? onConnected;
  const _ServerConfigSheet({this.onConnected});

  @override
  State<_ServerConfigSheet> createState() => _ServerConfigSheetState();
}

class _ServerConfigSheetState extends State<_ServerConfigSheet> {
  final ApiConfig _config = ApiConfig();
  late TextEditingController _controller;
  bool _isTesting = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _config.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _autoDetect() async {
    setState(() {
      _isTesting = true;
      _statusMessage = 'Đang quét tự động các IP máy tính...';
      _isSuccess = false;
    });

    final ok = await _config.autoDetect();
    if (!mounted) return;

    if (ok) {
      _controller.text = _config.baseUrl;
      setState(() {
        _isTesting = false;
        _isSuccess = true;
        _statusMessage = '✅ Đã tìm thấy máy chủ BE:\n${_config.baseUrl}';
      });
      widget.onConnected?.call();
    } else {
      setState(() {
        _isTesting = false;
        _isSuccess = false;
        _statusMessage = '❌ Không tìm thấy máy chủ tự động. Vui lòng nhập IP thủ công.';
      });
    }
  }

  Future<void> _testAndSave() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isTesting = true;
      _statusMessage = 'Đang kiểm tra kết nối...';
      _isSuccess = false;
    });

    final ok = await _config.setCustomUrl(input);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _isSuccess = ok;
      _statusMessage = ok
          ? 'Kết nối thành công! Đã lưu máy chủ.'
          : 'Không thể kết nối đến URL này. Hãy kiểm tra lại IP hoặc chắc chắn backend đang chạy.';
    });

    if (ok) {
      widget.onConnected?.call();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.dns, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'Cài đặt máy chủ Backend',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Nếu đổi mạng Wi-Fi hoặc chuyển đổi thiết bị, hãy bấm "Tự động dò" hoặc nhập IP máy tính.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Địa chỉ Backend API (URL hoặc IP)',
              hintText: 'VD: 192.168.1.13 hoặc http://192.168.1.13:5000/api',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _controller.clear(),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isSuccess ? Colors.green : Colors.red),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _autoDetect,
                  icon: const Icon(Icons.radar, color: Colors.orange),
                  label: const Text('Tự động dò', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isTesting ? null : _testAndSave,
                  icon: _isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Kiểm tra & Lưu', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text('Gợi ý:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              _buildChip('127.0.0.1 (USB)'),
              _buildChip('Cloud Tunnel (4G/Wi-Fi)'),
              _buildChip('192.168.1.190 (Wi-Fi)'),
              _buildChip('10.0.2.2 (Emulator)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    String url;
    if (label.contains('127.0.0.1')) {
      url = 'http://127.0.0.1:5000/api';
    } else if (label.contains('Cloud Tunnel')) {
      url = 'https://soopifood-dev.loca.lt/api';
    } else if (label.contains('192.168.1.190')) {
      url = 'http://192.168.1.190:5000/api';
    } else {
      url = 'http://10.0.2.2:5000/api';
    }
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        _controller.text = url;
      },
    );
  }
}
