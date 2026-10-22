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
      name: 'Test Tech Hub',
      state: 'Karnataka',
      taxRegistered: true,
      invoicePrefix: 'INV-',
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addProduct({
    String name = 'Laptop Stand',
    String sku = 'LS-1',
    int gstRate = 18,
    int salePrice = 100000, // ₹1,000.00
    int purchasePrice = 60000, // ₹600.00
    int stock = 50,
  }) =>
      repo.upsertProduct(
        Product(
          name: name,
          sku: sku,
          gstRate: gstRate,
          salePrice: salePrice,
          purchasePrice: purchasePrice,
          costAverage: purchasePrice,
          stock: stock,
        ),
        businessIdOverride: businessId,
      );

  Future<double> getStock(int prodId) async {
    final rows = await db.query('products', where: 'id = ?', whereArgs: [prodId], limit: 1);
    return (rows.first['stock'] as num).toDouble();
  }

  test('updateSale retroactively edits invoice items, numbers, dates and reconciles inventory stock', () async {
    final p1Id = await addProduct(name: 'Item A', sku: 'A-1', salePrice: 100000, stock: 50);
    final p2Id = await addProduct(name: 'Item B', sku: 'B-1', salePrice: 200000, stock: 30);
    final custId = await repo.upsertCustomer(
      Customer(name: 'Alpha Traders', state: 'Karnataka'),
      businessIdOverride: businessId,
    );

    // 1. Create initial sale: 5 of Item A
    final quote1 = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(quantity: 5, price: 100000, gstRate: 18),
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      gstEnabled: true,
      businessTaxRegistered: true,
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );

    final invId = await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-0001',
      customerId: custId,
      customerName: 'Alpha Traders',
      date: '2026-09-01',
      dueDate: '2026-09-15',
      gstType: 'intra',
      quote: quote1,
      lines: [
        InvoiceLine(
          productId: p1Id,
          name: 'Item A',
          gstRate: 18,
          quantity: 5,
          price: 100000,
          taxable: quote1.lines[0].taxable.paise,
          tax: quote1.lines[0].tax.paise,
        ),
      ],
      amountPaid: 0,
    );

    // Verify stock deduction for Item A (50 - 5 = 45)
    expect(await getStock(p1Id), 45.0);

    // 2. Retroactively update invoice:
    // Change number to 'INV-0001-REV', date to '2026-09-05'
    // Change quantity of Item A from 5 to 2
    // Add 3 of Item B
    // Add TCS charge (productId == null)
    // Pay ₹2,000 partial payment
    final quote2 = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(quantity: 2, price: 100000, gstRate: 18), // 2 * 1000 = 2000
        LineCalcInput(quantity: 3, price: 200000, gstRate: 18), // 3 * 2000 = 6000
        LineCalcInput(quantity: 1, price: 5000, gstRate: 0), // TCS ₹50 @ 0%
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      gstEnabled: true,
      businessTaxRegistered: true,
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );

    await repo.updateSale(
      businessId: businessId,
      invoiceId: invId,
      number: 'INV-0001-REV',
      customerId: custId,
      customerName: 'Alpha Traders',
      date: '2026-09-05',
      dueDate: '2026-09-20',
      gstType: 'intra',
      quote: quote2,
      lines: [
        InvoiceLine(
          productId: p1Id,
          name: 'Item A',
          gstRate: 18,
          quantity: 2,
          price: 100000,
          taxable: quote2.lines[0].taxable.paise,
          tax: quote2.lines[0].tax.paise,
        ),
        InvoiceLine(
          productId: p2Id,
          name: 'Item B',
          gstRate: 18,
          quantity: 3,
          price: 200000,
          taxable: quote2.lines[1].taxable.paise,
          tax: quote2.lines[1].tax.paise,
        ),
        InvoiceLine(
          productId: null,
          name: 'TCS @ 0.1%',
          gstRate: 0,
          quantity: 1,
          price: 5000,
          taxable: quote2.lines[2].taxable.paise,
          tax: quote2.lines[2].tax.paise,
        ),
      ],
      paymentMode: 'Bank Transfer',
      notes: 'Updated order terms',
      amountPaid: 200000, // ₹2,000 paid
    );

    // 3. Verify invoice record updated
    final updatedInv = await repo.invoice(businessId, invId);
    expect(updatedInv, isNotNull);
    expect(updatedInv!.number, 'INV-0001-REV');
    expect(updatedInv.date, '2026-09-05');
    expect(updatedInv.dueDate, '2026-09-20');
    expect(updatedInv.amountPaid, 200000);
    expect(updatedInv.status, 'Partially paid');
    expect(updatedInv.notes, 'Updated order terms');
    expect(updatedInv.lines.length, 3);

    // 4. Verify inventory stocks:
    // Item A was 50, originally 5 deducted (45). Restored 5 (50), now 2 deducted -> 48
    expect(await getStock(p1Id), 48.0);

    // Item B was 30, now 3 deducted -> 27
    expect(await getStock(p2Id), 27.0);

    // 5. Verify ledger integrity:
    final ledgerEntries = await db.query('ledger',
        where: 'ref_type = ? AND ref_id = ?', whereArgs: ['invoice', invId]);
    expect(ledgerEntries.isNotEmpty, true);

    // All ledger entries for this invoice must balance (sum of debits == sum of credits)
    var totalDebits = 0;
    var totalCredits = 0;
    for (final row in ledgerEntries) {
      if (row['account'] == 'cogs') continue;
      totalDebits += row['debit'] as int;
      totalCredits += row['credit'] as int;
    }
    expect(totalDebits, totalCredits);
  });

  test('isInvoiceNumberAvailable allows keeping current number when editing', () async {
    final quote = BillingEngine.calculateQuote(
      lines: [],
      invoiceDiscount: const InvoiceDiscountInput.none(),
    );
    await repo.finalizeSale(
      businessId: businessId,
      number: 'BILL-100',
      customerId: null,
      customerName: 'Direct',
      date: '2026-09-01',
      gstType: 'intra',
      quote: quote,
      lines: [],
      amountPaid: 0,
    );

    final invId2 = await repo.finalizeSale(
      businessId: businessId,
      number: 'BILL-200',
      customerId: null,
      customerName: 'Direct',
      date: '2026-09-01',
      gstType: 'intra',
      quote: quote,
      lines: [],
      amountPaid: 0,
    );

    // Checking BILL-100 without exclude: taken
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-100'), false);

    // Checking BILL-200 excluding invId2: available (self)
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-200', excludeInvoiceId: invId2), true);

    // Checking BILL-100 excluding invId2: still taken by invoice 1
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-100', excludeInvoiceId: invId2), false);

    // Brand new number is available
    expect(await repo.isInvoiceNumberAvailable(businessId, 'BILL-300'), true);
  });

  test('recentTransactions reflects partially received amount on invoice and records payment in', () async {
    final prodId = await addProduct(name: 'Office Chair', sku: 'OC-1', salePrice: 100000, stock: 20);
    final custId = await repo.upsertCustomer(Customer(name: 'Beta Corp', state: 'Karnataka'), businessIdOverride: businessId);

    // 1. Create invoice of ₹1,000 + 18% GST = ₹1,180
    final quote = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: 1, price: 100000, gstRate: 18)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: true,
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );

    final invId = await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-PARTIAL-1',
      customerId: custId,
      customerName: 'Beta Corp',
      date: '2026-09-10',
      gstType: 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: prodId,
          name: 'Office Chair',
          gstRate: 18,
          quantity: 1,
          price: 100000,
          taxable: quote.lines[0].taxable.paise,
          tax: quote.lines[0].tax.paise,
        ),
      ],
      amountPaid: 0,
    );

    // Initial check: invoice is unpaid in recentTransactions
    var txs = await repo.recentTransactions(businessId);
    var saleTx = txs.firstWhere((t) => t.type == TransactionType.sale && t.number == 'INV-PARTIAL-1');
    expect(saleTx.amount, 118000);
    expect(saleTx.paidAmount, 0);
    expect(saleTx.outstandingAmount, 118000);
    expect(saleTx.status, 'Unpaid');

    // 2. Register partially received payment of ₹400 (40000 paise)
    await repo.recordPayment(
      businessId: businessId,
      partyType: 'customer',
      partyId: custId,
      partyName: 'Beta Corp',
      amount: 40000,
      date: '2026-09-11',
      mode: 'Cash',
      invoiceIds: [invId],
    );

    // Check after partial payment:
    // - Sale transaction reflects paidAmount: 40000, outstandingAmount: 78000, status: 'Partially paid'
    // - Payment In transaction is recorded with amount: 40000 and linked to invoice
    txs = await repo.recentTransactions(businessId);
    saleTx = txs.firstWhere((t) => t.type == TransactionType.sale && t.number == 'INV-PARTIAL-1');
    expect(saleTx.amount, 118000);
    expect(saleTx.paidAmount, 40000);
    expect(saleTx.outstandingAmount, 78000);
    expect(saleTx.status, 'Partially paid');

    final payTx = txs.firstWhere((t) => t.type == TransactionType.paymentIn && t.refId == invId);
    expect(payTx.amount, 40000);
    expect(payTx.number, contains('INV-PARTIAL-1'));
    expect(payTx.partyName, 'Beta Corp');
  });

  test('adding charge and TCS calculates real-time quote, separates ledgers, and persists correctly', () async {
    final prodId = await addProduct(name: 'Gadget', sku: 'G-1', salePrice: 50000, stock: 10);

    // 1. Initial product: ₹500 @ 18% GST
    // 2. Add Delivery Charge: ₹100 @ 18% GST (non-TCS charge)
    // 3. Add TCS charge: ₹5 (tax liability)
    final prodInput = LineCalcInput(quantity: 1, price: 50000, gstRate: 18);
    final deliveryCharge = InvoiceCharge(name: 'Delivery / Shipping', amount: 10000, gstRate: 18, hsn: '9965');
    final tcsCharge = InvoiceCharge(name: 'TCS @ 0.1%', amount: 500, gstRate: 0, chargeType: 'tcs');

    final quoteWithCharges = BillingEngine.calculateQuote(
      lines: [prodInput],
      charges: [deliveryCharge, tcsCharge],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: true,
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );

    // Pure item taxable = 50000. Total tax = 9000 (item) + 1800 (delivery) = 10800.
    // Charges subtotal = 10000. TCS = 500. Total = 50000 + 10800 + 10000 + 500 = 71300.
    expect(quoteWithCharges.taxable.paise, 50000);
    expect(quoteWithCharges.cgst.paise + quoteWithCharges.sgst.paise, 10800);
    expect(quoteWithCharges.chargesSubtotal.paise, 10000);
    expect(quoteWithCharges.tcsTotal.paise, 500);
    expect(quoteWithCharges.total.paise, 71300);

    final invId = await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-CHARGE-1',
      customerId: null,
      customerName: 'Direct',
      date: '2026-09-12',
      gstType: 'intra',
      quote: quoteWithCharges,
      lines: [
        InvoiceLine(
          productId: prodId,
          name: 'Gadget',
          gstRate: 18,
          quantity: 1,
          price: 50000,
          taxable: quoteWithCharges.lines[0].taxable.paise,
          tax: quoteWithCharges.lines[0].tax.paise,
        ),
      ],
      charges: [deliveryCharge, tcsCharge],
      amountPaid: 71300,
    );

    final inv = await repo.invoice(businessId, invId);
    expect(inv, isNotNull);
    // Product items array has ONLY the physical product!
    expect(inv!.lines.length, 1);
    expect(inv.lines[0].productId, prodId);
    expect(inv.lines[0].name, 'Gadget');

    // Dedicated charges array has both charges!
    expect(inv.charges.length, 2);
    expect(inv.charges[0].name, 'Delivery / Shipping');
    expect(inv.charges[0].amount, 10000);
    expect(inv.charges[1].name, 'TCS @ 0.1%');
    expect(inv.charges[1].amount, 500);
    expect(inv.charges[1].isTcs, isTrue);
    expect(inv.total, 71300);

    // Verify double-entry ledger postings:
    final ledgerEntries = await db.query('ledger', where: 'ref_id = ? AND ref_type = ?', whereArgs: [invId, 'invoice']);
    final salesEntry = ledgerEntries.firstWhere((e) => e['account'] == 'income:sales');
    final gstEntry = ledgerEntries.firstWhere((e) => e['account'] == 'gst:output');
    final tcsEntry = ledgerEntries.firstWhere((e) => e['account'] == 'tax:tcs');
    final chargeEntry = ledgerEntries.firstWhere((e) => e['account'] == 'income:charges');

    // Sales revenue must ONLY reflect product taxable (50000 paise), NOT contaminated by charges or TCS!
    expect(salesEntry['credit'], 50000);
    expect(gstEntry['credit'], 10800);
    expect(tcsEntry['credit'], 500);
    expect(chargeEntry['credit'], 10000);
  });
}
