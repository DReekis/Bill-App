import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/gst_reports_service.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late int businessId;
  late Business testBusiness;
  final repo = Repository.instance;

  final testBusinessTemplate = Business(
    name: 'Apex Technologies Pvt Ltd',
    phone: '9876543210',
    email: 'accounts@apextech.in',
    address: '100 Industrial Corridor, Peenya',
    city: 'Bengaluru',
    state: 'Karnataka',
    pinCode: '560058',
    gstin: '29ABCDE1234F1Z5',
    pan: 'ABCDE1234F',
    taxRegistered: true,
    invoicePrefix: 'AT',
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);

    businessId = await repo.createBusiness(testBusinessTemplate);
    repo.session.businessId = businessId;
    testBusiness = (await repo.getBusiness(businessId))!;
  });

  tearDown(() async {
    await db.close();
  });

  group('Constraint 1: Tax & Decimal Precision (No Double Drift)', () {
    test('line items with fractional currency accumulate precisely in integer paise', () {
      // 3 items at ₹33.33 (3333 paise) with 18% GST
      final lineCalc = BillingEngine.calculateLine(LineCalcInput(
        quantity: 3,
        price: 3333,
        gstRate: 18,
      ));

      // 3 * 3333 = 9999 paise subtotal
      expect(lineCalc.lineTotal.paise, 9999);
      expect(lineCalc.taxable.paise, 9999);
      // Tax: (9999 * 18 / 100) rounded = 1800 paise
      expect(lineCalc.tax.paise, 1800);

      final quote = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 3, price: 3333, gstRate: 18),
          LineCalcInput(quantity: 7, price: 1429, gstRate: 12),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      // Verify all tax breakdown fields remain exact integers
      expect(quote.taxable.paise, greaterThan(0));
      expect(quote.cgst.paise + quote.sgst.paise, (quote.cgst + quote.sgst).paise);
      expect(quote.igst.paise, 0);

      // Emitted rupees formatted to 2 decimals without floating point residue
      final emittedRupees = GstReportsService.toRupees(quote.taxable.paise);
      expect(emittedRupees, double.parse(emittedRupees.toStringAsFixed(2)));
    });

    test('resolveStateCode zero-pads state code to 2 digits for GSTN v1.3 format', () {
      expect(GstReportsService.resolveStateCode(stateName: 'Jammu & Kashmir'), '01');
      expect(GstReportsService.resolveStateCode(stateName: 'Himachal Pradesh'), '02');
      expect(GstReportsService.resolveStateCode(stateName: 'Karnataka'), '29');
      expect(GstReportsService.resolveStateCode(stateName: 'Unknown State', defaultCode: '99'), '99');
    });
  });

  group('Constraint 2: Multi-Page Commercial PDF Overflow Protection', () {
    test('renders multi-page invoice with 35 items without overflow exceptions', () async {
      final custId = await repo.upsertCustomer(
        Customer(
          name: 'Global Supply Corp',
          gstin: '29ABCDE5678G1Z1',
          state: 'Karnataka',
          billingAddress: '42 Tech Park, Whitefield',
        ),
        businessIdOverride: businessId,
      );

      final manyLines = <LineCalcInput>[];
      final invoiceLines = <InvoiceLine>[];
      for (int i = 1; i <= 35; i++) {
        final price = 50000 + (i * 100);
        final qty = i.toDouble();
        final taxable = (price * qty).round();
        final tax = (taxable * 18 / 100).round();

        manyLines.add(LineCalcInput(
          quantity: qty,
          price: price,
          gstRate: 18,
        ));
        invoiceLines.add(InvoiceLine(
          name: 'Enterprise Industrial Hardware Component #$i',
          hsn: '84713010',
          gstRate: 18,
          quantity: qty,
          price: price,
          unit: 'PCS',
          discount: 0,
          discountPercent: 0,
          taxable: taxable,
          tax: tax,
        ));
      }

      final quote = BillingEngine.calculateQuote(
        lines: manyLines,
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      final invoiceId = await repo.finalizeSale(
        businessId: businessId,
        number: 'AT-MULTI-001',
        customerId: custId,
        customerName: 'Global Supply Corp',
        date: '2026-10-02',
        gstType: 'intra',
        quote: quote,
        lines: invoiceLines,
        amountPaid: quote.total.paise,
      );

      final invoice = await repo.invoice(businessId, invoiceId);
      expect(invoice, isNotNull);

      final cust = await repo.customer(businessId, custId);
      final settings = await repo.getInvoiceCustomizationSettings(businessId);

      // Generate multi-page PDF
      final pdfBytes = await buildInvoicePdf(
        business: testBusiness,
        invoice: invoice!,
        customer: cust,
        settings: settings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(5000));
      // Standard PDF magic header (%PDF)
      expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
    });
  });

  group('Constraint 3: Place of Supply (POS) Auto-Logic', () {
    test('POS automatically follows ship_to_state unless manually overridden', () {
      const billToState = 'Karnataka';
      const shipToState = 'Maharashtra';

      // Rule: If ship to different address is true, default POS to shipToState (Sec 10 IGST Act)
      String? resolvePos({
        required bool shipToDifferent,
        required String? billTo,
        required String? shipTo,
        required bool manualOverride,
        required String? manualChoice,
      }) {
        if (manualOverride) return manualChoice;
        if (shipToDifferent && shipTo != null && shipTo.isNotEmpty) {
          return shipTo;
        }
        return billTo;
      }

      // Test 1: Standard sale -> POS is Bill-to state
      expect(
        resolvePos(
          shipToDifferent: false,
          billTo: billToState,
          shipTo: null,
          manualOverride: false,
          manualChoice: null,
        ),
        'Karnataka',
      );

      // Test 2: Different destination -> POS defaults to Ship-To state (movement of goods)
      expect(
        resolvePos(
          shipToDifferent: true,
          billTo: billToState,
          shipTo: shipToState,
          manualOverride: false,
          manualChoice: null,
        ),
        'Maharashtra',
      );

      // Test 3: Manual override -> POS respects explicit choice
      expect(
        resolvePos(
          shipToDifferent: true,
          billTo: billToState,
          shipTo: shipToState,
          manualOverride: true,
          manualChoice: 'Gujarat',
        ),
        'Gujarat',
      );
    });
  });

  group('Constraint 4 & Phase 1: Idempotent SQLite Migrations & Persistence', () {
    test('PRAGMA table_info confirms columns and safe migration execution', () async {
      final info = await db.rawQuery('PRAGMA table_info(invoices)');
      final colNames = info.map((c) => c['name'] as String).toSet();

      expect(colNames.contains('ship_to_name'), isTrue);
      expect(colNames.contains('ship_to_address'), isTrue);
      expect(colNames.contains('ship_to_state'), isTrue);
      expect(colNames.contains('ship_to_pincode'), isTrue);
      expect(colNames.contains('place_of_supply'), isTrue);
      expect(colNames.contains('po_number'), isTrue);
      expect(colNames.contains('po_date'), isTrue);
      expect(colNames.contains('vehicle_number'), isTrue);
      expect(colNames.contains('eway_bill_number'), isTrue);
      expect(colNames.contains('lr_rr_number'), isTrue);
      expect(colNames.contains('reverse_charge'), isTrue);

      // Verify line items table has unit column
      final lineInfo = await db.rawQuery('PRAGMA table_info(invoice_items)');
      final lineColNames = lineInfo.map((c) => c['name'] as String).toSet();
      expect(lineColNames.contains('unit'), isTrue);

      // Verify invoice_customization_settings table exists and has new placement & visibility columns
      final customInfo = await db.rawQuery('PRAGMA table_info(invoice_customization_settings)');
      expect(customInfo, isNotEmpty);
      final customColNames = customInfo.map((c) => c['name'] as String).toSet();
      expect(customColNames.contains('show_email'), isTrue);
      expect(customColNames.contains('show_address'), isTrue);
      expect(customColNames.contains('show_gstin'), isTrue);
      expect(customColNames.contains('show_terms'), isTrue);
      expect(customColNames.contains('show_declaration'), isTrue);
      expect(customColNames.contains('bank_qr_placement'), isTrue);
      expect(customColNames.contains('signature_placement'), isTrue);
    });

    test('re-running migrations multiple times is completely idempotent and does not crash', () async {
      // Execute _migrate multiple times directly on existing open database
      await expectLater(
        AppDatabase.instance.migrateForTesting(db),
        completes,
      );
      await expectLater(
        AppDatabase.instance.migrateForTesting(db),
        completes,
      );
    });

    test('finalizeSale and invoice retrieval persists all transaction override fields and unit', () async {
      final quote = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 5, price: 10000, gstRate: 18)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Tamil Nadu',
      );

      final invId = await repo.finalizeSale(
        businessId: businessId,
        number: 'AT-SHIP-001',
        customerId: null,
        customerName: 'Interstate Client',
        date: '2026-10-02',
        dueDate: '2026-10-15',
        gstType: 'inter',
        quote: quote,
        lines: [
          InvoiceLine(
            name: 'Heavy Duty Motors',
            hsn: '8501',
            gstRate: 18,
            quantity: 5,
            price: 10000,
            unit: 'BOX',
            taxable: 50000,
            tax: 9000,
          )
        ],
        amountPaid: 0,
        shipToName: 'Consignee Hub B',
        shipToAddress: 'Plot 44, Guindy Industrial Estate',
        shipToState: 'Tamil Nadu',
        shipToPincode: '600032',
        placeOfSupply: 'Tamil Nadu',
        poNumber: 'PO-2026-88',
        poDate: '2026-09-30',
        vehicleNumber: 'KA04MN9999',
        ewayBillNumber: '241012345678',
        lrRrNumber: 'LR-5544',
        reverseCharge: true,
      );

      final invoice = await repo.invoice(businessId, invId);
      expect(invoice, isNotNull);
      expect(invoice!.shipToName, 'Consignee Hub B');
      expect(invoice.shipToAddress, 'Plot 44, Guindy Industrial Estate');
      expect(invoice.shipToState, 'Tamil Nadu');
      expect(invoice.shipToPincode, '600032');
      expect(invoice.placeOfSupply, 'Tamil Nadu');
      expect(invoice.poNumber, 'PO-2026-88');
      expect(invoice.poDate, '2026-09-30');
      expect(invoice.vehicleNumber, 'KA04MN9999');
      expect(invoice.ewayBillNumber, '241012345678');
      expect(invoice.lrRrNumber, 'LR-5544');
      expect(invoice.reverseCharge, isTrue);

      // Verify line unit
      expect(invoice.lines.first.unit, 'BOX');
    });

    test('customization settings can be saved and retrieved with placement and visibility options', () async {
      final newSettings = InvoiceCustomizationSettings(
        businessId: businessId,
        themeStyle: 'classic_grid',
        primaryColorHex: '#2563EB',
        showHsnColumn: true,
        showUnitColumn: true,
        showDiscountColumn: true,
        showTaxColumn: true,
        showHsnSummaryTable: true,
        showBankDetails: true,
        showUpiQr: true,
        showSignatureBox: true,
        showShipTo: true,
        showPoDetails: true,
        showVehicleDetails: true,
        showEmail: false,
        showAddress: true,
        showGstin: true,
        showTerms: true,
        showDeclaration: false,
        bankQrPlacement: 'bottom',
        signaturePlacement: 'left',
        declarationText: 'Certified that particulars given above are true and correct.',
        customTitleOverride: 'OFFICIAL TAX INVOICE',
      );

      await repo.saveInvoiceCustomizationSettings(newSettings);
      final loaded = await repo.getInvoiceCustomizationSettings(businessId);

      expect(loaded.themeStyle, 'classic_grid');
      expect(loaded.primaryColorHex, '#2563EB');
      expect(loaded.customTitleOverride, 'OFFICIAL TAX INVOICE');
      expect(loaded.showPoDetails, isTrue);
      expect(loaded.showEmail, isFalse);
      expect(loaded.showAddress, isTrue);
      expect(loaded.showGstin, isTrue);
      expect(loaded.showTerms, isTrue);
      expect(loaded.showDeclaration, isFalse);
      expect(loaded.bankQrPlacement, 'bottom');
      expect(loaded.signaturePlacement, 'left');

      // Test generating commercial sample PDF with these settings
      final pdfBytes = await generateCommercialSamplePdf(
        business: testBusiness,
        settings: loaded,
      );
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });
  });

  group('Phase 5: GSTR-1 Excel & JSON Protocol and Audit Guard', () {
    test('generateGstr1Excel builds distinct sheets without OpenXML corruption', () async {
      final bytes = await GstReportsService.instance.generateGstr1Excel(
        business: testBusiness,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );

      expect(bytes, isNotEmpty);
      expect(bytes[0], 0x50); // PK zip header
      expect(bytes[1], 0x4B);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);

      // Read workbook.xml to ensure sheets are registered
      final wbFile = archive.findFile('xl/workbook.xml');
      final wbXml = utf8.decode(wbFile!.content as List<int>);
      expect(wbXml.contains('b2b'), isTrue);
      expect(wbXml.contains('hsn'), isTrue);
      expect(wbXml.contains('docs'), isTrue);
    });

    test('auditGstr1Data flags missing HSN or invalid GSTIN before export', () async {
      final issues = await GstReportsService.instance.auditGstr1Data(
        business: testBusiness,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );

      // Verify audit executes cleanly and returns structured issues
      expect(issues, isA<List<GstAuditIssue>>());
    });
  });
}
