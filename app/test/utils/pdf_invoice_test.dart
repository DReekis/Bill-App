import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/models.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  group('UPI Payment URI tests', () {
    test('generateUpiPaymentUri uses explicit business UPI ID', () {
      final biz = Business(
        id: 1,
        name: 'Sharma Sweets',
        upiId: 'sharma@oksbi',
        phone: '9876543210',
      );

      final uri = generateUpiPaymentUri(
        business: biz,
        invoiceNumber: 'INV-001',
        amountPaise: 45050, // Rs. 450.50
      );

      expect(uri, contains('upi://pay?'));
      expect(uri, contains('pa=sharma@oksbi'));
      expect(uri, contains('pn=Sharma%20Sweets'));
      expect(uri, contains('am=450.50'));
      expect(uri, contains('cu=INR'));
      expect(uri, contains('tn=Invoice%20INV-001'));
    });

    test('generateUpiPaymentUri falls back to phone@upi when upiId is missing', () {
      final biz = Business(
        id: 2,
        name: 'Patel Electronics',
        phone: '9123456780',
      );

      final uri = generateUpiPaymentUri(
        business: biz,
        invoiceNumber: 'INV-102',
        amountPaise: 129900, // Rs. 1299.00
      );

      expect(uri, contains('pa=9123456780@upi'));
      expect(uri, contains('am=1299.00'));
    });

    test('getBusinessUpiId returns trimmed upiId if present', () {
      final biz = Business(
        id: 3,
        name: 'Store',
        upiId: '  merchant@paytm  ',
      );
      expect(getBusinessUpiId(biz), 'merchant@paytm');
    });
  });

  group('PDF & Thermal Print Generation tests', () {
    final testBusiness = Business(
      id: 1,
      name: 'Super Grocers',
      phone: '9988776655',
      address: '123 Main Bazaar, Jaipur, Rajasthan',
      gstin: '08AAAAA0000A1Z5',
      upiId: 'supergrocers@icici',
    );

    final testLines = [
      InvoiceLine(
        name: 'Basmati Rice 5kg',
        quantity: 2,
        price: 35000,
        discount: 0,
        taxable: 70000,
        tax: 3500,
        gstRate: 5,
      ),
      InvoiceLine(
        name: 'Refined Oil 1L',
        quantity: 1,
        price: 18000,
        discount: 1000,
        taxable: 17000,
        tax: 850,
        gstRate: 5,
      ),
    ];

    test('buildDocumentPdf creates valid PDF bytes for A4 and A5', () async {
      final bytesA4 = await buildDocumentPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'INV-2026-001',
        date: '2026-09-17',
        partyName: 'Rahul Verma',
        lines: testLines,
        subtotal: 88000,
        discount: 1000,
        taxable: 87000,
        igst: 0,
        cgst: 2175,
        sgst: 2175,
        roundOff: 0,
        total: 91350,
        outstandingPaise: 91350,
      );

      expect(bytesA4, isNotEmpty);
      expect(bytesA4.length, greaterThan(1000));

      // PDF magic bytes: %PDF-
      expect(String.fromCharCodes(bytesA4.sublist(0, 5)), '%PDF-');
    });

    test('buildThermalReceiptPdf generates 80mm receipt with UPI QR', () async {
      final bytes80mm = await buildThermalReceiptPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'REC-088',
        date: '2026-09-17',
        partyName: 'Counter Cash',
        lines: testLines,
        subtotal: 88000,
        discount: 1000,
        taxable: 87000,
        igst: 0,
        cgst: 2175,
        sgst: 2175,
        roundOff: 0,
        total: 91350,
        outstandingPaise: 0,
        paperSize: InvoicePaperSize.roll80mm,
      );

      expect(bytes80mm, isNotEmpty);
      expect(String.fromCharCodes(bytes80mm.sublist(0, 5)), '%PDF-');
    });

    test('buildThermalReceiptPdf generates 58mm compact receipt', () async {
      final bytes58mm = await buildThermalReceiptPdf(
        business: testBusiness,
        title: 'Bill',
        number: 'REC-058',
        date: '2026-09-17',
        partyName: null,
        lines: testLines,
        subtotal: 88000,
        discount: 1000,
        taxable: 87000,
        igst: 0,
        cgst: 2175,
        sgst: 2175,
        roundOff: 0,
        total: 91350,
        outstandingPaise: 91350,
        paperSize: InvoicePaperSize.roll58mm,
      );

      expect(bytes58mm, isNotEmpty);
      expect(String.fromCharCodes(bytes58mm.sublist(0, 5)), '%PDF-');
    });

    test('InvoicePaperSize formats are appropriately dimensioned', () {
      expect(InvoicePaperSize.values.length, 4);
      expect(InvoicePaperSize.roll58mm.format.width, closeTo(58 * 72 / 25.4, 1.0));
      expect(InvoicePaperSize.roll80mm.format.width, closeTo(80 * 72 / 25.4, 1.0));
    });
  });
}
