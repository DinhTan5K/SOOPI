import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const foodCategories = ['Món chính', 'Ăn nhẹ', 'Đồ uống'];
const weekDays = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ nhật',
];

class OpeningDay {
  OpeningDay({this.enabled = true, this.open = 480, this.close = 1320});
  bool enabled;
  int open;
  int close;
  OpeningDay copy() => OpeningDay(enabled: enabled, open: open, close: close);
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'open': open,
    'close': close,
  };
  factory OpeningDay.fromJson(Map<String, dynamic> json) => OpeningDay(
    enabled: json['enabled'] as bool,
    open: json['open'] as int,
    close: json['close'] as int,
  );
}

class MenuItem {
  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.category = 'Món chính',
    this.description = '',
    this.available = true,
  });
  final String id;
  final String name;
  final int price;
  final String category;
  final String description;
  final bool available;
  MenuItem withAvailability(bool value) => MenuItem(
    id: id,
    name: name,
    price: price,
    category: category,
    description: description,
    available: value,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'description': description,
    'available': available,
  };
  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as String,
    name: json['name'] as String,
    price: json['price'] as int,
    category: json['category'] as String,
    description: json['description'] as String,
    available: json['available'] as bool,
  );
}

String money(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} đ';
String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class MerchantData {
  static const _channel = MethodChannel('soopi/merchant_storage');
  bool acceptingOrders = true;
  List<OpeningDay> hours = List.generate(7, (_) => OpeningDay());
  List<MenuItem> items = [
    MenuItem(
      id: 'burger',
      name: 'Double Cheese Burger',
      price: 65000,
      description: 'Bò nướng, phô mai và rau tươi.',
    ),
    MenuItem(
      id: 'pizza',
      name: 'Pepperoni Pizza',
      price: 120000,
      description: 'Pizza xúc xích với phô mai mozzarella.',
    ),
    MenuItem(
      id: 'fries',
      name: 'Khoai tây chiên',
      price: 30000,
      category: 'Ăn nhẹ',
    ),
    MenuItem(
      id: 'tea',
      name: 'Trà đào cam sả',
      price: 35000,
      category: 'Đồ uống',
      available: false,
    ),
  ];
  bool get supportsStorage =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> load() async {
    if (!supportsStorage) return;
    final raw = await _channel.invokeMethod<String>('load');
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final loadedHours = (json['hours'] as List)
        .map((e) => OpeningDay.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (loadedHours.length != 7 ||
        loadedHours.any(
          (d) => d.open < 0 || d.open >= 1440 || d.close < 0 || d.close >= 1440,
        )) {
      throw const FormatException('Lịch không hợp lệ');
    }
    final loadedItems = (json['items'] as List)
        .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    acceptingOrders = json['acceptingOrders'] as bool;
    hours = loadedHours;
    items = loadedItems;
  }

  Future<void> save({
    bool? accepting,
    List<OpeningDay>? schedule,
    List<MenuItem>? menu,
  }) async {
    final nextAccepting = accepting ?? acceptingOrders;
    final nextHours = schedule ?? hours;
    final nextMenu = menu ?? items;
    if (supportsStorage) {
      await _channel.invokeMethod<void>(
        'save',
        jsonEncode({
          'acceptingOrders': nextAccepting,
          'hours': nextHours.map((d) => d.toJson()).toList(),
          'items': nextMenu.map((m) => m.toJson()).toList(),
        }),
      );
    }
    acceptingOrders = nextAccepting;
    hours = nextHours;
    items = nextMenu;
  }
}
