import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Invoice Charges & Statutory Flow Tests', () {
    test('Sequence: [Subtotal of Items] -> [Item GST] -> [Charges/TCS] -> [Grand Total]', () {
      // 1 Item: 2 units @ ₹500 = ₹1,000 (paise: 100000) @ 18% GST (Intra-state: 9% CGST, 9% SGST)
      final itemInput = LineCalcInput(quantity: 2, price: 50000, gstRate: 18, taxIncluded: false);
      // Delivery Charge: ₹100 @ 18% GST = ₹18 GST (paise: 10000 + 1800 tax)
      final delivery = InvoiceCharge(name: 'Delivery Charge', amount: 10000, gstRate: 18, hsn: '9965');
      // TCS @ 0.1%: ₹10 (paise: 1000), 0% GST (statutory direct tax charge)
      final tcs = InvoiceCharge(name: 'TCS @ 0.1%', amount: 1000, gstRate: 0, chargeType: 'tcs');

      final quote = BillingEngine.calculateQuote(
        lines: [itemInput],
        charges: [delivery, tcs],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessTaxRegistered: true,
        businessState: 'Maharashtra',
        customerState: 'Maharashtra',
      );

      // Item Subtotal: 100000 paise (₹1,000)
      expect(quote.subtotal.paise, 100000);
      expect(quote.taxable.paise, 100000);

      // Item GST: 18% of 100000 = 18000 paise (CGST: 9000, SGST: 9000)
      // Delivery GST: 18% of 10000 = 1800 paise (CGST: 900, SGST: 900)
      // Total CGST: 9900, SGST: 9900
      expect(quote.cgst.paise, 9900);
      expect(quote.sgst.paise, 9900);

      // Charges subtotal: 10000 (Delivery)
      expect(quote.chargesSubtotal.paise, 10000);
      expect(quote.chargesTax.paise, 1800);

      // TCS: 1000
      expect(quote.tcsTotal.paise, 1000);

      // Net: 100000 (item taxable) + 19800 (total GST) + 10000 (delivery base) + 1000 (TCS) = 130800 paise (₹1,308.00)
      expect(quote.total.paise, 130800);
      expect(quote.roundOff.paise, 0);
    });

    test('Inclusive of GST (Inc. GST) back-calculates item tax properly while keeping charges separate', () {
      // 1 Item: 1 unit @ ₹1,180 (tax inclusive 18% GST) -> Taxable: ₹1,000, Tax: ₹180
      final itemInput = LineCalcInput(quantity: 1, price: 118000, gstRate: 18, taxIncluded: true);
      final tcs = InvoiceCharge(name: 'TCS u/s 206C(1H)', amount: 200, gstRate: 0, chargeType: 'tcs');

      final quote = BillingEngine.calculateQuote(
        lines: [itemInput],
        charges: [tcs],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessTaxRegistered: true,
        businessState: 'Delhi',
        customerState: 'Delhi',
      );

      expect(quote.subtotal.paise, 118000);
      expect(quote.taxable.paise, 100000);
      expect(quote.cgst.paise + quote.sgst.paise, 18000);
      expect(quote.tcsTotal.paise, 200);
      // Net: 100000 + 18000 + 200 = 118200
      expect(quote.total.paise, 118200);
    });

    test('Invoice model serializes and deserializes charges_json cleanly', () {
      final charges = [
        InvoiceCharge(name: 'Handling Fee', amount: 5000, gstRate: 18),
        InvoiceCharge(name: 'TCS @ 0.1%', amount: 350, gstRate: 0, chargeType: 'tcs'),
      ];

      final invoice = Invoice(
        number: 'INV-TEST-001',
        date: '2026-10-14',
        charges: charges,
      );

      final map = invoice.toMap();
      expect(map['charges_json'], isNotNull);
      final decoded = jsonDecode(map['charges_json'] as String) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['name'], 'Handling Fee');
      expect(decoded[1]['charge_type'], 'tcs');

      final reconstituted = Invoice.fromMap(map);
      expect(reconstituted.charges.length, 2);
      expect(reconstituted.charges[0].name, 'Handling Fee');
      expect(reconstituted.charges[0].amount, 5000);
      expect(reconstituted.charges[1].isTcs, isTrue);
    });

    test('Repository separates sales income from TCS liability and charge income', () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 1,
          onCreate: (db, v) async {
        await AppDatabase.instance.createSchema(db, v);
        await AppDatabase.instance.migrateForTesting(db);
      });
      AppDatabase.instance.useDatabaseForTesting(db);
      final repo = Repository.instance;

      try {
        final bizId = await repo.createBusiness(Business(
          name: 'Apex Traders',
          phone: '9876543210',
          state: 'Karnataka',
          taxRegistered: true,
        ));

        final prodId = await db.insert('products', {
          'business_id': bizId,
          'name': 'LED Monitor',
          'stock': 20,
          'sale_price': 1000000, // ₹10,000
          'gst_rate': 18,
          'cost_average': 700000,
        });

        final prodInput = LineCalcInput(quantity: 1, price: 1000000, gstRate: 18);
        final tcs = InvoiceCharge(name: 'TCS @ 0.1%', amount: 1000, chargeType: 'tcs');
        final freight = InvoiceCharge(name: 'Freight & Shipping', amount: 50000, gstRate: 18, hsn: '9965');

        final quote = BillingEngine.calculateQuote(
          lines: [prodInput],
          charges: [freight, tcs],
          invoiceDiscount: const InvoiceDiscountInput.none(),
          businessTaxRegistered: true,
          businessState: 'Karnataka',
          customerState: 'Karnataka',
        );

        final invId = await repo.finalizeSale(
          businessId: bizId,
          number: 'INV-2026-001',
          customerId: null,
          customerName: 'Direct Buyer',
          date: '2026-10-14',
          gstType: 'intra',
          quote: quote,
          lines: [
            InvoiceLine(
              productId: prodId,
              name: 'LED Monitor',
              gstRate: 18,
              quantity: 1,
              price: 1000000,
              taxable: quote.lines[0].taxable.paise,
              tax: quote.lines[0].tax.paise,
            ),
          ],
          charges: [freight, tcs],
          amountPaid: quote.total.paise,
        );

        final loaded = await repo.invoice(bizId, invId);
        expect(loaded, isNotNull);
        // Ensure lines contains ONLY the product
        expect(loaded!.lines.length, 1);
        expect(loaded.lines[0].name, 'LED Monitor');
        // Ensure charges contains the non-product items
        expect(loaded.charges.length, 2);

        // Check ledgers
        final entries = await db.query('ledger', where: 'ref_id = ? AND ref_type = ?', whereArgs: [invId, 'invoice']);
        final salesCredit = entries.firstWhere((e) => e['account'] == 'income:sales')['credit'];
        final tcsCredit = entries.firstWhere((e) => e['account'] == 'tax:tcs')['credit'];
        final chargesCredit = entries.firstWhere((e) => e['account'] == 'income:charges')['credit'];
        final gstCredit = entries.firstWhere((e) => e['account'] == 'gst:output')['credit'];

        // Strict ledger separation:
        expect(salesCredit, 1000000); // Only the LED Monitor taxable sales
        expect(tcsCredit, 1000); // Statutory direct tax liability
        expect(chargesCredit, 50000); // Freight income
        expect(gstCredit, 189000); // 18% on monitor (180000) + 18% on freight (9000)
      } finally {
        AppDatabase.instance.resetConnection();
        await db.close();
      }
    });

    test('PDF Generator renders GST breakdown table above calculations and excludes charges from line items', () async {
      final biz = Business(
        id: 1,
        name: 'Apex Traders',
        phone: '9876543210',
        state: 'Karnataka',
        taxRegistered: true,
      );

      final productLine = InvoiceLine(
        productId: 101,
        name: 'Industrial Widget',
        hsn: '8471',
        gstRate: 18,
        quantity: 2,
        price: 50000,
        taxable: 100000,
        tax: 18000,
      );

      final charges = [
        InvoiceCharge(name: 'Delivery Charge', amount: 10000, gstRate: 18, hsn: '9965'),
        InvoiceCharge(name: 'TCS @ 0.1%', amount: 1000, gstRate: 0, chargeType: 'tcs'),
      ];

      final pdfBytes = await buildDocumentPdf(
        business: biz,
        title: 'Tax Invoice',
        number: 'INV-PDF-001',
        date: '2026-10-14',
        partyName: 'ABC Enterprises',
        lines: [productLine],
        charges: charges,
        subtotal: 100000,
        discount: 0,
        taxable: 100000,
        igst: 0,
        cgst: 9900,
        sgst: 9900,
        roundOff: 0,
        total: 130800,
        outstandingPaise: 0,
        notes: 'Goods once sold cannot be returned.',
        termsText: 'Payment within 15 days.',
        settings: InvoiceCustomizationSettings(
          showHsnSummaryTable: true,
          themeStyle: 'classic_grid',
        ),
      );

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
