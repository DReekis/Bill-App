import 'dart:convert';

import 'api_client.dart';

class BusinessDto {
  const BusinessDto({
    required this.id,
    required this.name,
    this.ownerName,
    this.phone,
    this.email,
    this.gstin,
    this.pan,
    this.address,
    this.city,
    this.state,
    this.pinCode,
    this.country = 'India',
    this.industry,
    this.taxRegistered = false,
    this.invoicePrefix = 'INV',
    this.currency = 'INR',
    this.subscriptionTier = 'free',
    this.subscriptionStatus = 'active',
    this.upiId,
  });

  final String id;
  final String name;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? pan;
  final String? address;
  final String? city;
  final String? state;
  final String? pinCode;
  final String country;
  final String? industry;
  final bool taxRegistered;
  final String invoicePrefix;
  final String currency;
  final String subscriptionTier;
  final String subscriptionStatus;
  final String? upiId;

  factory BusinessDto.fromJson(Map<String, dynamic> json) {
    return BusinessDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      ownerName: json['ownerName'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      gstin: json['gstin'] as String?,
      pan: json['pan'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pinCode: json['pinCode'] as String?,
      country: json['country'] as String? ?? 'India',
      industry: json['industry'] as String?,
      taxRegistered: json['taxRegistered'] as bool? ?? false,
      invoicePrefix: json['invoicePrefix'] as String? ?? 'INV',
      currency: json['currency'] as String? ?? 'INR',
      subscriptionTier: json['subscriptionTier'] as String? ?? 'free',
      subscriptionStatus: json['subscriptionStatus'] as String? ?? 'active',
      upiId: json['upiId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (ownerName != null) 'ownerName': ownerName,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (gstin != null) 'gstin': gstin,
        if (pan != null) 'pan': pan,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (pinCode != null) 'pinCode': pinCode,
        'country': country,
        if (industry != null) 'industry': industry,
        'taxRegistered': taxRegistered,
        'invoicePrefix': invoicePrefix,
        'currency': currency,
        'subscriptionTier': subscriptionTier,
        'subscriptionStatus': subscriptionStatus,
        if (upiId != null) 'upiId': upiId,
      };
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

  Future<BusinessDto> createBusiness({
    required String name,
    String? ownerName,
    String? phone,
    String? email,
    String? gstin,
    String? pan,
    String? address,
    String? city,
    String? state,
    String? pinCode,
    String? country,
    String? industry,
    bool? taxRegistered,
    String? invoicePrefix,
    String? upiId,
  }) async {
    final response = await _client.post('/api/v1/businesses', {
      'name': name,
      if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (gstin != null && gstin.isNotEmpty) 'gstin': gstin,
      if (pan != null && pan.isNotEmpty) 'pan': pan,
      if (address != null && address.isNotEmpty) 'address': address,
      if (city != null && city.isNotEmpty) 'city': city,
      if (state != null && state.isNotEmpty) 'state': state,
      if (pinCode != null && pinCode.isNotEmpty) 'pinCode': pinCode,
      if (country != null && country.isNotEmpty) 'country': country,
      if (industry != null && industry.isNotEmpty) 'industry': industry,
      if (taxRegistered != null) 'taxRegistered': taxRegistered,
      if (invoicePrefix != null && invoicePrefix.isNotEmpty) 'invoicePrefix': invoicePrefix,
      if (upiId != null && upiId.isNotEmpty) 'upiId': upiId,
      'currency': 'INR',
    });

    if (response.statusCode >= 400) {
      throw Exception(
          jsonDecode(response.body)['error'] ?? 'Business creation failed');
    }

    return BusinessDto.fromJson(jsonDecode(response.body));
  }

  Future<BusinessDto> updateBusiness(
    String id, {
    String? name,
    String? ownerName,
    String? phone,
    String? email,
    String? gstin,
    String? pan,
    String? address,
    String? city,
    String? state,
    String? pinCode,
    String? country,
    String? industry,
    bool? taxRegistered,
    String? invoicePrefix,
    String? upiId,
  }) async {
    final payload = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (ownerName != null) 'ownerName': ownerName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (gstin != null) 'gstin': gstin,
      if (pan != null) 'pan': pan,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (pinCode != null) 'pinCode': pinCode,
      if (country != null) 'country': country,
      if (industry != null) 'industry': industry,
      if (taxRegistered != null) 'taxRegistered': taxRegistered,
      if (invoicePrefix != null) 'invoicePrefix': invoicePrefix,
      if (upiId != null) 'upiId': upiId,
    };

    final response = await _client.patch('/api/v1/businesses/$id', payload);
    if (response.statusCode >= 400) {
      throw Exception(
          jsonDecode(response.body)['error'] ?? 'Business update failed');
    }

    return BusinessDto.fromJson(jsonDecode(response.body));
  }
}
