class UserAddress {
  final String id;
  final String firebaseUid;
  final String label;
  final String recipientName;
  final String phoneNumber;
  final String fullAddress;
  final String note;
  final bool isDefault;
  final double? latitude;
  final double? longitude;

  UserAddress({
    required this.id,
    required this.firebaseUid,
    this.label = 'Nhà riêng',
    required this.recipientName,
    required this.phoneNumber,
    required this.fullAddress,
    this.note = '',
    this.isDefault = false,
    this.latitude,
    this.longitude,
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
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
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
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
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
    double? latitude,
    double? longitude,
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
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
