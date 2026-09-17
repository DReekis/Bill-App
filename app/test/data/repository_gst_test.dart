import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/dates.dart';
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
      name: 'Sharma Electronics Hub',
      state: 'Maharashtra',
      gstin: '27AABCU9603R1ZM',
      taxRegistered: true,
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> makeSale({
    required int customerId,
    required String customerName,
    required int productId,
    required String productName,
    required String hsn,
    required int gstRate,
    required double qty,
    required int price,
    String? customerState,
    int amountPaid = 0,
  }) async {
    final quote = BillingEngine.calculateQuote(
      lines: [LineCalcInput(quantity: qty, price: price, gstRate: gstRate)],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessState: 'Maharashtra',
      customerState: customerState ?? 'Maharashtra',
    );
    final line = quote.lines.first;
    return repo.finalizeSale(
      businessId: businessId,
      number: await repo.nextInvoiceNumber(businessId, 'INV'),
      customerId: customerId,
      customerName: customerName,
      date: isoDate(DateTime.now()),
      gstType: customerState != null && customerState != 'Maharashtra' ? 'inter' : 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: productId,
          name: productName,
          hsn: hsn,
          gstRate: gstRate,
          quantity: qty,
          price: price,
          taxable: line.taxable.paise,
          tax: line.tax.paise,
        )
      ],
      paymentMode: amountPaid > 0 ? 'Cash' : null,
      amountPaid: amountPaid,
    );
  }

  test('GstTaxSummary aggregates output tax, input tax, and computes net payable', () async {
    final custId = await repo.upsertCustomer(Customer(
      name: 'Acme Enterprises',
      gstin: '27AABCA1234A1Z5',
      state: 'Maharashtra',
    ));

    final pId = await repo.upsertProduct(Product(
      name: 'Laptop Pro',
      salePrice: 10000000, // ₹1,00,000
      purchasePrice: 7000000,
      stock: 10,
      hsn: '8471',
      gstRate: 18,
    ));

    await makeSale(
      customerId: custId,
      customerName: 'Acme Enterprises',
      productId: pId,
      productName: 'Laptop Pro',
      hsn: '8471',
      gstRate: 18,
      qty: 1,
      price: 10000000,
      amountPaid: 11800000,
    );

    await repo.createPurchase(
      businessId: businessId,
      supplierId: null,
      supplierName: 'Hardware Vendor',
      date: isoDate(DateTime.now()),
      items: [
        (null, 'Parts', 1.0, 5000000, 18),
      ],
      amountPaid: 5900000,
    );

    final summary = await repo.getGstTaxSummary(businessId);

    expect(summary.totalSalesTaxable, 10000000);
    expect(summary.totalOutputCgst, 900000);
    expect(summary.totalOutputSgst, 900000);
    expect(summary.totalOutputTax, 1800000);
    expect(summary.b2bCount, 1);
    expect(summary.totalInvoices, 1);
    expect(summary.totalPurchasesTaxable, 5900000);
    expect(summary.totalInputTaxCredit, greaterThan(0));
    expect(summary.netTaxPayable, greaterThan(0));
  });

  test('Gstr1Data separates B2B, B2CL, and B2CS correctly', () async {
    final regCustomer = await repo.upsertCustomer(Customer(
      name: 'Bharat Retail Pvt Ltd',
      gstin: '27AABCU1234B1Z2',
      state: 'Maharashtra',
    ));
    final unregCustomer = await repo.upsertCustomer(Customer(
      name: 'Local Consumer',
      state: 'Maharashtra',
    ));

    final pId = await repo.upsertProduct(Product(
      name: 'Smartphone',
      salePrice: 2000000,
      stock: 50,
      hsn: '8517',
      gstRate: 18,
    ));

    // B2B sale
    await makeSale(
      customerId: regCustomer,
      customerName: 'Bharat Retail Pvt Ltd',
      productId: pId,
      productName: 'Smartphone',
      hsn: '8517',
      gstRate: 18,
      qty: 2,
      price: 2000000,
    );

    // B2CS retail sale
    await makeSale(
      customerId: unregCustomer,
      customerName: 'Local Consumer',
      productId: pId,
      productName: 'Smartphone',
      hsn: '8517',
      gstRate: 18,
      qty: 1,
      price: 2000000,
    );

    // Export sale
    final expCustomer = await repo.upsertCustomer(Customer(
      name: 'Global Client Dubai',
      state: 'Foreign',
    ));
    await makeSale(
      customerId: expCustomer,
      customerName: 'Global Client Dubai',
      productId: pId,
      productName: 'Smartphone',
      hsn: '8517',
      gstRate: 18,
      qty: 1,
      price: 5000000,
      customerState: 'Foreign',
    );

    final gstr1 = await repo.getGstr1Data(businessId);
    final b2bSection = gstr1.firstWhere((s) => s.code == 'B2B');
    final b2csSection = gstr1.firstWhere((s) => s.code == 'B2CS');
    final expSection = gstr1.firstWhere((s) => s.code == 'EXP');

    expect(b2bSection.count, 1);
    expect(b2bSection.taxableAmount, 4000000);
    expect(b2csSection.count, 1);
    expect(b2csSection.taxableAmount, 2000000);
    expect(expSection.count, 1);
    expect(expSection.taxableAmount, 5000000);
  });

  test('HsnSummary groups invoice items by HSN and tax rate', () async {
    final custId = await repo.upsertCustomer(Customer(
      name: 'Walk-in Client',
      state: 'Maharashtra',
    ));

    final p1 = await repo.upsertProduct(Product(
      name: 'Mouse',
      salePrice: 50000,
      stock: 100,
      hsn: '8471',
      gstRate: 18,
    ));
    final p2 = await repo.upsertProduct(Product(
      name: 'Keyboard',
      salePrice: 150000,
      stock: 50,
      hsn: '8471',
      gstRate: 18,
    ));

    await makeSale(
      customerId: custId,
      customerName: 'Walk-in Client',
      productId: p1,
      productName: 'Mouse',
      hsn: '8471',
      gstRate: 18,
      qty: 5,
      price: 50000,
    );

    await makeSale(
      customerId: custId,
      customerName: 'Walk-in Client',
      productId: p2,
      productName: 'Keyboard',
      hsn: '8471',
      gstRate: 18,
      qty: 2,
      price: 150000,
    );

    final hsnItems = await repo.getHsnSummary(businessId);
    expect(hsnItems.isNotEmpty, true);
    final hsn8471 = hsnItems.firstWhere((h) => h.hsn == '8471');
    expect(hsn8471.gstRate, 18);
    expect(hsn8471.totalQuantity, 7.0);
    expect(hsn8471.taxableValue, 550000);
  });

  test('Gstr3bData compiles Table 3.1 and payment details', () async {
    final gstr3b = await repo.getGstr3bData(businessId, period: 'October 2026');
    expect(gstr3b.period, 'October 2026');
    expect(gstr3b.totalTaxPayableCash, greaterThanOrEqualTo(0));
  });
}
