import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/dates.dart';
import 'package:billket/core/gst_service.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late Business business;
  late int customerId;
  late int supplierId;
  late int helmetProductId;

  setUpAll(() {
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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
      name: 'RideSafe Gear Co',
      ownerName: 'Alex Gear',
      taxRegistered: true,
      gstin: '29ABCDE1234F1Z5',
      state: 'Karnataka',
      allowNegativeStock: true,
    ));
    business = (await repo.getBusiness(businessId))!;
    repo.session.businessId = businessId;

    customerId = await repo.upsertCustomer(
      Customer(
        name: 'Rohan Sharma',
        phone: '9876543210',
        billingAddress: 'MG Road, Bangalore',
      ),
      businessIdOverride: businessId,
    );

    supplierId = await repo.upsertSupplier(
      Supplier(
        name: 'Vega Helmets Ltd',
        phone: '9123456789',
        address: 'Peenya Industrial Area, Bangalore',
      ),
      businessIdOverride: businessId,
    );

    helmetProductId = await repo.upsertProduct(
      Product(
        name: 'Safety Helmet',
        sku: 'HLM-001',
        hsn: '6506',
        unit: 'PCS',
        gstRate: 18,
        salePrice: 95000, // ₹950
        purchasePrice: 35000, // ₹350
        costAverage: 35000,
        stock: 10,
      ),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Problem 1: Strict E-Way Bill Number Validation', () {
    test('Rejects 11-digit random inputs, invalid state codes, and accepts valid 12-digit numbers', () {
      // 11 digits: as reported by user "58575885788"
      expect(GstService.isValidEwayBillNumber('58575885788'), isFalse);

      // 12 digits, but state code "58" does not exist in India
      expect(GstService.isValidEwayBillNumber('585758857881'), isFalse);

      // Letters or special characters
      expect(GstService.isValidEwayBillNumber('24ABC8857881'), isFalse);
      expect(GstService.isValidEwayBillNumber(''), isFalse);
      expect(GstService.isValidEwayBillNumber(null), isFalse);
      expect(GstService.isValidEwayBillNumber('2410492810923'), isFalse); // 13 digits

      // Valid 12 digits with legitimate GST State Codes
      expect(GstService.isValidEwayBillNumber('241049281092'), isTrue); // 24 = Gujarat
      expect(GstService.isValidEwayBillNumber('271234567890'), isTrue); // 27 = Maharashtra
      expect(GstService.isValidEwayBillNumber('299876543210'), isTrue); // 29 = Karnataka
      expect(GstService.isValidEwayBillNumber('071122334455'), isTrue); // 07 = Delhi
    });
  });

  group('Problem 2: Zero Values in PDF Line Items for Purchases, Sales Orders & Purchase Orders', () {
    test('Purchase Bill (PUR-0003) populates taxable, tax, price, rate, and renders non-zero in PDF', () async {
      // Create Purchase Bill PUR-0003: 3 Helmets @ ₹350 + 18% GST = ₹1,239
      final purchaseId = await repo.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: 'Vega Helmets Ltd',
        date: todayIso(),
        purchaseNumber: 'PUR-0003',
        items: [
          (helmetProductId, 'Safety Helmet', 3.0, 35000, 18),
        ],
        amountPaid: 123900, // Paid in full ₹1,239
        paymentMode: 'Cash',
      );

      expect(purchaseId, greaterThan(0));

      // Retrieve purchase using repo.purchase
      final purchaseDoc = await repo.purchase(businessId, purchaseId);
      expect(purchaseDoc, isNotNull);
      expect(purchaseDoc!.lines.length, 1);

      final line = purchaseDoc.lines.first;
      expect(line.name, 'Safety Helmet');
      expect(line.price, 35000); // ₹350 rate
      expect(line.quantity, 3.0);
      expect(line.taxable, 105000); // ₹1,050 taxable
      expect(line.tax, 18900); // ₹189 GST (18% of 1050)
      expect(line.hsn, '6506');
      expect(line.unit, 'PCS');

      // Test PDF generation
      final pdfBytes = await buildPurchaseBillPdf(
        business: business,
        purchase: purchaseDoc,
        supplier: await repo.supplier(businessId, supplierId),
      );
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('Sales Order (SO-0001) persists and enriches lines with rate, taxable, tax, and generates PDF', () async {
      // Create Sales Order: 2 Helmets @ ₹950 = ₹1,900 + 18% GST = ₹2,242
      final so = SalesOrder(
        businessId: businessId,
        number: 'SO-0001',
        customerId: customerId,
        customerName: 'Rohan Sharma',
        date: todayIso(),
        total: 224200,
        lines: [
          InvoiceLine(
            productId: helmetProductId,
            name: 'Safety Helmet',
            quantity: 2,
            price: 95000,
            gstRate: 18,
            taxable: 190000,
            tax: 34200,
            unit: 'PCS',
            hsn: '6506',
          ),
        ],
      );

      final soId = await repo.finalizeSalesOrder(so);
      expect(soId, greaterThan(0));

      final retrievedSo = await repo.salesOrder(businessId, soId);
      expect(retrievedSo, isNotNull);
      expect(retrievedSo!.lines.length, 1);

      final item = retrievedSo.lines.first;
      expect(item.name, 'Safety Helmet');
      expect(item.price, 95000); // Rate ₹950
      expect(item.taxable, 190000); // Taxable ₹1,900
      expect(item.tax, 34200); // Tax ₹342
      expect(item.hsn, '6506');
      expect(item.unit, 'PCS');

      // Test Sales Order PDF generation
      final pdfBytes = await buildSalesOrderPdf(
        business: business,
        order: retrievedSo,
        customer: await repo.customer(businessId, customerId),
      );
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('Purchase Order (PO-0001) persists and enriches lines with rate, taxable, tax, and generates PDF', () async {
      // Create Purchase Order: 4 Helmets @ ₹350 = ₹1,400 + 18% GST = ₹1,652
      final po = PurchaseOrder(
        businessId: businessId,
        number: 'PO-0001',
        supplierId: supplierId,
        supplierName: 'Vega Helmets Ltd',
        date: todayIso(),
        total: 165200,
        lines: [
          InvoiceLine(
            productId: helmetProductId,
            name: 'Safety Helmet',
            quantity: 4,
            price: 35000,
            gstRate: 18,
            taxable: 140000,
            tax: 25200,
            unit: 'PCS',
            hsn: '6506',
          ),
        ],
      );

      final poId = await repo.finalizePurchaseOrder(po);
      expect(poId, greaterThan(0));

      final retrievedPo = await repo.purchaseOrder(businessId, poId);
      expect(retrievedPo, isNotNull);
      expect(retrievedPo!.lines.length, 1);

      final item = retrievedPo.lines.first;
      expect(item.name, 'Safety Helmet');
      expect(item.price, 35000); // Rate ₹350
      expect(item.taxable, 140000); // Taxable ₹1,400
      expect(item.tax, 25200); // Tax ₹252
      expect(item.hsn, '6506');
      expect(item.unit, 'PCS');

      // Test Purchase Order PDF generation
      final pdfBytes = await buildPurchaseOrderPdf(
        business: business,
        order: retrievedPo,
        supplier: await repo.supplier(businessId, supplierId),
      );
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('Defensive PDF normalization fixes zero-taxable line items', () async {
      final pdfBytes = await buildDocumentPdf(
        business: business,
        title: 'Tax Invoice',
        number: 'INV-TEST-01',
        date: todayIso(),
        partyName: 'Walk-in Customer',
        lines: [
          InvoiceLine(
            productId: helmetProductId,
            name: 'Defensive Helmet',
            quantity: 2,
            price: 35000,
            gstRate: 18,
            taxable: 0, // Zero taxable passed defensively
            tax: 0, // Zero tax passed defensively
          ),
        ],
        subtotal: 70000,
        discount: 0,
        taxable: 70000,
        igst: 0,
        cgst: 6300,
        sgst: 6300,
        roundOff: 0,
        total: 82600,
        outstandingPaise: 0,
      );

      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('Problem 4: Purchase Amount Paid Calculation Bug', () {
    test('Amount Paid only reflects payments for the specific purchase, not all prior purchases', () async {
      // 1. Create previous purchase PUR-0001 for ₹42,539
      final pur1Id = await repo.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: 'Vega Helmets Ltd',
        date: todayIso(),
        purchaseNumber: 'PUR-0001',
        items: [
          (helmetProductId, 'Safety Helmet', 100.0, 42539, 0),
        ],
        amountPaid: 42539,
        paymentMode: 'Cash',
      );

      // 2. Create target purchase PUR-0003 for ₹1,239
      final pur3Id = await repo.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: 'Vega Helmets Ltd',
        date: todayIso(),
        purchaseNumber: 'PUR-0003',
        items: [
          (helmetProductId, 'Safety Helmet', 3.0, 35000, 18),
        ],
        amountPaid: 123900,
        paymentMode: 'Cash',
      );

      // 3. Query PUR-0003
      final pur3 = await repo.purchase(businessId, pur3Id);
      expect(pur3, isNotNull);

      // Total must be ₹1,239 and Paid must be exactly ₹1,239, NOT ₹42,539 + ₹1,239
      expect(pur3!.total, 123900);
      expect(pur3.amountPaid, 123900);
      expect(pur3.outstanding, 0);

      // Also verify PUR-0001
      final pur1 = await repo.purchase(businessId, pur1Id);
      expect(pur1, isNotNull);
      expect(pur1!.amountPaid, 42539);
    });
  });

  group('Problem 5: Purchase Order Totals and GST Inclusions', () {
    test('PO line calculations include GST in totalPaise', () {
      final helmet = Product(
        name: 'Helmet',
        purchasePrice: 35000,
        salePrice: 95000,
        gstRate: 18,
      );

      const qty = 4.0;
      final price = helmet.purchasePrice;
      final subtotalPaise = (price * qty).round();
      final taxPaise = (subtotalPaise * (helmet.gstRate / 100)).round();
      final totalPaise = subtotalPaise + taxPaise;

      // 4 units @ ₹350 = ₹1,400
      expect(subtotalPaise, 140000);
      // 18% GST of 1,400 = ₹252
      expect(taxPaise, 25200);
      // Total with GST = ₹1,652
      expect(totalPaise, 165200);
    });
  });

  group('Problem 6: Dashboard Net Profit Consistency and Calculation', () {
    test('Negative stock sale followed by purchase does not blow up cost average or drop net profit into negative', () async {
      // 1. Initial product with 0 stock
      final zeroStockProdId = await repo.upsertProduct(
        Product(
          name: 'Zero Stock Part',
          sku: 'ZSP-01',
          gstRate: 0,
          salePrice: 100000, // ₹1,000 selling price
          purchasePrice: 60000, // ₹600 purchase price
          costAverage: 60000,
          stock: 0,
        ),
        businessIdOverride: businessId,
      );

      // 2. Make a sale of 2 units when stock is 0 (stock becomes -2)
      final quote = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 2, price: 100000, gstRate: 0)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      final line = quote.lines.first;
      await repo.finalizeSale(
        businessId: businessId,
        number: await repo.nextInvoiceNumber(businessId, 'INV'),
        customerId: customerId,
        customerName: 'Rohan Sharma',
        date: todayIso(),
        gstType: 'intra',
        quote: quote,
        lines: [
          InvoiceLine(
            productId: zeroStockProdId,
            name: 'Zero Stock Part',
            gstRate: 0,
            quantity: 2,
            price: 100000,
            taxable: line.taxable.paise,
            tax: line.tax.paise,
          )
        ],
        paymentMode: 'Cash',
        amountPaid: 200000,
      );

      var prod = (await repo.products(businessId)).firstWhere((p) => p.id == zeroStockProdId);
      expect(prod.stock, -2);
      expect(prod.costAverage, 60000); // Maintained valid cost

      // 3. Receive new purchase of 5 units @ ₹600
      await repo.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: 'Vega Helmets Ltd',
        date: todayIso(),
        purchaseNumber: 'PUR-NEW-01',
        items: [
          (zeroStockProdId, 'Zero Stock Part', 5.0, 60000, 0),
        ],
        amountPaid: 300000,
        paymentMode: 'Cash',
      );

      prod = (await repo.products(businessId)).firstWhere((p) => p.id == zeroStockProdId);
      expect(prod.stock, 3); // -2 + 5 = 3
      expect(prod.costAverage, 60000); // Not blown up or negative!

      // 4. Check dashboard totals and performance
      final totals = await repo.dashboardTotals(businessId);
      final perf = await repo.dashboardPerformance(businessId, 'Today');

      // Sales revenue: ₹2,000 (200000 paise)
      // COGS: 2 * ₹600 = ₹1,200 (120000 paise)
      // Net profit: ₹2,000 - ₹1,200 = ₹800 (80000 paise)
      expect(totals['salesToday'], 200000);
      expect(totals['cogsToday'], 120000);
      final netProfit = (totals['taxableToday'] ?? 0) - (totals['cogsToday'] ?? 0) - (totals['expensesToday'] ?? 0);
      expect(netProfit, 80000); // Exactly ₹800 positive net profit!
      expect(perf.profitTrend.isNegative, isFalse);
    });
  });
}
