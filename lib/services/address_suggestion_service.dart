import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressSuggestion {
  final String displayName;
  final String street;
  final String district;
  final String city;
  final double latitude;
  final double longitude;

  const AddressSuggestion({
    required this.displayName,
    required this.street,
    required this.district,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    final coordinates =
        (json['geometry'] as Map<String, dynamic>?)?['coordinates']
            as List<dynamic>? ??
        [];
    final houseNumber = properties['housenumber']?.toString() ?? '';
    final road = properties['street']?.toString() ?? '';
    final street = [houseNumber, road]
        .where((part) => part.isNotEmpty)
        .join(' ');
    final district = properties['district'] ?? properties['county'] ?? '';
    final city = properties['city'] ?? properties['state'] ?? '';
    final addressParts = <String>[
      properties['name']?.toString() ?? '',
      street,
      district.toString(),
      city.toString(),
      properties['country']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).toSet().toList();

    return AddressSuggestion(
      displayName: addressParts.join(', '),
      street: street,
      district: district.toString(),
      city: city.toString(),
      latitude: coordinates.length > 1 ? (coordinates[1] as num).toDouble() : 0,
      longitude: coordinates.isNotEmpty ? (coordinates[0] as num).toDouble() : 0,
    );
  }
}

class AddressSuggestionService {
  static Future<List<AddressSuggestion>> search(String query) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query.trim(),
      'limit': '6',
      'countrycode': 'VN',
    });
    final response = await http
        .get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoopiFood/1.0 (delivery address search)',
        })
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Dịch vụ tìm địa chỉ trả về mã ${response.statusCode}.');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final features = payload['features'] as List<dynamic>? ?? [];
    return features
        .map((item) => AddressSuggestion.fromJson(item as Map<String, dynamic>))
        .where((item) =>
            item.displayName.isNotEmpty &&
            item.latitude != 0 &&
            item.longitude != 0)
        .toList();
  }
}
