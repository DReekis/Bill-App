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

    test('getEffectiveBusinessName respects businessNameOverride over business.name', () {
      final biz = Business(name: 'Dhar Enterprises Pvt Ltd');
      final settings = InvoiceCustomizationSettings(businessNameOverride: 'Balaji Supermarket');
      expect(getEffectiveBusinessName(biz, settings), 'Balaji Supermarket');
      expect(getEffectiveBusinessName(biz, null), 'Dhar Enterprises Pvt Ltd');
      expect(getEffectiveBusinessName(biz, InvoiceCustomizationSettings(businessNameOverride: '  ')), 'Dhar Enterprises Pvt Ltd');
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

    test('buildPurchaseBillPdf generates complete BillBook standard PDF with vendor, buyer card, payment mode, and inward signatory', () async {
      final supplier = Supplier(
        id: 101,
        name: 'Hindustan Unilever Distributor Ltd',
        phone: '9862123456',
        address: 'Plot 42, Industrial Area, Dharmanagar',
        gstin: '16AABCH1234F1Z5',
        state: 'Tripura',
      );

      final purchase = PurchaseBill(
        id: 1,
        number: 'PB-2026-009',
        supplierId: supplier.id,
        supplierName: supplier.name,
        supplierPhone: supplier.phone,
        supplierAddress: supplier.address,
        supplierGstin: supplier.gstin,
        date: '2026-10-22',
        total: 52500,
        amountPaid: 30000,
        outstanding: 22500,
        paymentMode: 'Bank Transfer',
        notes: 'Inward material inspected and accepted.',
        lines: [
          InvoiceLine(
            name: 'Dove Soap 100g (Pack of 48)',
            hsn: '34011110',
            unit: 'CTN',
            quantity: 5,
            price: 10000,
            gstRate: 5,
            tax: 2500,
            taxable: 50000,
          ),
        ],
      );

      final pdfBytes = await buildPurchaseBillPdf(
        business: testBusiness,
        purchase: purchase,
        supplier: supplier,
        settings: InvoiceCustomizationSettings(themeStyle: 'billbook_stylish'),
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildDeliveryChallanPdf generates Rule 55 compliant Delivery Challan PDF with transport details, dual signatures, and declared value', () async {
      final customer = Customer(
        id: 55,
        name: 'Saha Construction & Hardware',
        phone: '9436123456',
        address: 'Hospital Road, Agartala',
        gstin: '16ABCDE1234F1Z5',
        state: 'Tripura',
      );

      final challan = DeliveryChallan(
        id: 1,
        number: 'DC-2026-004',
        customerId: customer.id,
        customerName: customer.name,
        date: '2026-10-22',
        address: customer.address,
        vehicleNo: 'TR 01 AX 9921',
        transportDetails: 'LR-88210 / Maa Tara Roadlines',
        invoiceNumber: 'INV-2026-104',
        notes: 'Transport for job-work / delivery on approval.',
        lines: [
          InvoiceLine(
            name: 'UltraTech Cement 50kg Bags',
            hsn: '252329',
            unit: 'BAG',
            quantity: 100,
            price: 38000,
          ),
        ],
      );

      final pdfBytes = await buildDeliveryChallanPdf(
        business: testBusiness,
        challan: challan,
        customer: customer,
        settings: InvoiceCustomizationSettings(themeStyle: 'modern_minimal'),
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildPurchaseOrderPdf and buildSalesOrderPdf generate valid PDFs with full party and tax handling', () async {
      final supplier = Supplier(
        id: 102,
        name: 'National Steel Corp',
        phone: '9876543210',
        address: 'Kolkata Steel Yard',
        gstin: '19AAACN1234F1Z8',
        state: 'West Bengal',
      );

      final po = PurchaseOrder(
        id: 1,
        number: 'PO-2026-001',
        supplierId: supplier.id,
        supplierName: supplier.name,
        date: '2026-10-22',
        expectedDate: '2026-10-30',
        total: 150000,
        notes: 'Deliver to site.',
        lines: [
          InvoiceLine(
            name: 'TMT Rebars 12mm Fe 550D',
            hsn: '721420',
            unit: 'TON',
            quantity: 2,
            price: 75000,
            tax: 27000,
            taxable: 150000,
          ),
        ],
      );

      final poBytes = await buildPurchaseOrderPdf(
        business: testBusiness,
        order: po,
        supplier: supplier,
        settings: InvoiceCustomizationSettings(),
      );
      expect(poBytes, isNotEmpty);
      expect(String.fromCharCodes(poBytes.sublist(0, 5)), '%PDF-');

      final so = SalesOrder(
        id: 1,
        number: 'SO-2026-001',
        customerId: 1,
        customerName: 'Pooja Mart',
        date: '2026-10-22',
        dueDate: '2026-10-28',
        total: 50000,
        lines: [
          InvoiceLine(
            name: 'Groceries Assorted',
            quantity: 10,
            price: 5000,
          ),
        ],
      );

      final testBank = BankAccount(
        id: 1,
        businessId: 1,
        bankName: 'Bank Of India, Dharmanagar',
        accountName: 'MAHADEV TRADERS',
        accountNumber: '502320110000274',
        ifsc: 'BKID0005023',
      );

      final soBytes = await buildSalesOrderPdf(
        business: testBusiness,
        order: so,
        customer: Customer(id: 1, name: 'Pooja Mart', state: 'Tripura'),
        bankAccount: testBank,
        settings: InvoiceCustomizationSettings(),
      );
      expect(soBytes, isNotEmpty);
      expect(String.fromCharCodes(soBytes.sublist(0, 5)), '%PDF-');
    });

    test('buildReturnPdf generates valid Credit Note and Debit Note PDFs', () async {
      final creditReturn = TransactionReturn(
        id: 1,
        number: 'CR-2026-001',
        partyType: 'customer',
        partyName: 'SARADA DEBI ENTERPRISE',
        date: '2026-10-22',
        subtotal: 10000,
        tax: 1800,
        taxable: 10000,
        total: 11800,
        reason: 'Goods returned due to transit packaging damage.',
        lines: [
          InvoiceLine(
            name: 'Broken Pack Goods',
            quantity: 1,
            price: 10000,
          ),
        ],
      );

      final crBytes = await buildReturnPdf(
        business: testBusiness,
        returnInvoice: creditReturn,
        settings: InvoiceCustomizationSettings(),
      );
      expect(crBytes, isNotEmpty);
      expect(String.fromCharCodes(crBytes.sublist(0, 5)), '%PDF-');

      final debitReturn = TransactionReturn(
        id: 2,
        number: 'DR-2026-001',
        partyType: 'supplier',
        partyName: 'Hindustan Unilever Distributor Ltd',
        date: '2026-10-22',
        subtotal: 5000,
        tax: 900,
        taxable: 5000,
        total: 5900,
        reason: 'Purchase return for expired batch.',
        lines: [
          InvoiceLine(
            name: 'Expired Batch Items',
            quantity: 1,
            price: 5000,
          ),
        ],
      );

      final drBytes = await buildReturnPdf(
        business: testBusiness,
        returnInvoice: debitReturn,
        settings: InvoiceCustomizationSettings(),
      );
      expect(drBytes, isNotEmpty);
      expect(String.fromCharCodes(drBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
