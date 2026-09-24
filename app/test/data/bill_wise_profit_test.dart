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
    String name = 'Smart Watch',
    String sku = 'SW-1',
    int gstRate = 18,
    int salePrice = 200000,
    int purchasePrice = 120000,
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

  test('billWiseProfitReport calculates profit, margin, and cost correctly', () async {
    final pId = await addProduct();
    final customerId = await repo.upsertCustomer(
      Customer(name: 'Rahul Sharma', phone: '9876543210'),
      businessIdOverride: businessId,
    );

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final quote = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: 2, price: 200000, gstRate: 18)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );
    final line = quote.lines.first;

    final invId = await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-0001',
      customerId: customerId,
      customerName: 'Rahul Sharma',
      date: today,
      gstType: 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: pId,
          name: 'Smart Watch',
          gstRate: 18,
          quantity: 2,
          price: 200000,
          taxable: line.taxable.paise,
          tax: line.tax.paise,
        ),
      ],
      paymentMode: 'Cash',
      amountPaid: quote.total.paise,
    );

    expect(invId, isPositive);

    final reports = await repo.billWiseProfitReport(
      businessId,
      fromDate: today,
      toDate: today,
    );

    expect(reports.length, 1);
    final rep = reports.first;
    expect(rep.number, 'INV-0001');
    expect(rep.customerName, 'Rahul Sharma');
    // Taxable = 400000 paise (4000.00)
    expect(rep.taxable, 400000);
    // Cost = 2 * 120000 = 240000 paise (2400.00)
    expect(rep.cogs, 240000);
    // Profit = 400000 - 240000 = 160000 paise (1600.00)
    expect(rep.profit, 160000);
    expect(rep.isProfitable, isTrue);
    expect(rep.margin, closeTo(40.0, 0.1));
    expect(rep.items.length, 1);
    expect(rep.items.first.name, 'Smart Watch');
    expect(rep.items.first.profit, 160000);
  });

  test('salesSummaryReport aggregates sales, taxes, and payment modes correctly', () async {
    final pId = await addProduct(name: 'Headphones', sku: 'HP-1', salePrice: 100000, purchasePrice: 50000);
    final customerId = await repo.upsertCustomer(
      Customer(name: 'Anita Roy', phone: '9123456780'),
      businessIdOverride: businessId,
    );

    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Sale 1: Cash
    final quote1 = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: 1, price: 100000, gstRate: 18)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );
    await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-0002',
      customerId: customerId,
      customerName: 'Anita Roy',
      date: today,
      gstType: 'intra',
      quote: quote1,
      lines: [
        InvoiceLine(
          productId: pId,
          name: 'Headphones',
          gstRate: 18,
          quantity: 1,
          price: 100000,
          taxable: quote1.lines.first.taxable.paise,
          tax: quote1.lines.first.tax.paise,
        ),
      ],
      paymentMode: 'Cash',
      amountPaid: quote1.total.paise,
    );

    // Sale 2: UPI
    final quote2 = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: 2, price: 100000, gstRate: 18)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Karnataka',
      customerState: 'Karnataka',
    );
    await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-0003',
      customerId: customerId,
      customerName: 'Anita Roy',
      date: today,
      gstType: 'intra',
      quote: quote2,
      lines: [
        InvoiceLine(
          productId: pId,
          name: 'Headphones',
          gstRate: 18,
          quantity: 2,
          price: 100000,
          taxable: quote2.lines.first.taxable.paise,
          tax: quote2.lines.first.tax.paise,
        ),
      ],
      paymentMode: 'UPI',
      amountPaid: quote2.total.paise,
    );

    final summary = await repo.salesSummaryReport(businessId, fromDate: today, toDate: today);

    expect(summary.invoiceCount, 2);
    expect(summary.totalGrossSales, quote1.total.paise + quote2.total.paise);
    expect(summary.totalTaxable, quote1.subtotal.paise + quote2.subtotal.paise);
    expect(summary.paymentModes['Cash'], quote1.total.paise);
    expect(summary.paymentModes['UPI'], quote2.total.paise);
    expect(summary.invoices.length, 2);
  });
}
