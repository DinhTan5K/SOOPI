import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_address.dart';
import '../services/profile_api_service.dart';
import '../services/geocoding_service.dart';
import '../services/address_suggestion_service.dart';

class AddEditAddressScreen extends StatefulWidget {
  final UserAddress? addressToEdit;

  const AddEditAddressScreen({super.key, this.addressToEdit});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();

  String _selectedLabel = 'Nhà riêng';
  bool _isDefault = false;
  bool _isLoading = false;
  bool _isSearchingAddress = false;
  bool _isLocatingGps = false;
  double? _selectedLat;
  double? _selectedLng;
  List<AddressSuggestion> _addressSuggestions = [];
  int _addressSearchVersion = 0;

  final List<String> _labels = ['Nhà riêng', 'Văn phòng', 'Khác'];

  @override
  void initState() {
    super.initState();
    if (widget.addressToEdit != null) {
      final addr = widget.addressToEdit!;
      _nameController.text = addr.recipientName;
      _phoneController.text = addr.phoneNumber;
      _addressController.text = addr.fullAddress;
      _noteController.text = addr.note;
      _selectedLabel = addr.label;
      _isDefault = addr.isDefault;
    }
  }

  @override
  void dispose() {
    _addressSearchVersion++;
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _onAddressChanged(String value) async {
    final version = ++_addressSearchVersion;
    if (value.trim().length < 3) {
      if (mounted) {
        setState(() {
          _addressSuggestions = [];
          _isSearchingAddress = false;
        });
      }
      return;
    }

    setState(() => _isSearchingAddress = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || version != _addressSearchVersion) return;

    try {
      final suggestions = await AddressSuggestionService.search(value.trim());
      if (!mounted || version != _addressSearchVersion) return;
      setState(() {
        _addressSuggestions = suggestions;
        _isSearchingAddress = false;
      });
    } catch (_) {
      if (!mounted || version != _addressSearchVersion) return;
      setState(() {
        _addressSuggestions = [];
        _isSearchingAddress = false;
      });
    }
  }

  void _selectAddressSuggestion(AddressSuggestion suggestion) {
    _addressSearchVersion++;
    _addressController.value = TextEditingValue(
      text: suggestion.displayName,
      selection: TextSelection.collapsed(offset: suggestion.displayName.length),
    );
    setState(() {
      _selectedLat = suggestion.latitude;
      _selectedLng = suggestion.longitude;
      _addressSuggestions = [];
      _isSearchingAddress = false;
    });
  }

  Future<void> _useCurrentGpsLocation() async {
    if (_isLocatingGps) return;
    setState(() => _isLocatingGps = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Hãy bật dịch vụ Vị trí/GPS trên điện thoại rồi thử lại.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        throw Exception('Quyền vị trí đang bị chặn trong Cài đặt.');
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

      final resolvedAddress = await GeocodingService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (resolvedAddress.isEmpty) {
        throw Exception('Không phân giải được địa chỉ từ tọa độ GPS.');
      }

      if (mounted) {
        _addressSearchVersion++;
        setState(() {
          _addressController.text = resolvedAddress;
          _selectedLat = position.latitude;
          _selectedLng = position.longitude;
          _addressSuggestions = [];
          _isSearchingAddress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lấy địa chỉ: $resolvedAddress'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không lấy được vị trí: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final apiService = ProfileApiService();
      final addressQuery = _addressController.text.trim();
      final coords = (_selectedLat != null && _selectedLng != null)
          ? null
          : await GeocodingService.getCoordinatesFromAddress(addressQuery);
      final finalLat = _selectedLat ?? coords?.latitude;
      final finalLng = _selectedLng ?? coords?.longitude;

      if (widget.addressToEdit == null) {
        // Tạo mới
        final newAddress = UserAddress(
          id: '',
          firebaseUid: '',
          label: _selectedLabel,
          recipientName: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          fullAddress: addressQuery,
          note: _noteController.text.trim(),
          isDefault: _isDefault,
        );
        await apiService.addAddress(newAddress);
      } else {
        // Cập nhật
        final updated = widget.addressToEdit!.copyWith(
          label: _selectedLabel,
          recipientName: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          fullAddress: addressQuery,
          note: _noteController.text.trim(),
          isDefault: _isDefault,
        );
        await apiService.updateAddress(updated);
      }

      // Tự động định vị và lưu vào SharedPreferences nếu đây là địa chỉ mặc định
      if (_isDefault) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
          await prefs.setString(
            'soopi.delivery_address.$uid',
            jsonEncode({
              'address': addressQuery,
              'type': _selectedLabel,
              'latitude': finalLat ?? 10.77689,
              'longitude': finalLng ?? 106.70089,
            }),
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.addressToEdit == null ? 'Thêm địa chỉ thành công!' : 'Đã cập nhật địa chỉ!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.addressToEdit != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(isEditing ? 'Chỉnh sửa địa chỉ' : 'Thêm địa chỉ mới',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chọn loại địa chỉ (Nhãn)
              const Text('Loại địa chỉ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 10),
              Row(
                children: _labels.map((label) {
                  final isSelected = _selectedLabel == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      selectedColor: Colors.orange.shade100,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.orange.shade900 : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? Colors.orange : Colors.grey.shade300,
                      ),
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedLabel = label);
                      },
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Tên người nhận
              _buildTextField(
                controller: _nameController,
                label: 'Tên người nhận *',
                hint: 'Nhập họ và tên người nhận',
                icon: Icons.person_outline,
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tên người nhận' : null,
              ),
              const SizedBox(height: 16),

              // Số điện thoại
              _buildTextField(
                controller: _phoneController,
                label: 'Số điện thoại nhận hàng *',
                hint: 'Ví dụ: 0987654321',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Vui lòng nhập số điện thoại';
                  if (val.trim().length < 9) return 'Số điện thoại không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Địa chỉ chi tiết + Nút lấy GPS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Địa chỉ cụ thể *',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  TextButton.icon(
                    onPressed: _isLocatingGps ? null : _useCurrentGpsLocation,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: _isLocatingGps
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          )
                        : const Icon(Icons.my_location, size: 16, color: Colors.orange),
                    label: Text(
                      _isLocatingGps ? 'Đang định vị...' : 'Lấy vị trí hiện tại (GPS)',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 3,
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Vui lòng nhập địa chỉ cụ thể' : null,
                onChanged: _onAddressChanged,
                decoration: InputDecoration(
                  hintText: 'Số nhà, tên đường, phường/xã, quận/huyện, thành phố',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.orange, width: 1.5),
                  ),
                ),
              ),
              if (_isSearchingAddress)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_addressSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _addressSuggestions.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final suggestion = _addressSuggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined, color: Colors.orange),
                        title: Text(
                          suggestion.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => _selectAddressSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Ghi chú cho tài xế
              _buildTextField(
                controller: _noteController,
                label: 'Ghi chú cho tài xế (tùy chọn)',
                hint: 'Ví dụ: Giao lên tầng 3, bấm chuông cổng phụ...',
                icon: Icons.edit_note_outlined,
              ),
              const SizedBox(height: 16),

              // Switch Đặt làm mặc định
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Đặt làm địa chỉ mặc định', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Tự động chọn địa chỉ này khi đặt món', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    Switch(
                      value: _isDefault,
                      activeThumbColor: Colors.orange,
                      onChanged: (val) => setState(() => _isDefault = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Nút Lưu
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveAddress,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(isEditing ? 'Lưu thay đổi' : 'Thêm địa chỉ',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: maxLines == 1 ? Icon(icon, color: Colors.grey) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
