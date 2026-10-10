import 'dart:convert';
import 'package:http/http.dart' as http;

import '../data/repositories.dart';
import 'api_client.dart';
import 'gst_reports_service.dart';
import 'gst_service.dart';
import 'models.dart';

class EInvoiceResult {
  const EInvoiceResult({
    required this.irn,
    required this.ackNo,
    required this.ackDate,
    required this.signedQrCode,
    required this.status,
    required this.nicSchemaVersion,
  });

  final String irn;
  final String ackNo;
  final String ackDate;
  final String signedQrCode;
  final String status;
  final String nicSchemaVersion;

  factory EInvoiceResult.fromJson(Map<String, dynamic> json) {
    return EInvoiceResult(
      irn: json['irn'] as String? ?? '',
      ackNo: json['ackNo']?.toString() ?? '',
      ackDate: json['ackDate'] as String? ?? '',
      signedQrCode: json['signedQrCode'] as String? ?? '',
      status: json['status'] as String? ?? 'ACT',
      nicSchemaVersion: json['nicSchemaVersion'] as String? ?? '1.03',
    );
  }
}

class EWayBillResult {
  const EWayBillResult({
    required this.ewbNo,
    required this.ewbDate,
    required this.validUntil,
    required this.status,
    required this.vehicleNo,
    required this.distanceKm,
  });

  final String ewbNo;
  final String ewbDate;
  final String validUntil;
  final String status;
  final String vehicleNo;
  final int distanceKm;

  factory EWayBillResult.fromJson(Map<String, dynamic> json) {
    return EWayBillResult(
      ewbNo: json['ewbNo']?.toString() ?? '',
      ewbDate: json['ewbDate'] as String? ?? '',
      validUntil: json['validUntil'] as String? ?? '',
      status: json['status'] as String? ?? 'ACT',
      vehicleNo: json['vehicleNo'] as String? ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toInt() ?? 50,
    );
  }
}

/// Service orchestrating official Sandbox.co.in E-Invoice and E-Way Bill operations.
class ComplianceService {
  ComplianceService._();
  static final ComplianceService instance = ComplianceService._();

  /// Validates prerequisite requirements for B2B E-Invoice generation.
  static String? validateForEInvoice(Business business, Invoice invoice, {Customer? customer}) {
    final sellerGstin = (business.gstin ?? '').trim().toUpperCase();
    if (!GstService.isValidGstinFormat(sellerGstin)) {
      return 'Valid 15-character Business GSTIN is required. Please set in Settings > Business Details.';
    }

    final buyerGstin = (customer?.gstin ?? '').trim().toUpperCase();
    if (buyerGstin.isEmpty) {
      return 'B2B Recipient GSTIN is required to generate a Government E-Invoice.';
    }
    if (!GstService.isValidGstinFormat(buyerGstin)) {
      return 'Recipient GSTIN "$buyerGstin" is invalid. Please update party details.';
    }

    if (invoice.lines.isEmpty) {
      return 'Invoice must contain at least one line item.';
    }

    return null;
  }

  /// Generates official NIC Schema v1.03 E-Invoice (IRN & Signed QR Code).
  Future<EInvoiceResult> generateEInvoice({
    required Business business,
    required Invoice invoice,
    Customer? customer,
    ApiClient? apiClient,
  }) async {
    final validationError = validateForEInvoice(business, invoice, customer: customer);
    if (validationError != null) {
      throw StateError(validationError);
    }

    final client = apiClient ?? ApiClient();
    final url = '${client.baseUrl}/api/v1/einvoice/generate';

    final sellerGstin = business.gstin!.trim().toUpperCase();
    final buyerGstin = (customer?.gstin ?? '').trim().toUpperCase();

    final sellerStateCode = GstReportsService.resolveStateCode(gstin: sellerGstin);
    final buyerStateCode = GstReportsService.resolveStateCode(gstin: buyerGstin);

    final payload = {
      'invoiceId': invoice.id,
      'invoiceNumber': invoice.number,
      'invoiceDate': invoice.date,
      'supplyType': 'B2B',
      'reverseCharge': invoice.reverseCharge,
      'sellerGstin': sellerGstin,
      'sellerLegalName': business.name,
      'sellerTradeName': business.name,
      'sellerAddress': (business.address ?? 'Commercial Premises').trim(),
      'sellerCity': (business.city ?? 'Commercial City').trim(),
      'sellerStateCode': sellerStateCode,
      'sellerPincode': (business.pinCode ?? '560001').trim(),
      'buyerGstin': buyerGstin,
      'buyerLegalName': customer?.name ?? invoice.customerName ?? 'Buyer',
      'buyerTradeName': customer?.name ?? invoice.customerName ?? 'Buyer',
      'buyerAddress': (customer?.address ?? invoice.shipToAddress ?? 'Premises').trim(),
      'buyerCity': (customer?.city ?? 'City').trim(),
      'buyerStateCode': buyerStateCode,
      'buyerPincode': (invoice.shipToPincode ?? '560001').trim(),
      'placeOfSupply': invoice.placeOfSupply ?? buyerStateCode,
      'taxableAmount': invoice.taxable,
      'cgstAmount': invoice.cgst,
      'sgstAmount': invoice.sgst,
      'igstAmount': invoice.igst,
      'cessAmount': invoice.cess,
      'roundOff': invoice.roundOff,
      'totalInvoiceValue': invoice.total,
      'items': invoice.lines.map((l) => {
        'productName': l.name,
        'hsn': (l.hsn != null && l.hsn!.isNotEmpty) ? l.hsn : '84705000',
        'quantity': l.quantity,
        'unit': l.unit ?? 'NOS',
        'unitPrice': l.price,
        'grossAmount': (l.price * l.quantity).round(),
        'discount': l.discount,
        'taxableAmount': l.taxable,
        'gstRate': l.gstRate,
        'totalItemValue': (l.taxable + l.tax),
      }).toList(),
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (client.hasAuth) {
      headers['Authorization'] = 'Bearer ${client.token}';
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw StateError(err['error'] as String? ?? 'E-Invoice generation failed (${response.statusCode})');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = EInvoiceResult.fromJson(json);

    // Persist into SQLite
    final currentCustom = Map<String, dynamic>.from(invoice.customFields);
    currentCustom['ack_no'] = result.ackNo;
    currentCustom['ack_date'] = result.ackDate;
    currentCustom['signed_qr_code'] = result.signedQrCode;
    currentCustom['einvoice_status'] = 'ACT';
    currentCustom['nic_version'] = result.nicSchemaVersion;

    if (business.id != null && invoice.id != null) {
      await Repository.instance.updateInvoiceCompliance(
        business.id!,
        invoice.id!,
        irn: result.irn,
        customFieldsJson: jsonEncode(currentCustom),
      );
    }

    return result;
  }

  /// Cancels an existing E-Invoice IRN within the 24-hour statutory window.
  Future<void> cancelEInvoice({
    required int businessId,
    required Invoice invoice,
    required String reason, // 1: Duplicate, 2: Data entry error, 3: Order cancelled, 4: Others
    String? remarks,
    ApiClient? apiClient,
  }) async {
    final irn = invoice.irn;
    if (irn == null || irn.trim().isEmpty) {
      throw StateError('Cannot cancel: Invoice does not have an active IRN');
    }

    final client = apiClient ?? ApiClient();
    final url = '${client.baseUrl}/api/v1/einvoice/cancel';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (client.hasAuth) {
      headers['Authorization'] = 'Bearer ${client.token}';
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({
        'irn': irn,
        'reason': reason,
        'remarks': remarks ?? 'Cancelled via user application',
      }),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw StateError(err['error'] as String? ?? 'E-Invoice cancellation failed');
    }

    final currentCustom = Map<String, dynamic>.from(invoice.customFields);
    currentCustom['einvoice_status'] = 'CNL';
    currentCustom['einvoice_cancel_date'] = DateTime.now().toIso8601String();
    currentCustom['einvoice_cancel_reason'] = reason;

    if (invoice.id != null) {
      await Repository.instance.updateInvoiceCompliance(
        businessId,
        invoice.id!,
        customFieldsJson: jsonEncode(currentCustom),
      );
    }
  }

  /// Generates official 12-digit E-Way Bill (Part A & Part B).
  Future<EWayBillResult> generateEWayBill({
    required Business business,
    required Invoice invoice,
    required int distanceKm,
    required String vehicleNo,
    String? transportMode,
    String? vehicleType,
    String? transporterName,
    String? transporterId,
    String? transDocNo,
    Customer? customer,
    ApiClient? apiClient,
  }) async {
    final client = apiClient ?? ApiClient();
    final url = '${client.baseUrl}/api/v1/ewaybill/generate';

    final cleanVehicle = vehicleNo.trim().toUpperCase().replaceAll(' ', '');
    if (cleanVehicle.isEmpty) {
      throw StateError('Vehicle Number is required for E-Way Bill Part B.');
    }

    final sellerGstin = (business.gstin ?? '29AAAAA0000A1Z5').trim().toUpperCase();
    final buyerGstin = (customer?.gstin ?? '29AAAAA0000A1Z5').trim().toUpperCase();

    final fromState = GstReportsService.resolveStateCode(gstin: sellerGstin);
    final toState = GstReportsService.resolveStateCode(gstin: buyerGstin);

    final payload = {
      'invoiceNumber': invoice.number,
      'invoiceDate': invoice.date,
      'subSupplyType': '1',
      'docType': 'INV',
      'fromGstin': sellerGstin,
      'fromTradeName': business.name,
      'fromAddress': (business.address ?? 'Commercial Premises').trim(),
      'fromCity': (business.city ?? 'Commercial City').trim(),
      'fromPincode': (business.pinCode ?? '560001').trim(),
      'fromStateCode': fromState,
      'toGstin': buyerGstin,
      'toTradeName': customer?.name ?? invoice.customerName ?? 'Buyer',
      'toAddress': (customer?.address ?? invoice.shipToAddress ?? 'Premises').trim(),
      'toCity': (customer?.city ?? 'City').trim(),
      'toPincode': (invoice.shipToPincode ?? '560001').trim(),
      'toStateCode': toState,
      'totalValue': invoice.taxable,
      'cgstValue': invoice.cgst,
      'sgstValue': invoice.sgst,
      'igstValue': invoice.igst,
      'cessValue': invoice.cess,
      'totInvValue': invoice.total,
      'distanceKm': distanceKm,
      'vehicleNo': cleanVehicle,
      'vehicleType': vehicleType ?? 'R',
      'transportMode': transportMode ?? 'Road',
      'transporterName': transporterName,
      'transporterId': transporterId,
      'transDocNo': transDocNo,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (client.hasAuth) {
      headers['Authorization'] = 'Bearer ${client.token}';
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw StateError(err['error'] as String? ?? 'E-Way Bill generation failed');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = EWayBillResult.fromJson(json);

    // Persist into SQLite
    final currentCustom = Map<String, dynamic>.from(invoice.customFields);
    currentCustom['ewb_date'] = result.ewbDate;
    currentCustom['ewb_valid_until'] = result.validUntil;
    currentCustom['ewb_status'] = 'ACT';
    currentCustom['distance_km'] = result.distanceKm;
    if (transporterName != null && transporterName.isNotEmpty) {
      currentCustom['transporter_name'] = transporterName;
    }

    if (business.id != null && invoice.id != null) {
      await Repository.instance.updateInvoiceCompliance(
        business.id!,
        invoice.id!,
        ewayBillNumber: result.ewbNo,
        vehicleNumber: result.vehicleNo,
        customFieldsJson: jsonEncode(currentCustom),
      );
    }

    return result;
  }

  /// Cancels an existing E-Way Bill within 24 hours.
  Future<void> cancelEWayBill({
    required int businessId,
    required Invoice invoice,
    required String reason, // 1: Duplicate, 2: Order Cancelled, 3: Data Entry Error, 4: Others
    String? remarks,
    ApiClient? apiClient,
  }) async {
    final ewbNo = invoice.ewayBillNumber;
    if (ewbNo == null || ewbNo.trim().isEmpty) {
      throw StateError('Cannot cancel: Invoice does not have an active E-Way Bill Number');
    }

    final client = apiClient ?? ApiClient();
    final url = '${client.baseUrl}/api/v1/ewaybill/cancel';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (client.hasAuth) {
      headers['Authorization'] = 'Bearer ${client.token}';
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({
        'ewbNo': ewbNo,
        'reason': reason,
        'remarks': remarks ?? 'Cancelled by user',
      }),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw StateError(err['error'] as String? ?? 'E-Way Bill cancellation failed');
    }

    final currentCustom = Map<String, dynamic>.from(invoice.customFields);
    currentCustom['ewb_status'] = 'CNL';
    currentCustom['ewb_cancel_date'] = DateTime.now().toIso8601String();

    if (invoice.id != null) {
      await Repository.instance.updateInvoiceCompliance(
        businessId,
        invoice.id!,
        customFieldsJson: jsonEncode(currentCustom),
      );
    }
  }
}
