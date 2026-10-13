class UserAddress {
  final String id;
  final String firebaseUid;
  final String label; // 'Nhà riêng', 'Văn phòng', 'Khác'
  final String recipientName;
  final String phoneNumber;
  final String fullAddress;
  final String note;
  final bool isDefault;

  UserAddress({
    required this.id,
    required this.firebaseUid,
    this.label = 'Nhà riêng',
    required this.recipientName,
    required this.phoneNumber,
    required this.fullAddress,
    this.note = '',
    this.isDefault = false,
  });

  factory UserAddress.fromJson(Map<String, dynamic> json) {
    return UserAddress(
      id: json['id']?.toString() ?? '',
      firebaseUid: json['firebaseUid']?.toString() ?? json['uid']?.toString() ?? '',
      label: json['label'] ?? 'Nhà riêng',
      recipientName: json['recipientName'] ?? json['name'] ?? '',
      phoneNumber: json['phoneNumber'] ?? json['phone'] ?? '',
      fullAddress: json['fullAddress'] ?? json['address'] ?? '',
      note: json['note'] ?? '',
      isDefault: json['isDefault'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firebaseUid': firebaseUid,
      'label': label,
      'recipientName': recipientName,
      'phoneNumber': phoneNumber,
      'fullAddress': fullAddress,
      'note': note,
      'isDefault': isDefault,
    };
  }

  UserAddress copyWith({
    String? id,
    String? firebaseUid,
    String? label,
    String? recipientName,
    String? phoneNumber,
    String? fullAddress,
    String? note,
    bool? isDefault,
  }) {
    return UserAddress(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      fullAddress: fullAddress ?? this.fullAddress,
      note: note ?? this.note,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
