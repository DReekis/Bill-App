import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);
    businessId = await repo.createBusiness(Business(
      name: 'Alpha Traders',
      state: 'Maharashtra',
      taxRegistered: true,
      invoicePrefix: 'INV',
      quotationPrefix: 'EST',
      purchasePrefix: 'PUR',
      invoicePhone: '9876543210',
      invoiceEmail: 'billing@alphatraders.com',
      termsSales: '1. Goods once sold will not be taken back.',
      termsQuotation: '1. Estimate valid for 15 days.',
      termsPurchase: '1. Subject to quality inspection.',
      signatureText: 'For Alpha Traders, Authorised Signatory',
      showEmptySignatureBox: true,
      showPaymentQr: true,
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  test('Business model persists and loads all invoice settings properly', () async {
    final biz = await repo.getBusiness(businessId);
    expect(biz, isNotNull);
    expect(biz!.invoicePhone, '9876543210');
    expect(biz.invoiceEmail, 'billing@alphatraders.com');
    expect(biz.displayInvoicePhone, '9876543210');
    expect(biz.displayInvoiceEmail, 'billing@alphatraders.com');
    expect(biz.termsSales, contains('Goods once sold'));
    expect(biz.termsQuotation, contains('valid for 15 days'));
    expect(biz.termsPurchase, contains('quality inspection'));
    expect(biz.signatureText, contains('Alpha Traders'));
    expect(biz.showEmptySignatureBox, isTrue);
    expect(biz.showPaymentQr, isTrue);
    expect(biz.quotationPrefix, 'EST');
    expect(biz.purchasePrefix, 'PUR');
  });

  test('peek and next sequential number generation for invoices, estimates, and purchases', () async {
    // 1. Peek next invoice number without incrementing
    final peek1 = await repo.peekNextInvoiceNumber(businessId, 'INV');
    expect(peek1, 'INV-0001');
    final peek2 = await repo.peekNextInvoiceNumber(businessId, 'INV');
    expect(peek2, 'INV-0001'); // Same because sequence wasn't incremented

    // 2. Consume next invoice number
    final inv1 = await repo.nextInvoiceNumber(businessId, 'INV');
    expect(inv1, 'INV-0001');
    final inv2 = await repo.nextInvoiceNumber(businessId, 'INV');
    expect(inv2, 'INV-0002');

    // 3. Peek and consume quotation numbers
    final qPeek = await repo.peekNextQuotationNumber(businessId, 'EST');
    expect(qPeek, 'EST-0001');
    final q1 = await repo.nextQuotationNumber(businessId, 'EST');
    expect(q1, 'EST-0001');
    final q2 = await repo.nextQuotationNumber(businessId, 'EST');
    expect(q2, 'EST-0002');

    // 4. Peek and consume purchase numbers
    final pPeek = await repo.peekNextPurchaseNumber(businessId, 'PUR');
    expect(pPeek, 'PUR-0001');
    final p1 = await repo.nextPurchaseNumber(businessId, 'PUR');
    expect(p1, 'PUR-0001');
    final p2 = await repo.nextPurchaseNumber(businessId, 'PUR');
    expect(p2, 'PUR-0002');
  });

  test('isInvoiceNumberAvailable detects existing vs available numbers', () async {
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-999'), isTrue);

    // Save an invoice with number 'BILL-999'
    await db.insert('invoices', {
      'business_id': businessId,
      'number': 'BILL-999',
      'date': '2026-09-24',
      'total': 1000,
    });

    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-999'), isFalse);
    expect(await repo.isInvoiceNumberAvailable(businessId, 'bill-999'), isFalse); // Case-insensitive
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-1000'), isTrue);
  });

  test('peekNextInvoiceNumber detects existing invoices in database and avoids duplicate numbers', () async {
    // Suppose businesses table has sequence = 3, but INV-0004 already exists in DB
    await db.update('businesses', {'invoice_sequence': 3}, where: 'id = ?', whereArgs: [businessId]);
    await db.insert('invoices', {
      'business_id': businessId,
      'number': 'INV-0004',
      'date': '2026-09-28',
      'total': 250000,
    });

    // Peeking must NOT return INV-0004 because it already exists; it must return INV-0005!
    final peek = await repo.peekNextInvoiceNumber(businessId, 'INV');
    expect(peek, 'INV-0005');

    // nextInvoiceNumber must return INV-0005 and update sequence to 5
    final next = await repo.nextInvoiceNumber(businessId, 'INV');
    expect(next, 'INV-0005');

    final biz = await repo.getBusiness(businessId);
    expect(biz!.invoiceSequence, 5);
  });

  test('finalizeSale automatically advances invoice_sequence so subsequent sales never collide', () async {
    final quote = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(quantity: 1, price: 10000, gstRate: 18),
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: false,
    );

    // Finalize sale with number 'INV-0010'
    await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-0010',
      customerId: null,
      customerName: 'Test Customer',
      date: '2026-09-28',
      gstType: 'regular',
      quote: quote,
      lines: [
        InvoiceLine(name: 'Widget', gstRate: 18, quantity: 1, price: 10000),
      ],
      amountPaid: 11800,
    );

    // Sequence in businesses table should now be at least 10
    final biz = await repo.getBusiness(businessId);
    expect(biz!.invoiceSequence, greaterThanOrEqualTo(10));

    // Next peek must automatically be INV-0011!
    final nextNum = await repo.peekNextInvoiceNumber(businessId, 'INV');
    expect(nextNum, 'INV-0011');
  });

  test('createPurchase automatically advances purchase_sequence and avoids collisions', () async {
    await repo.createPurchase(
      businessId: businessId,
      supplierId: null,
      supplierName: 'Vendor ABC',
      date: '2026-09-28',
      items: [
        (null, 'Raw Material', 10.0, 5000, 18),
      ],
      amountPaid: 59000,
      purchaseNumber: 'PUR-0005',
    );

    final biz = await repo.getBusiness(businessId);
    expect(biz!.purchaseSequence, greaterThanOrEqualTo(5));

    final nextPurch = await repo.peekNextPurchaseNumber(businessId, 'PUR');
    expect(nextPurch, 'PUR-0006');
  });
}
