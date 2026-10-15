import 'dart:convert';

import '../services/merchant_api_service.dart';

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
    this.imageBase64,
  });
  final String id;
  final String name;
  final int price;
  final String category;
  final String description;
  final bool available;
  final String? imageBase64;
  MenuItem withAvailability(bool value) => MenuItem(
    id: id,
    name: name,
    price: price,
    category: category,
    description: description,
    available: value,
    imageBase64: imageBase64,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'description': description,
    'available': available,
    'imageBase64': imageBase64,
  };
  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as String,
    name: json['name'] as String,
    price: json['price'] as int,
    category: json['category'] as String,
    description: json['description'] as String,
    available: json['available'] as bool,
    imageBase64: json['imageBase64'] as String?,
  );
}

String money(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} đ';
String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class RestaurantSelectionRequired implements Exception {
  const RestaurantSelectionRequired(this.restaurants);
  final List<Map<String, dynamic>> restaurants;
}

class MerchantData {
  MerchantData({this.remote = false, MerchantApiService? api})
    : api = api ?? MerchantApiService();
  final bool remote;
  final MerchantApiService api;
  String? restaurantId;
  String restaurantName = '';
  String approvalStatus = '';
  bool isActive = false;
  Map<String, String> categoryIds = {};
  List<String> get categories =>
      remote ? categoryIds.keys.toList() : foodCategories;

  Future<List<Map<String, dynamic>>> listRestaurants() async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final result = await api.request(
        'GET',
        'restaurants?page=$page&pageSize=100',
      );
      final items = result['items'] as List;
      rows.addAll(items.map((r) => Map<String, dynamic>.from(r as Map)));
      if (items.isEmpty || rows.length >= (result['total'] as int)) break;
    }
    return rows;
  }

  Future<void> _loadRemote() async {
    if (restaurantId == null) {
      await api.request('GET', 'me');
      final restaurants = await listRestaurants();
      if (restaurants.isEmpty) throw Exception('Tài khoản chưa có quán ăn.');
      if (restaurants.length > 1) {
        throw RestaurantSelectionRequired(restaurants);
      }
      restaurantId = restaurants.first['id'] as String;
    }
    final data = await api.request('GET', 'restaurants/$restaurantId');
    restaurantName = data['name'] as String;
    approvalStatus = data['approvalStatus'] as String;
    isActive = data['isActive'] as bool;
    acceptingOrders = data['isAcceptingOrders'] as bool;
    categoryIds = {
      for (final c in data['categories'])
        c['name'] as String: c['id'] as String,
    };
    items = [
      for (final c in data['categories'])
        for (final m in c['items'])
          MenuItem(
            id: m['id'],
            name: m['name'],
            price: (m['price'] as num).round(),
            category: c['name'],
            description: m['description'] ?? '',
            available: m['isAvailable'],
            imageBase64: m['imageUrl'],
          ),
    ];
    hours = List.generate(7, (_) => OpeningDay(enabled: false));
    for (final h in data['openingHours']) {
      int minutes(String value) {
        final parts = value.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }

      hours[((h['dayOfWeek'] as int) + 6) % 7] = OpeningDay(
        enabled: !h['isClosed'],
        open: minutes(h['opensAt']),
        close: minutes(h['closesAt']),
      );
    }
  }

  Future<void> _saveRemote({
    bool? accepting,
    List<OpeningDay>? schedule,
    List<MenuItem>? menu,
  }) async {
    final path = 'restaurants/$restaurantId';
    try {
      if (accepting != null) {
        await api.request('PATCH', '$path/operation', {
          'isActive': accepting ? true : isActive,
          'isAcceptingOrders': accepting,
        });
      }
      if (schedule != null) {
        for (var i = 0; i < 7; i++) {
          final d = schedule[i];
          await api.request('PUT', '$path/hours/${(i + 1) % 7}', {
            'opensAt': '${clockLabel(d.open)}:00',
            'closesAt': '${clockLabel(d.close)}:00',
            'isClosed': !d.enabled,
          });
        }
      }
      if (menu != null) {
        for (final old in items) {
          if (!menu.any((m) => m.id == old.id)) {
            await api.request('DELETE', '$path/menu/${old.id}');
          }
        }
        for (final item in menu) {
          final old = items.where((m) => m.id == item.id).firstOrNull;
          if (identical(old, item)) continue;
          if (old != null &&
              old.name == item.name &&
              old.price == item.price &&
              old.category == item.category &&
              old.description == item.description &&
              old.imageBase64 == item.imageBase64) {
            await api.request('PATCH', '$path/menu/${item.id}/availability', {
              'isAvailable': item.available,
            });
            continue;
          }
          var image = item.imageBase64;
          if (image != null && !image.startsWith('http')) {
            image = await api.upload(restaurantId!, image);
          }
          await api.request(
            old == null ? 'POST' : 'PUT',
            old == null ? '$path/menu' : '$path/menu/${item.id}',
            {
              'categoryId': categoryIds[item.category],
              'name': item.name,
              'description': item.description,
              'price': item.price,
              'imageUrl': image,
              'isAvailable': item.available,
            },
          );
        }
      }
    } finally {
      await _loadRemote();
    }
  }

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
    if (remote) return _loadRemote();
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
    if (remote) {
      return _saveRemote(accepting: accepting, schedule: schedule, menu: menu);
    }
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
