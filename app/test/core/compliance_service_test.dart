import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/compliance_service.dart';
import 'package:billket/core/models.dart';

void main() {
  group('ComplianceService Validation Tests', () {
    final validBusiness = Business(
      id: 1,
      name: 'Modern Retail Enterprises Pvt Ltd',
      gstin: '29AAAAA0000A1Z5',
      address: '104, MG Road, Brigade Junction',
      city: 'Bengaluru',
      pinCode: '560001',
    );

    final unregBusiness = Business(
      id: 2,
      name: 'Corner Kirana',
      gstin: null,
    );

    final validCustomer = Customer(
      id: 10,
      name: 'Apex Electronics LLP',
      gstin: '27AAPFU0939F1ZV',
      address: 'Shop 12, Lamington Road',
      city: 'Mumbai',
    );

    final unregCustomer = Customer(
      id: 11,
      name: 'Cash Customer',
      gstin: null,
    );

    test('blocks E-Invoice if business GSTIN is missing or invalid', () {
      final inv = Invoice(
        id: 1,
        number: 'INV-101',
        date: '2026-10-10',
        lines: [
          InvoiceLine(name: 'Item 1', price: 10000, quantity: 1, gstRate: 18),
        ],
      );

      final err = ComplianceService.validateForEInvoice(unregBusiness, inv, customer: validCustomer);
      expect(err, isNotNull);
      expect(err, contains('Business GSTIN is required'));
    });

    test('blocks E-Invoice if recipient GSTIN is missing (B2C cannot have IRN)', () {
      final inv = Invoice(
        id: 1,
        number: 'INV-101',
        date: '2026-10-10',
        lines: [
          InvoiceLine(name: 'Item 1', price: 10000, quantity: 1, gstRate: 18),
        ],
      );

      final err = ComplianceService.validateForEInvoice(validBusiness, inv, customer: unregCustomer);
      expect(err, isNotNull);
      expect(err, contains('B2B Recipient GSTIN is required'));
    });

    test('blocks E-Invoice if invoice has zero lines', () {
      final inv = Invoice(
        id: 1,
        number: 'INV-101',
        date: '2026-10-10',
        lines: [],
      );

      final err = ComplianceService.validateForEInvoice(validBusiness, inv, customer: validCustomer);
      expect(err, isNotNull);
      expect(err, contains('at least one line item'));
    });

    test('passes validation for fully compliant B2B transaction', () {
      final inv = Invoice(
        id: 1,
        number: 'INV-101',
        date: '2026-10-10',
        lines: [
          InvoiceLine(name: 'Item 1', price: 10000, quantity: 1, gstRate: 18),
        ],
      );

      final err = ComplianceService.validateForEInvoice(validBusiness, inv, customer: validCustomer);
      expect(err, isNull);
    });
  });

  group('Invoice Model Compliance Getters', () {
    test('extracts IRN and signed QR code from customFieldsJson', () {
      final customJson = jsonEncode({
        'ack_no': '1226101012345678',
        'ack_date': '2026-10-10 14:30:00',
        'signed_qr_code': 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature',
        'einvoice_status': 'ACT',
        'ewb_date': '2026-10-10T14:30:00.000Z',
        'ewb_valid_until': '2026-10-12T14:30:00.000Z',
        'ewb_status': 'ACT',
        'transporter_name': 'VRL Logistics',
        'distance_km': 450,
      });

      final inv = Invoice(
        id: 101,
        number: 'BILL-900',
        date: '2026-10-10',
        irn: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
        ewayBillNumber: '292610123456',
        vehicleNumber: 'KA01AB1234',
        customFieldsJson: customJson,
      );

      expect(inv.hasEInvoice, isTrue);
      expect(inv.irn, 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(inv.ackNo, '1226101012345678');
      expect(inv.ackDate, '2026-10-10 14:30:00');
      expect(inv.signedQrCode, contains('eyJhbGciOi'));
      expect(inv.einvoiceStatus, 'ACT');

      expect(inv.hasEWayBill, isTrue);
      expect(inv.ewayBillNumber, '292610123456');
      expect(inv.vehicleNumber, 'KA01AB1234');
      expect(inv.transporterName, 'VRL Logistics');
      expect(inv.distanceKm, 450);
      expect(inv.ewbStatus, 'ACT');
    });

    test('marks hasEInvoice false when status is CNL', () {
      final customJson = jsonEncode({
        'einvoice_status': 'CNL',
        'ewb_status': 'CNL',
      });

      final inv = Invoice(
        id: 102,
        number: 'BILL-901',
        date: '2026-10-10',
        irn: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
        ewayBillNumber: '292610123456',
        customFieldsJson: customJson,
      );

      expect(inv.hasEInvoice, isFalse);
      expect(inv.hasEWayBill, isFalse);
    });
  });

  group('EInvoiceResult & EWayBillResult Deserialization', () {
    test('accurately parses official backend payloads', () {
      final einv = EInvoiceResult.fromJson({
        'irn': '64hexcharsstringmockhere1234567890123456789012345678901234567890',
        'ackNo': '1226101099887766',
        'ackDate': '2026-10-10 15:00:00',
        'signedQrCode': 'signed_jwt_qr_string',
        'status': 'ACT',
        'nicSchemaVersion': '1.03',
      });

      expect(einv.irn.length, 64);
      expect(einv.ackNo, '1226101099887766');
      expect(einv.status, 'ACT');
      expect(einv.nicSchemaVersion, '1.03');

      final ewb = EWayBillResult.fromJson({
        'ewbNo': '241049281092',
        'ewbDate': '2026-10-10T15:00:00.000Z',
        'validUntil': '2026-10-12T15:00:00.000Z',
        'status': 'ACT',
        'vehicleNo': 'KA01AB1234',
        'distanceKm': 250,
      });

      expect(ewb.ewbNo, '241049281092');
      expect(ewb.distanceKm, 250);
      expect(ewb.vehicleNo, 'KA01AB1234');
      expect(ewb.status, 'ACT');
    });
  });
}
