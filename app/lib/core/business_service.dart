import 'dart:convert';

import 'api_client.dart';

class BusinessDto {
  const BusinessDto(
      {required this.id,
      required this.name,
      required this.ownerName,
      required this.currency});

  final String id;
  final String name;
  final String? ownerName;
  final String currency;

  factory BusinessDto.fromJson(Map<String, dynamic> json) {
    return BusinessDto(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerName: json['ownerName'] as String?,
      currency: json['currency'] as String? ?? 'INR',
    );
  }
}

class BusinessService {
  const BusinessService(this._client);

  final ApiClient _client;

  Future<List<BusinessDto>> fetchBusinesses() async {
    final response = await _client.get('/api/v1/businesses');
    if (response.statusCode >= 400) {
      throw Exception(
          jsonDecode(response.body)['error'] ?? 'Failed to load businesses');
    }

    final body = jsonDecode(response.body) as List<dynamic>;
    return body
        .map((item) => BusinessDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BusinessDto> createBusiness(
      {required String name,
      String? ownerName,
      String? gstin,
      String? city,
      String? state,
      String? address}) async {
    final response = await _client.post('/api/v1/businesses', {
      'name': name,
      if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
      if (gstin != null && gstin.isNotEmpty) 'gstin': gstin,
      if (city != null && city.isNotEmpty) 'city': city,
      if (state != null && state.isNotEmpty) 'state': state,
      if (address != null && address.isNotEmpty) 'address': address,
      'currency': 'INR',
    });

    if (response.statusCode >= 400) {
      throw Exception(
          jsonDecode(response.body)['error'] ?? 'Business creation failed');
    }

    return BusinessDto.fromJson(jsonDecode(response.body));
  }
}
