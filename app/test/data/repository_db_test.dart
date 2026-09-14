// Drives the real Repository against an in-memory copy of the real schema.
// This is the check that catches SQL/schema drift: a column that does not exist,
// an ambiguous column in a JOIN, or a ledger sign flipped the wrong way.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
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
    required int customerId,
    double qty = 2,
    int price = 10000,
    int gstRate = 18,
    int amountPaid = 0,
    String mode = 'Cash',
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
      customerName: 'Acme',
      date: '2026-09-02',
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
}
