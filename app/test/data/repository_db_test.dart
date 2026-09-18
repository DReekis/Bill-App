// Drives the real Repository against an in-memory copy of the real schema.
// This is the check that catches SQL/schema drift: a column that does not exist,
// an ambiguous column in a JOIN, or a ledger sign flipped the wrong way.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/data/seed_data.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 1, onCreate: AppDatabase.instance.createSchema),
    );
    AppDatabase.instance.useDatabaseForTesting(db);
    businessId = await repo.createBusiness(Business(
      name: 'Test Store',
      state: 'Karnataka',
      taxRegistered: true,
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addProduct({
    String name = 'Widget',
    String sku = 'W-1',
    int gstRate = 18,
    int salePrice = 10000,
    int purchasePrice = 6000,
    int stock = 10,
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

  Future<int> sell({
    required int productId,
    int? customerId,
    double qty = 2,
    int price = 10000,
    int gstRate = 18,
    int amountPaid = 0,
    String mode = 'Cash',
    String? date,
    String? dueDate,
  }) async {
    final quote = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: qty, price: price, gstRate: gstRate)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );
    final line = quote.lines.first;
    return repo.finalizeSale(
      businessId: businessId,
      number: await repo.nextInvoiceNumber(businessId, 'INV'),
      customerId: customerId,
      customerName: customerId == null ? 'Walk-in customer' : 'Acme',
      date: date ?? '2026-09-02',
      dueDate: dueDate,
      gstType: 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: productId,
          name: 'Widget',
          gstRate: gstRate,
          quantity: qty,
          price: price,
          taxable: line.taxable.paise,
          tax: line.tax.paise,
        )
      ],
      paymentMode: amountPaid > 0 ? mode : null,
      amountPaid: amountPaid,
    );
  }

  test('sample data leaves the invoice counter clear of the numbers it used',
      () async {
    await seedDemoData(repo, businessId);
    final seeded = await repo.invoices(businessId);
    expect(seeded.length, 3);
    // the counter must be past the seeded numbers, or the first real sale
    // collides with the UNIQUE index on (business_id, number)
    expect(await repo.nextInvoiceNumber(businessId, 'INV'), 'INV-0004');
    expect(seeded.map((i) => i.number).toSet().length, seeded.length);
  });

  test('invoice numbering increments per business', () async {
    expect(await repo.nextInvoiceNumber(businessId, 'INV'), 'INV-0001');
    expect(await repo.nextInvoiceNumber(businessId, 'inv'), 'INV-0002');
    expect(await repo.nextInvoiceNumber(businessId, ''), 'INV-0003');
  });

  test('a product without SKU or barcode is not a duplicate', () async {
    await repo.upsertProduct(Product(name: 'Loose item A'),
        businessIdOverride: businessId);
    await repo.upsertProduct(Product(name: 'Loose item B'),
        businessIdOverride: businessId);
    expect((await repo.products(businessId)).length, 2);
  });

  test('a real duplicate SKU is rejected', () async {
    await addProduct(sku: 'W-1');
    await expectLater(
      addProduct(name: 'Other', sku: 'W-1'),
      throwsA(isA<StateError>()),
    );
  });

  test('finalizeSale writes items, decrements stock and balances the ledger',
      () async {
    final productId = await addProduct();
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    final invoiceId = await sell(productId: productId, customerId: customerId);

    final invoice = await repo.invoice(businessId, invoiceId);
    expect(invoice!.lines.length, 1);
    expect(invoice.total, 23600); // 2 x 100.00 + 18% GST
    expect(invoice.cgst + invoice.sgst, 3600);
    expect(invoice.status, 'Unpaid');

    final product = (await repo.products(businessId)).single;
    expect(product.stock, 8);
    expect((await repo.stockMoves(businessId, productId)).length, 2);

    // customer owes the full invoice
    expect(await repo.partyBalance(businessId, 'customer', customerId), 23600);
  });

  test('stock cannot go negative unless the business allows it', () async {
    final productId = await addProduct(stock: 1);
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    await expectLater(
      sell(productId: productId, customerId: customerId, qty: 5),
      throwsA(isA<StateError>()),
    );
  });

  test('createPurchase records the expense, stock and payables', () async {
    final productId = await addProduct(stock: 4, purchasePrice: 5000);
    final supplierId = await repo.upsertSupplier(Supplier(name: 'Vendor'),
        businessIdOverride: businessId);
    // notes used to be written to a column that does not exist on `expenses`
    await repo.createPurchase(
      businessId: businessId,
      supplierId: supplierId,
      supplierName: 'Vendor',
      date: '2026-09-02',
      items: [(productId, 'Widget', 6, 5000, 18)],
      amountPaid: 0,
      notes: 'restock order 7',
    );

    final product = (await repo.products(businessId)).single;
    expect(product.stock, 10);
    expect(product.costAverage, 5000);
    // 6 x 50.00 + 18% = 354.00 owed to the supplier
    expect(await repo.partyBalance(businessId, 'supplier', supplierId), 35400);
    expect((await repo.expenses(businessId)).single.description,
        contains('restock order 7'));
  });

  test('a purchase of zero quantity does not blow up the cost average',
      () async {
    final productId = await addProduct(stock: 0, purchasePrice: 0);
    await repo.createPurchase(
      businessId: businessId,
      supplierId: null,
      supplierName: 'Direct',
      date: '2026-09-02',
      items: [(productId, 'Widget', 0, 0, 0)],
      amountPaid: 0,
    );
    expect((await repo.products(businessId)).single.costAverage, 0);
  });

  test('recordPayment allocates across invoices and settles them', () async {
    final productId = await addProduct(stock: 50);
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    final first = await sell(productId: productId, customerId: customerId);
    final second = await sell(productId: productId, customerId: customerId);

    await repo.recordPayment(
      businessId: businessId,
      partyType: 'customer',
      amount: 30000,
      date: '2026-09-02',
      mode: 'Cash',
      invoiceIds: [first, second],
      partyId: customerId,
      partyName: 'Acme',
    );

    expect((await repo.invoice(businessId, first))!.status, 'Paid');
    expect((await repo.invoice(businessId, second))!.status, 'Partially paid');
    expect(await repo.partyBalance(businessId, 'customer', customerId),
        23600 * 2 - 30000);
  });

  test('recordPayment settles walk-in invoices and invoicesForParty retrieves them', () async {
    final productId = await addProduct(stock: 10);
    final walkInInvoiceId = await sell(productId: productId, customerId: null);

    final walkInInvoices = await repo.invoicesForParty(businessId, 'customer', null);
    expect(walkInInvoices.any((i) => i.id == walkInInvoiceId), isTrue);

    await repo.recordPayment(
      businessId: businessId,
      partyType: 'customer',
      amount: 23600,
      date: '2026-09-02',
      mode: 'Cash',
      invoiceIds: [walkInInvoiceId],
      partyId: null,
      partyName: 'Walk-in customer',
    );

    expect((await repo.invoice(businessId, walkInInvoiceId))!.status, 'Paid');
  });

  test('cash and bank balances follow the direction of the money', () async {
    final productId = await addProduct(stock: 50);
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    // ₹236 received in cash
    await sell(
        productId: productId, customerId: customerId, amountPaid: 23600);
    // ₹100 paid out of the bank
    await repo.recordExpense(
      businessId: businessId,
      category: 'Rent',
      amount: 10000,
      mode: 'Bank transfer',
      date: '2026-09-02',
      description: 'Shop rent',
    );

    final totals = await repo.dashboardTotals(businessId,
        day: DateTime(2026, 9, 2));
    expect(totals['cash'], 23600);
    expect(totals['bank'], -10000);
    expect(totals['salesToday'], 23600);
    expect(totals['taxableToday'], 20000);
    expect(totals['expensesToday'], 10000);
  });

  test('report queries run against the real schema', () async {
    final productId = await addProduct(stock: 50);
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    await sell(productId: productId, customerId: customerId, amountPaid: 23600);
    await repo.recordExpense(
      businessId: businessId,
      category: 'Rent',
      amount: 10000,
      mode: 'Cash',
      date: '2026-09-02',
    );

    final period = await repo.periodTotals(businessId, '2026-09-01');
    expect(period['sales'], 23600);
    expect(period['taxable'], 20000);
    expect(period['collected'], 23600);

    expect(await repo.expenseBreakdown(businessId, '2026-09-01'),
        [('Rent', 10000)]);

    // `taxable` exists on both invoice_items and invoices — this JOIN used to
    // fail with "ambiguous column name" and hang the Reports screen.
    final best = await repo.bestProducts(businessId, '2026-09-01');
    expect(best, [('Widget', 2, 20000)]);
  });

  test('inactive rows are hidden unless explicitly requested', () async {
    final productId = await addProduct();
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    await repo.upsertProduct(
      Product(id: productId, name: 'Widget', sku: 'W-1', inactive: true),
      businessIdOverride: businessId,
    );
    await repo.softDeleteCustomer(businessId, customerId);

    expect(await repo.products(businessId), isEmpty);
    expect((await repo.products(businessId, includeInactive: true)).length, 1);
    expect(await repo.customers(businessId), isEmpty);
    expect((await repo.customers(businessId, includeInactive: true)).length, 1);
  });

  test('every write leaves an audit trail and a sync job', () async {
    final productId = await addProduct();
    final customerId = await repo.upsertCustomer(Customer(name: 'Acme'),
        businessIdOverride: businessId);
    await sell(productId: productId, customerId: customerId);

    final audit = await repo.auditLog(businessId);
    expect(audit.map((e) => e.entity), containsAll(['business', 'product', 'customer', 'invoice']));
    expect(await repo.pendingSyncCount(), greaterThan(0));

    final queued = await repo.syncQueue();
    await repo.markSyncSuccess(queued.first.id!);
    expect(await repo.pendingSyncCount(), queued.length - 1);
  });

  test('recentTransactions aggregates sales, purchases, payments, and expenses correctly', () async {
    final productId = await addProduct(salePrice: 10000, purchasePrice: 5000);
    final customerId = await repo.upsertCustomer(Customer(name: 'Customer A'), businessIdOverride: businessId);
    final supplierId = await repo.upsertSupplier(Supplier(name: 'Supplier B'), businessIdOverride: businessId);

    // 1. Sale
    await sell(productId: productId, customerId: customerId, qty: 1, price: 10000, amountPaid: 10000);

    // 2. Purchase
    await repo.createPurchase(
      businessId: businessId,
      supplierId: supplierId,
      supplierName: 'Supplier B',
      date: '2026-09-03',
      items: [(productId, 'Widget', 5.0, 5000, 18)],
      amountPaid: 25000,
      paymentMode: 'Cash',
    );

    // 3. Standalone Payment In
    await repo.recordPayment(
      businessId: businessId,
      partyType: 'customer',
      partyId: customerId,
      partyName: 'Customer A',
      amount: 5000,
      date: '2026-09-04',
      mode: 'UPI',
    );

    // 4. Expense
    await repo.recordExpense(
      businessId: businessId,
      category: 'Utilities',
      amount: 1500,
      mode: 'Cash',
      date: '2026-09-05',
      description: 'Electricity Bill',
    );

    final txs = await repo.recentTransactions(businessId, limit: 10);
    expect(txs.length, 4);

    final types = txs.map((t) => t.type).toList();
    expect(types, contains(TransactionType.sale));
    expect(types, contains(TransactionType.purchase));
    expect(types, contains(TransactionType.paymentIn));
    expect(types, contains(TransactionType.expense));

    // Verify latest transaction is first (Electricity Bill on 2026-09-05)
    expect(txs.first.type, TransactionType.expense);
    expect(txs.first.amount, 1500);
  });

  test('lowStockProducts and outOfStockProducts return filtered inventory correctly', () async {
    // Product 1: healthy stock (20)
    await repo.upsertProduct(Product(
      name: 'Healthy Item',
      sku: 'H-1',
      salePrice: 1000,
      stock: 20,
      lowStockThreshold: 5,
    ), businessIdOverride: businessId);

    // Product 2: low stock (3 <= threshold 5)
    await repo.upsertProduct(Product(
      name: 'Low Stock Item',
      sku: 'L-1',
      salePrice: 1000,
      stock: 3,
      lowStockThreshold: 5,
    ), businessIdOverride: businessId);

    // Product 3: out of stock (0)
    await repo.upsertProduct(Product(
      name: 'Out of Stock Item',
      sku: 'O-1',
      salePrice: 1000,
      stock: 0,
      lowStockThreshold: 5,
    ), businessIdOverride: businessId);

    final low = await repo.lowStockProducts(businessId);
    expect(low.length, 1);
    expect(low.first.name, 'Low Stock Item');

    final out = await repo.outOfStockProducts(businessId);
    expect(out.length, 1);
    expect(out.first.name, 'Out of Stock Item');
  });

  test('overdueInvoicesSummary and overdueInvoices identify unpaid invoices past due date', () async {
    final custId = await repo.upsertCustomer(
      Customer(name: 'Due Customer', phone: '9999900000'),
      businessIdOverride: businessId,
    );
    final pId = await addProduct(stock: 50);

    // 1. Invoice with past due date (overdue)
    await sell(
      productId: pId,
      customerId: custId,
      qty: 2,
      amountPaid: 0,
      date: '2026-08-01',
      dueDate: '2026-08-15',
    );

    // 2. Invoice with future due date (not overdue)
    await sell(
      productId: pId,
      customerId: custId,
      qty: 1,
      amountPaid: 0,
      date: '2026-09-10',
      dueDate: '2026-10-15',
    );

    final (count, amount) = await repo.overdueInvoicesSummary(businessId);
    expect(count, 1);
    expect(amount, greaterThan(0));

    final overdueList = await repo.overdueInvoices(businessId);
    expect(overdueList.length, 1);
    expect(overdueList.first.dueDate, '2026-08-15');
  });

  test('dashboardTotals respects fromDate range', () async {
    final custId = await repo.upsertCustomer(
      Customer(name: 'Date Customer', phone: '9999911111'),
      businessIdOverride: businessId,
    );
    final pId = await addProduct(stock: 100);
    // Sale in July
    await sell(productId: pId, customerId: custId, qty: 1, amountPaid: 10000, date: '2026-07-01');
    // Sale in September
    await sell(productId: pId, customerId: custId, qty: 2, amountPaid: 20000, date: '2026-09-10');

    // Totals from September 1st onward
    final septTotals = await repo.dashboardTotals(businessId, fromDate: '2026-09-01');
    // Totals all time (or earlier)
    final allTotals = await repo.dashboardTotals(businessId, fromDate: '2026-01-01');

    expect(septTotals['salesToday']!, lessThan(allTotals['salesToday']!));
  });

  test('dashboardPerformance returns dynamic trends and history for all timeframes', () async {
    final custId = await repo.upsertCustomer(
      Customer(name: 'Trend Customer', phone: '9999922222'),
      businessIdOverride: businessId,
    );
    final pId = await addProduct(stock: 100);
    final now = DateTime.now();
    final todayStr = isoDate(now);
    await sell(productId: pId, customerId: custId, qty: 1, amountPaid: 10000, date: todayStr);

    final perfToday = await repo.dashboardPerformance(businessId, 'Today');
    expect(perfToday.comparisonLabel, 'vs yesterday');
    expect(perfToday.salesHistory.length, 7);
    expect(perfToday.profitHistory.length, 7);
    expect(perfToday.salesTrend.formatted, isNotEmpty);

    final perfWeek = await repo.dashboardPerformance(businessId, 'This Week');
    expect(perfWeek.comparisonLabel, 'vs last week');
    expect(perfWeek.salesHistory.length, 7);
    expect(perfWeek.profitHistory.length, 7);

    final perfMonth = await repo.dashboardPerformance(businessId, 'This Month');
    expect(perfMonth.comparisonLabel, 'vs last month');
    expect(perfMonth.salesHistory.length, greaterThanOrEqualTo(28));
    expect(perfMonth.profitHistory.length, greaterThanOrEqualTo(28));

    final perfYear = await repo.dashboardPerformance(businessId, 'This Year');
    expect(perfYear.comparisonLabel, 'vs last year');
    expect(perfYear.salesHistory.length, 12);
    expect(perfYear.profitHistory.length, 12);
  });
}

