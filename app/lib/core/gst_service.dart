import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Comprehensive model for business information derived or fetched from a GSTIN.
class GstBusinessInfo {
  const GstBusinessInfo({
    required this.gstin,
    required this.valid,
    this.businessName,
    this.tradeName,
    this.legalName,
    this.ownerName,
    this.pan,
    this.stateCode,
    this.state,
    this.city,
    this.address,
    this.pinCode,
    this.constitution,
    this.industry,
    this.isComposition = false,
    this.status = 'Active',
    this.registrationDate,
    this.isOnlineFetched = false,
  });

  final String gstin;
  final bool valid;
  final String? businessName;
  final String? tradeName;
  final String? legalName;
  final String? ownerName;
  final String? pan;
  final String? stateCode;
  final String? state;
  final String? city;
  final String? address;
  final String? pinCode;
  final String? constitution;
  final String? industry;
  final bool isComposition;
  final String status;
  final String? registrationDate;
  final bool isOnlineFetched;

  /// Returns the most descriptive business name available.
  String get effectiveName {
    if (tradeName != null && tradeName!.trim().isNotEmpty) return tradeName!.trim();
    if (businessName != null && businessName!.trim().isNotEmpty) return businessName!.trim();
    if (legalName != null && legalName!.trim().isNotEmpty) return legalName!.trim();
    return '';
  }

  /// Returns the owner / proprietor name.
  String get effectiveOwner {
    if (ownerName != null && ownerName!.trim().isNotEmpty) return ownerName!.trim();
    if (legalName != null && legalName!.trim().isNotEmpty && (constitution == 'Sole Proprietorship' || constitution == 'Individual')) {
      return legalName!.trim();
    }
    return '';
  }

  bool get isActive => status.toLowerCase() == 'active';

  factory GstBusinessInfo.fromJson(Map<String, dynamic> json) {
    return GstBusinessInfo(
      gstin: json['gstin'] as String? ?? '',
      valid: json['valid'] as bool? ?? true,
      businessName: json['businessName'] as String?,
      tradeName: json['tradeName'] as String?,
      legalName: json['legalName'] as String?,
      ownerName: json['ownerName'] as String?,
      pan: json['pan'] as String?,
      stateCode: json['stateCode'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      address: json['address'] as String?,
      pinCode: json['pinCode'] as String?,
      constitution: json['constitution'] as String?,
      industry: json['industry'] as String?,
      isComposition: json['isComposition'] as bool? ?? (json['taxpayerType'] == 'Composition'),
      status: json['status'] as String? ?? 'Active',
      registrationDate: json['registrationDate'] as String?,
      isOnlineFetched: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'gstin': gstin,
        'valid': valid,
        'businessName': businessName,
        'tradeName': tradeName,
        'legalName': legalName,
        'ownerName': ownerName,
        'pan': pan,
        'stateCode': stateCode,
        'state': state,
        'city': city,
        'address': address,
        'pinCode': pinCode,
        'constitution': constitution,
        'industry': industry,
        'isComposition': isComposition,
        'status': status,
        'registrationDate': registrationDate,
        'isOnlineFetched': isOnlineFetched,
      };
}

/// Service providing offline deterministic derivation and online public GST lookup.
class GstService {
  GstService._();
  static final GstService instance = GstService._();

  /// Standard GST State Code Table for all 36 Indian States and Union Territories.
  static const Map<String, String> stateCodes = {
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
    '99': 'Centre Jurisdiction',
  };

  /// Indian PAN 4th character entity / constitution mapping.
  static const Map<String, String> panEntityTypes = {
    'P': 'Sole Proprietorship',
    'C': 'Company',
    'F': 'Partnership / LLP',
    'H': 'Hindu Undivided Family (HUF)',
    'A': 'Association of Persons (AOP)',
    'T': 'Trust',
    'B': 'Body of Individuals (BOI)',
    'L': 'Local Authority',
    'J': 'Artificial Juridical Person',
    'G': 'Government Agency',
  };

  /// Validates standard 15-character Indian GSTIN format.
  static bool isValidGstinFormat(String? gstin) {
    if (gstin == null) return false;
    final clean = gstin.trim().toUpperCase();
    if (clean.length != 15) return false;
    return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(clean);
  }

  /// Derives business information deterministically from the GSTIN string without any network dependency.
  static GstBusinessInfo parseDeterministic(String gstin) {
    final clean = gstin.trim().toUpperCase();
    final isValid = isValidGstinFormat(clean);

    if (clean.length < 2) {
      return GstBusinessInfo(gstin: clean, valid: false);
    }

    final stateCode = clean.substring(0, 2);
    final stateName = stateCodes[stateCode];

    String? pan;
    String? constitution;
    String? industry = 'Retail';

    if (clean.length >= 12) {
      pan = clean.substring(2, 12);
      final entityChar = pan.length >= 4 ? pan[3] : '';
      constitution = panEntityTypes[entityChar] ?? 'Business Entity';

      switch (entityChar) {
        case 'P':
          industry = 'Retail';
          break;
        case 'C':
          industry = 'Manufacturing';
          break;
        case 'F':
          industry = 'Wholesale';
          break;
        case 'T':
        case 'A':
          industry = 'Services';
          break;
        default:
          industry = 'Retail';
      }
    }

    return GstBusinessInfo(
      gstin: clean,
      valid: isValid,
      pan: pan,
      stateCode: stateCode,
      state: stateName,
      constitution: constitution,
      industry: industry,
      status: 'Active',
      isComposition: false,
      isOnlineFetched: false,
    );
  }

  /// Looks up business details from a GSTIN.
  /// 1. Tries backend `/api/v1/gst/lookup/:gstin` via [apiClient].
  /// 2. If backend is unavailable, queries public GST registry endpoints.
  /// 3. If offline or error occurs, seamlessly falls back to [parseDeterministic].
  Future<GstBusinessInfo> lookup(String gstin, {ApiClient? apiClient}) async {
    final clean = gstin.trim().toUpperCase();
    final fallback = parseDeterministic(clean);
    if (!isValidGstinFormat(clean)) {
      return fallback;
    }

    // 1. Try local backend proxy if available
    try {
      final client = apiClient ?? ApiClient();
      final url = '${client.baseUrl}/api/v1/gst/lookup/$clean';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 2500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return GstBusinessInfo.fromJson(data);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Backend GST lookup skipped/failed: $e');
      }
    }

    // 2. Try direct public GST directory lookup
    try {
      final directUrl = 'https://sheet.gstincheck.co.in/check/$clean';
      final response = await http.get(
        Uri.parse(directUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 3000));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json is Map<String, dynamic> && json['flag'] == true && json['data'] != null) {
          final d = json['data'] as Map<String, dynamic>;
          final pradr = d['pradr'] as Map<String, dynamic>?;
          final addr = pradr?['addr'] as Map<String, dynamic>?;

          final tradeName = d['tradeNam'] as String?;
          final legalName = d['lgnm'] as String?;
          final city = addr?['dst'] as String? ?? addr?['city'] as String?;
          final pinCode = addr?['pncd'] as String?;
          final addressParts = [
            addr?['bno'],
            addr?['bnm'],
            addr?['st'],
            addr?['loc'],
            city,
            addr?['stcd'],
            pinCode,
          ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');

          final status = d['sts'] as String? ?? 'Active';
          final dty = d['dty'] as String? ?? 'Regular';

          return GstBusinessInfo(
            gstin: clean,
            valid: true,
            tradeName: tradeName?.isNotEmpty == true ? tradeName : null,
            businessName: tradeName?.isNotEmpty == true ? tradeName : legalName,
            legalName: legalName,
            ownerName: legalName,
            pan: fallback.pan,
            stateCode: fallback.stateCode,
            state: fallback.state,
            city: city,
            address: addressParts.isNotEmpty ? addressParts : null,
            pinCode: pinCode,
            constitution: d['ctb'] as String? ?? fallback.constitution,
            industry: fallback.industry,
            isComposition: dty.toLowerCase().contains('composition'),
            status: status,
            registrationDate: d['rgdt'] as String?,
            isOnlineFetched: true,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Public GST lookup skipped/failed: $e');
      }
    }

    // 3. Guaranteed reliable fallback to deterministic parsing
    return fallback;
  }
}
