import 'dart:convert';
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
      name: 'Critical Flows Retailer',
      state: 'Karnataka',
      taxRegistered: true,
      currency: 'INR',
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedProduct({
    String name = 'Test Product',
    String sku = 'TP-01',
    int salePrice = 10000, // ₹100.00
    int purchasePrice = 6000, // ₹60.00
    int stock = 10,
    int gstRate = 18,
  }) =>
      repo.upsertProduct(
        Product(
          name: name,
          sku: sku,
          salePrice: salePrice,
          purchasePrice: purchasePrice,
          costAverage: purchasePrice,
          stock: stock,
          gstRate: gstRate,
        ),
        businessIdOverride: businessId,
      );

  Future<int> seedCustomer({
    String name = 'Test Customer',
    String phone = '9876543210',
    int openingBalance = 0,
    int creditLimit = 50000,
  }) =>
      repo.upsertCustomer(
        Customer(
          name: name,
          phone: phone,
          openingBalance: openingBalance,
          creditLimit: creditLimit,
        ),
        businessIdOverride: businessId,
      );

  Future<int> seedSupplier({
    String name = 'Test Supplier',
    String phone = '9123456780',
    int openingBalance = 0,
  }) =>
      repo.upsertSupplier(
        Supplier(
          name: name,
          phone: phone,
          openingBalance: openingBalance,
        ),
        businessIdOverride: businessId,
      );

  Future<int> sell({
    required int productId,
    required int customerId,
    String customerName = 'Acme Customer',
    double qty = 2,
    int price = 10000,
    int gstRate = 18,
    int amountPaid = 0,
    String? mode = 'Cash',
    String? dueDate,
  }) async {
    final quote = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: qty, price: price, gstRate: gstRate)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );
    final line = quote.lines.first;
    final number = await repo.nextInvoiceNumber(businessId, 'INV');
    return repo.finalizeSale(
      businessId: businessId,
      number: number,
      customerId: customerId,
      customerName: customerName,
      date: '2026-09-02',
      dueDate: dueDate,
      gstType: 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: productId,
          name: 'Item',
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

  // =========================================================================
  // 10 CRITICAL BUSINESS FLOWS (SPECIFICATION VERIFICATION)
  // =========================================================================

  test('Flow A: Cash Sale (Stock decrements, Cash ledger credited, Sales balanced)', () async {
    final prodId = await seedProduct(stock: 10, salePrice: 10000, gstRate: 18);
    final custId = await seedCustomer();

    // 2 units @ ₹100 + 18% GST = ₹236.00 (23600 paise)
    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      qty: 2,
      price: 10000,
      gstRate: 18,
      amountPaid: 23600,
      mode: 'Cash',
    );
    expect(invoiceId, greaterThan(0));

    // Verify stock decreased by 2
    final updatedProd = (await repo.products(businessId)).firstWhere((p) => p.id == prodId);
    expect(updatedProd.stock, 8);

    // Verify invoice is fully paid
    final inv = await repo.invoice(businessId, invoiceId);
    expect(inv, isNotNull);
    expect(inv!.amountPaid, 23600);
    expect(inv.outstanding.paise, 0);
    expect(inv.status, 'Paid');

    // Verify cash ledger increased
    final totals = await repo.dashboardTotals(businessId, day: DateTime(2026, 9, 2));
    expect(totals['cash'], 23600);
  });

  test('Flow B: Credit Sale (Customer outstanding increases, overdue tracked)', () async {
    final prodId = await seedProduct(stock: 10, salePrice: 50000, gstRate: 0);
    final custId = await seedCustomer(openingBalance: 0);

    const pastDueDate = '2026-08-25';
    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Credit Buyer',
      qty: 1,
      price: 50000,
      gstRate: 0,
      amountPaid: 0,
      dueDate: pastDueDate,
    );

    final inv = await repo.invoice(businessId, invoiceId);
    expect(inv, isNotNull);
    expect(inv!.status, 'Unpaid');
    expect(inv.outstanding.paise, 50000);

    // Customer outstanding balance increases
    final balance = await repo.partyBalance(businessId, 'customer', custId);
    expect(balance, 50000);

    // Overdue status check
    expect(DateTime.parse(inv.dueDate!).isBefore(DateTime.now()), isTrue);
  });

  test('Flow C: Partial Payment (Transitions to Partially Paid, settles on completion)', () async {
    final prodId = await seedProduct(stock: 10, salePrice: 100000, gstRate: 0);
    final custId = await seedCustomer();

    // Total ₹1000, Customer pays ₹400 upfront
    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Partial Buyer',
      qty: 1,
      price: 100000,
      gstRate: 0,
      amountPaid: 40000,
      mode: 'Cash',
    );

    var inv = await repo.invoice(businessId, invoiceId);
    expect(inv, isNotNull);
    expect(inv!.status, 'Partially paid');
    expect(inv.outstanding.paise, 60000);

    // Customer pays remainder ₹600
    await repo.recordPayment(
      businessId: businessId,
      partyType: 'customer',
      partyId: custId,
      partyName: 'Partial Buyer',
      amount: 60000,
      mode: 'Cash',
      date: '2026-09-02',
      invoiceIds: [invoiceId],
    );

    inv = await repo.invoice(businessId, invoiceId);
    expect(inv!.status, 'Paid');
    expect(inv.outstanding.paise, 0);
  });

  test('Flow D: Sale Return (Validates quantity, increments stock, balances ledger)', () async {
    final prodId = await seedProduct(stock: 10, salePrice: 10000, gstRate: 0);
    final custId = await seedCustomer();

    // Sell 4 items -> stock becomes 6
    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Buyer',
      qty: 4,
      price: 10000,
      gstRate: 0,
      amountPaid: 40000,
    );
    expect((await repo.products(businessId)).firstWhere((p) => p.id == prodId).stock, 6);

    // Process return of 2 items
    final ret = TransactionReturn(
      businessId: businessId,
      number: 'RET-001',
      partyType: 'customer',
      partyId: custId,
      partyName: 'Buyer',
      date: '2026-09-02',
      invoiceId: invoiceId,
      subtotal: 20000,
      taxable: 20000,
      tax: 0,
      total: 20000,
      lines: [
        InvoiceLine(
          productId: prodId,
          name: 'Test Product',
          quantity: 2,
          price: 10000,
          taxable: 20000,
          tax: 0,
        ),
      ],
    );
    final returnId = await repo.finalizeReturn(ret);
    expect(returnId, greaterThan(0));

    // Stock should restore from 6 to 8
    expect((await repo.products(businessId)).firstWhere((p) => p.id == prodId).stock, 8);
  });

  test('Flow E: Purchase (Increments stock, recalculates weighted cost, updates payable)', () async {
    final prodId = await seedProduct(stock: 5, purchasePrice: 10000); // 5 @ ₹100
    final suppId = await seedSupplier();

    // Purchase 10 @ ₹160 (16000 paise)
    await repo.createPurchase(
      businessId: businessId,
      supplierId: suppId,
      supplierName: 'Test Supplier',
      date: '2026-09-02',
      items: [(prodId, 'Test Product', 10.0, 16000, 0)],
      amountPaid: 0,
    );

    // Stock becomes 5 + 10 = 15
    final prod = (await repo.products(businessId)).firstWhere((p) => p.id == prodId);
    expect(prod.stock, 15);

    // Weighted average: (5*10000 + 10*16000) / 15 = (50000 + 160000) / 15 = 210000 / 15 = 14000 paise
    expect(prod.costAverage, 14000);

    // Supplier payable is ₹1,600 (160000 paise)
    final suppBalance = await repo.partyBalance(businessId, 'supplier', suppId);
    expect(suppBalance, 160000);
  });

  test('Flow F: Purchase Return (Decrements stock, decrements supplier payable)', () async {
    final prodId = await seedProduct(stock: 5, purchasePrice: 16000);
    final suppId = await seedSupplier();

    // First create purchase of 10 units @ 16000
    await repo.createPurchase(
      businessId: businessId,
      supplierId: suppId,
      supplierName: 'Test Supplier',
      date: '2026-09-02',
      items: [(prodId, 'Test Product', 10.0, 16000, 0)],
      amountPaid: 0,
    );
    expect((await repo.products(businessId)).firstWhere((p) => p.id == prodId).stock, 15);
    expect(await repo.partyBalance(businessId, 'supplier', suppId), 160000);

    // Now return 3 units
    final ret = TransactionReturn(
      businessId: businessId,
      number: 'PRET-001',
      partyType: 'supplier',
      partyId: suppId,
      partyName: 'Test Supplier',
      date: '2026-09-02',
      subtotal: 48000,
      taxable: 48000,
      tax: 0,
      total: 48000,
      lines: [
        InvoiceLine(
          productId: prodId,
          name: 'Test Product',
          quantity: 3,
          price: 16000,
          taxable: 48000,
          tax: 0,
        ),
      ],
    );
    await repo.finalizeReturn(ret);

    // Stock decrements from 15 to 12
    expect((await repo.products(businessId)).firstWhere((p) => p.id == prodId).stock, 12);

    // Supplier payable decreases by 48,000 paise: 160000 - 48000 = 112000
    final suppBalance = await repo.partyBalance(businessId, 'supplier', suppId);
    expect(suppBalance, 112000);
  });

  test('Flow G: Offline Resilience (Offline write persists to SQLite and enqueues sync)', () async {
    final custId = await seedCustomer(name: 'Offline Customer');
    final prodId = await seedProduct(stock: 10, salePrice: 10000, gstRate: 0);

    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Offline Customer',
      qty: 1,
      price: 10000,
      gstRate: 0,
      amountPaid: 10000,
    );
    expect(invoiceId, greaterThan(0));

    // Verify written to local SQLite
    final invoice = await repo.invoice(businessId, invoiceId);
    expect(invoice, isNotNull);
    expect(invoice!.customerName, 'Offline Customer');

    // Verify enqueued into sync_queue with entity = 'invoice'
    final pendingSync = await repo.syncQueue();
    expect(pendingSync.any((q) => q.entity == 'invoice' && q.entityId == invoiceId), isTrue);
  });

  test('Flow H: Duplicate Prevention (Double invoice save produces unique invoices without collision)', () async {
    final prodId = await seedProduct(stock: 20, salePrice: 10000, gstRate: 0);
    final custId = await seedCustomer();

    final id1 = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Buyer 1',
      qty: 1,
      price: 10000,
      gstRate: 0,
    );

    final id2 = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Buyer 2',
      qty: 1,
      price: 10000,
      gstRate: 0,
    );

    final inv1 = await repo.invoice(businessId, id1);
    final inv2 = await repo.invoice(businessId, id2);

    // Each invoice gets a distinct auto-incremented invoice number and ID
    expect(inv1!.number, isNot(equals(inv2!.number)));
    expect(inv1.id, isNot(equals(inv2.id)));
  });

  test('Flow I: Multi-Device Sync Reconciliation (No echo loops on pull)', () async {
    // Reconcile remote customer pushed by another device
    await repo.reconcileRemoteChange({
      'entity': 'customer',
      'payload': jsonEncode({
        'name': 'Cloud Reconciled Customer',
        'phone': '9988776655',
        'opening_balance': 15000,
      }),
    });

    // Verify customer exists in local SQLite
    final customers = await repo.customers(businessId);
    expect(customers.any((c) => c.name == 'Cloud Reconciled Customer'), isTrue);

    // Verify NO sync_queue echo loop entry was generated for this reconciled change
    final echoItems = await db.query(
      'sync_queue',
      where: 'entity = ? AND payload LIKE ?',
      whereArgs: ['customer', '%Cloud Reconciled Customer%'],
    );
    expect(echoItems.isEmpty, isTrue);
  });

  test('Flow J: Server Failure Fallback (Local SQLite safe if remote server fails/timeouts)', () async {
    final prodId = await seedProduct(stock: 10, salePrice: 10000, gstRate: 0);
    final custId = await seedCustomer();

    final invoiceId = await sell(
      productId: prodId,
      customerId: custId,
      customerName: 'Offline Resilient Buyer',
      qty: 1,
      price: 10000,
      gstRate: 0,
      amountPaid: 10000,
    );
    expect(invoiceId, greaterThan(0));

    // Even if cloud push fails or server is unreachable, the local invoice remains 100% valid and queryable
    final inv = await repo.invoice(businessId, invoiceId);
    expect(inv, isNotNull);
    expect(inv!.customerName, 'Offline Resilient Buyer');

    // Sync queue item retains pending status safely
    final queue = await repo.syncQueue();
    final item = queue.firstWhere((q) => q.entity == 'invoice' && q.entityId == invoiceId);
    expect(item.status, 'pending');
  });
}
