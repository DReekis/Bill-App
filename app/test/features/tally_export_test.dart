import 'dart:io';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/reports/tally_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('TallyExportService Unit Tests', () {
    test('xmlEscape properly escapes special XML characters', () {
      expect(
        TallyExportService.xmlEscape('A & B < C > D "quote" \'apostrophe\''),
        'A &amp; B &lt; C &gt; D &quot;quote&quot; &apos;apostrophe&apos;',
      );
    });

    test('formatTallyDate converts ISO dates to YYYYMMDD', () {
      expect(TallyExportService.formatTallyDate('2026-04-15'), '20260415');
      expect(TallyExportService.formatTallyDate('2026-12-31T14:30:00'), '20261231');
      expect(TallyExportService.formatTallyDate(''), '');
    });

    test('formatRupees converts paise to 2-decimal rupee strings', () {
      expect(TallyExportService.formatRupees(100000), '1000.00');
      expect(TallyExportService.formatRupees(9950), '99.50');
      expect(TallyExportService.formatRupees(0), '0.00');
    });

    test('exportTallyXml produces compliant Tally XML envelope with Masters & Vouchers', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: AppDatabase.instance.createSchema,
        ),
      );
      AppDatabase.instance.useDatabaseForTesting(db);

      final repo = Repository.instance;
      final bizId = await repo.createBusiness(Business(
        name: 'Alpha Traders & Co.',
        state: 'Maharashtra',
        gstin: '27AABCT1234F1Z5',
        taxRegistered: true,
      ));
      repo.session.businessId = bizId;
      Session().businessId = bizId;

      // Create Customer & Supplier
      final custId = await repo.upsertCustomer(Customer(
        name: 'Shree Krishna Mart',
        state: 'Maharashtra',
        gstin: '27ABCDE5678G1Z9',
      ));
      await repo.upsertSupplier(Supplier(
        name: 'Om Enterprises',
        state: 'Maharashtra',
        gstin: '27XYZAB9999K1Z2',
      ));

      // Create Product & Sale Invoice
      final prodId = await repo.upsertProduct(Product(
        name: 'Wireless Mouse',
        salePrice: 50000,
        purchasePrice: 30000,
        gstRate: 18,
        stock: 10,
      ));

      final quote = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(
            quantity: 2,
            price: 50000, // 500.00 * 2 = 1000.00
            gstRate: 18,
            taxIncluded: false,
          ),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Maharashtra',
        customerState: 'Maharashtra',
      );

      final invoiceId = await repo.finalizeSale(
        businessId: bizId,
        number: 'INV-TEST-001',
        customerId: custId,
        customerName: 'Shree Krishna Mart',
        date: '2026-04-15',
        dueDate: '2026-04-30',
        gstType: 'intra',
        quote: quote,
        lines: [
          InvoiceLine(
            productId: prodId,
            name: 'Wireless Mouse',
            gstRate: 18,
            quantity: 2,
            price: 50000,
            taxable: 100000,
            tax: 18000,
          ),
        ],
        amountPaid: 0,
      );

      // Create Receipt
      await repo.recordPayment(
        businessId: bizId,
        partyType: 'customer',
        partyId: custId,
        partyName: 'Shree Krishna Mart',
        amount: 50000,
        mode: 'Cash',
        date: '2026-04-16',
        invoiceIds: [invoiceId],
      );

      // Export Tally XML
      final result = await TallyExportService.instance.exportTallyXml(
        businessId: bizId,
        outputDir: Directory.systemTemp,
      );

      // Verifications
      expect(result.salesCount, 1);
      expect(result.receiptCount, 1);
      expect(result.ledgerCount, greaterThanOrEqualTo(10));
      expect(result.totalVouchers, 2);

      final xml = result.xml;
      // Envelope checks
      expect(xml, contains('<ENVELOPE>'));
      expect(xml, contains('<TALLYREQUEST>Import Data</TALLYREQUEST>'));
      expect(xml, contains('<REPORTNAME>All Masters</REPORTNAME>'));
      expect(xml, contains('<SVCURRENTCOMPANY>Alpha Traders &amp; Co.</SVCURRENTCOMPANY>'));

      // Ledger checks
      expect(xml, contains('<LEDGER NAME="Shree Krishna Mart" ACTION="Create">'));
      expect(xml, contains('<PARENT>Sundry Debtors</PARENT>'));
      expect(xml, contains('<PARTYGSTIN>27ABCDE5678G1Z9</PARTYGSTIN>'));
      expect(xml, contains('<LEDGER NAME="Om Enterprises" ACTION="Create">'));
      expect(xml, contains('<PARENT>Sundry Creditors</PARENT>'));
      expect(xml, contains('<LEDGER NAME="Sales Account" ACTION="Create">'));
      expect(xml, contains('<LEDGER NAME="CGST" ACTION="Create">'));
      expect(xml, contains('<LEDGER NAME="SGST" ACTION="Create">'));

      // Voucher checks
      expect(xml, contains('<VOUCHER VCHTYPE="Sales" ACTION="Create" OBJVIEW="Invoice Voucher View">'));
      expect(xml, contains('<VOUCHERNUMBER>INV-TEST-001</VOUCHERNUMBER>'));
      expect(xml, contains('<DATE>20260415</DATE>'));
      expect(xml, contains('<PARTYLEDGERNAME>Shree Krishna Mart</PARTYLEDGERNAME>'));
      expect(xml, contains('<STOCKITEMNAME>Wireless Mouse</STOCKITEMNAME>'));

      // Receipt checks
      expect(xml, contains('<VOUCHER VCHTYPE="Receipt" ACTION="Create">'));
      expect(xml, contains('<DATE>20260416</DATE>'));
      expect(xml, contains('<LEDGERNAME>Cash</LEDGERNAME>'));

      // File exists and is non-empty
      expect(await result.file.exists(), isTrue);
      expect(await result.file.length(), greaterThan(500));

      await db.close();
    });
  });
}
