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

    test('buildDocumentPdf renders billbook_stylish with custom brand color and party cards', () async {
      final settings = InvoiceCustomizationSettings(
        themeStyle: 'billbook_stylish',
        primaryColorHex: '#4338CA',
        showShipTo: true,
        showHsnColumn: true,
        showUnitColumn: true,
        showDiscountColumn: true,
        showTaxColumn: true,
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'INV-BB-001',
        date: '2026-10-12',
        partyName: 'Apex Retails Ltd',
        partyGstin: '16AABCA1234F1Z1',
        shipToName: 'Apex Warehouse 2',
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
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildDocumentPdf renders modern_minimal borderless layout cleanly', () async {
      final settings = InvoiceCustomizationSettings(
        themeStyle: 'modern_minimal',
        primaryColorHex: '#0F766E',
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Invoice',
        number: 'MIN-001',
        date: '2026-10-12',
        partyName: 'Studio Nordic',
        lines: testLines,
        subtotal: 88000,
        discount: 1000,
        taxable: 87000,
        igst: 0,
        cgst: 2175,
        sgst: 2175,
        roundOff: 0,
        total: 91350,
        outstandingPaise: 40000,
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildDocumentPdf renders gst_tax_pro with explicit CGST and SGST columns', () async {
      final settings = InvoiceCustomizationSettings(
        themeStyle: 'gst_tax_pro',
        primaryColorHex: '#1E3A8A',
        showHsnColumn: true,
        showUnitColumn: true,
        showDiscountColumn: true,
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'GST-PRO-99',
        date: '2026-10-12',
        partyName: 'Bharat Hardware Enterprise',
        partyGstin: '16AAECB5678F1Z9',
        placeOfSupply: 'Tripura (16)',
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
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildDocumentPdf renders compact_pos single-page layout', () async {
      final settings = InvoiceCustomizationSettings(
        themeStyle: 'compact_pos',
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Cash Receipt',
        number: 'CPOS-102',
        date: '2026-10-12',
        partyName: 'Walk-in Retail Buyer',
        lines: testLines,
        subtotal: 88000,
        discount: 0,
        taxable: 88000,
        igst: 0,
        cgst: 2200,
        sgst: 2200,
        roundOff: 0,
        total: 92400,
        outstandingPaise: 0,
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('generateCommercialSamplePdf executes across all 5 templates flawlessly', () async {
      final testBank = BankAccount(
        id: 1,
        businessId: 1,
        bankName: 'HDFC Bank',
        accountNumber: '50200012345678',
        ifsc: 'HDFC0001234',
      );
      final styles = ['billbook_stylish', 'classic_grid', 'modern_minimal', 'gst_tax_pro', 'compact_pos', 'modern_band'];
      for (final s in styles) {
        final settings = InvoiceCustomizationSettings(themeStyle: s, primaryColorHex: '#065F46');
        final bytes = await generateCommercialSamplePdf(
          business: testBusiness,
          settings: settings,
          bankAccount: testBank,
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      }
    });

    test('buildDocumentPdf renders multi-page invoice with closing container at end', () async {
      final testBank = BankAccount(
        id: 1,
        businessId: 1,
        bankName: 'Axis Bank, DHARMANAGAR',
        accountName: 'Bishwajit Dhar',
        accountNumber: '923010060652484',
        ifsc: 'UTIB0000708',
      );

      final multiLines = List.generate(
        25,
        (i) => InvoiceLine(
          name: 'Item ${i + 1} Industrial PVC Pipe 20mm',
          hsn: '39174000',
          quantity: (i + 1) * 10,
          unit: 'Pcs',
          price: 4500,
          discount: 0,
          taxable: (i + 1) * 45000,
          tax: (i + 1) * 8100,
          gstRate: 18,
        ),
      );

      final totalTaxable = multiLines.fold(0, (s, l) => s + l.taxable);
      final totalTax = multiLines.fold(0, (s, l) => s + l.tax);
      final grandTotal = totalTaxable + totalTax;

      final settings = InvoiceCustomizationSettings(
        themeStyle: 'billbook_stylish',
        primaryColorHex: '#6B21A8',
        showBankDetails: true,
        showUpiQr: true,
        showTerms: true,
        showDeclaration: true,
        showHsnSummaryTable: true,
        bankQrPlacement: 'left',
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'MT/2026-27/01137',
        date: '2026-08-28',
        partyName: 'BALAJI ENTERPRISE',
        lines: multiLines,
        subtotal: totalTaxable,
        discount: 0,
        taxable: totalTaxable,
        igst: 0,
        cgst: totalTax ~/ 2,
        sgst: totalTax - (totalTax ~/ 2),
        roundOff: 0,
        total: grandTotal,
        outstandingPaise: 0,
        bankAccount: testBank,
        termsText: '1. Goods once sold will not be taken back.\n2. Interest @18% p.a. charged if payment not made within due date.',
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildDocumentPdf renders with bankQrPlacement right cleanly', () async {
      final testBank = BankAccount(
        id: 1,
        businessId: 1,
        bankName: 'Bank Of India, Dharmanagar',
        accountName: 'MAHADEV TRADERS',
        accountNumber: '502320110000274',
        ifsc: 'BKID0005023',
      );

      final settings = InvoiceCustomizationSettings(
        themeStyle: 'classic_grid',
        showBankDetails: true,
        showUpiQr: true,
        showTerms: true,
        bankQrPlacement: 'right',
      );

      final pdfBytes = await buildDocumentPdf(
        business: testBusiness,
        title: 'Tax Invoice',
        number: 'INV-RIGHT-001',
        date: '2026-08-28',
        partyName: 'SARADA DEBI ENTERPRISE',
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
        bankAccount: testBank,
        termsText: 'Payment due upon receipt.',
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
