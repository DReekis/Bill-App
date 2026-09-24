import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      name: 'Alpha Traders',
      state: 'Maharashtra',
      taxRegistered: true,
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  test('finalizeQuotation successfully saves estimate without DatabaseException', () async {
    final customerId = await repo.upsertCustomer(
      Customer(name: 'Acme Corp', phone: '9876543210', state: 'Maharashtra'),
      businessIdOverride: businessId,
    );

    final biz = await repo.getBusiness(businessId);
    expect(biz, isNotNull);

    // 2. Create products
    final prod1Id = await repo.upsertProduct(
      Product(name: 'Widget A', sku: 'WA-01', salePrice: 15000, gstRate: 18, unit: 'pcs'),
      businessIdOverride: businessId,
    );
    final prod2Id = await repo.upsertProduct(
      Product(name: 'Widget B', sku: 'WB-02', salePrice: 25000, gstRate: 12, unit: 'box'),
      businessIdOverride: businessId,
    );

    final prods = await repo.products(businessId);
    expect(prods.length, 2);

    // 3. Build quotation with proforma, discounts, and units
    final quote = Quotation(
      businessId: businessId,
      number: 'EST-TEST-001',
      customerId: customerId,
      customerName: 'Acme Corp',
      date: todayIso(),
      subtotal: 40000,
      taxable: 40000,
      cgst: 3100,
      sgst: 3100,
      igst: 0,
      total: 46200,
      status: 'Open',
      isProforma: false,
      notes: 'Estimate valid for 15 days',
      lines: [
        InvoiceLine(
          productId: prod1Id,
          name: 'Widget A',
          quantity: 1,
          price: 15000,
          gstRate: 18,
          discountPercent: 0,
          taxable: 15000,
          tax: 2700,
          unit: 'pcs',
        ),
        InvoiceLine(
          productId: prod2Id,
          name: 'Widget B',
          quantity: 1,
          price: 25000,
          gstRate: 12,
          discountPercent: 5,
          taxable: 23750,
          tax: 2850,
          unit: 'box',
        ),
      ],
    );

    // 4. Save quotation - MUST NOT throw DatabaseException
    final quoteId = await repo.finalizeQuotation(quote);
    expect(quoteId, greaterThan(0));

    // 5. Query saved quotation and its lines
    final retrieved = await repo.quotation(businessId, quoteId);
    expect(retrieved, isNotNull);
    expect(retrieved!.number, 'EST-TEST-001');
    expect(retrieved.customerId, customerId);
    expect(retrieved.customerName, 'Acme Corp');
    expect(retrieved.total, 46200);
    expect(retrieved.lines.length, 2);
    expect(retrieved.lines[0].name, 'Widget A');
    expect(retrieved.lines[0].unit, 'pcs');
    expect(retrieved.lines[1].name, 'Widget B');
    expect(retrieved.lines[1].unit, 'box');
  });

  test('item deduplication logic merges duplicate items and auto-increments quantity', () {
    // Model test of the exact deduplication algorithm used in QuotationBuilderScreen
    final lines = <InvoiceLine>[];

    void addOrMerge(Product product, double qty, int price) {
      final existingIndex = lines.indexWhere((l) =>
          (l.productId != null && product.id != null && l.productId == product.id) ||
          (l.name.trim().toLowerCase() == product.name.trim().toLowerCase() &&
              l.name.trim().isNotEmpty));

      if (existingIndex >= 0) {
        lines[existingIndex].quantity += qty;
        lines[existingIndex].price = price;
      } else {
        lines.add(InvoiceLine(
          productId: product.id,
          name: product.name,
          quantity: qty,
          price: price,
          unit: product.unit,
          gstRate: product.gstRate,
        ));
      }
    }

    final p1 = Product(id: 101, name: 'Steel Rod', salePrice: 50000, unit: 'kg');
    final p2 = Product(id: 102, name: 'Cement Bag', salePrice: 38000, unit: 'bag');

    // Add p1 with qty 2
    addOrMerge(p1, 2, p1.salePrice);
    expect(lines.length, 1);
    expect(lines.first.quantity, 2);

    // Add p2 with qty 5
    addOrMerge(p2, 5, p2.salePrice);
    expect(lines.length, 2);

    // Accidentally select p1 again with qty 3
    addOrMerge(p1, 3, p1.salePrice);

    // Should NOT create duplicate line item. Instead, merges and increments qty to 2 + 3 = 5!
    expect(lines.length, 2);
    expect(lines.first.name, 'Steel Rod');
    expect(lines.first.quantity, 5);

    // Accidentally select product with same name without ID (or re-scanned)
    final p1Duplicate = Product(name: 'steel rod ', salePrice: 52000, unit: 'kg');
    addOrMerge(p1Duplicate, 2, 52000);

    // Should merge by normalized name and increment qty to 5 + 2 = 7!
    expect(lines.length, 2);
    expect(lines.first.quantity, 7);
    expect(lines.first.price, 52000);
  });

  test('quotationsForParty retrieves only quotations for the target customer with lines', () async {
    final c1 = await repo.upsertCustomer(
      Customer(name: 'Party Alpha', phone: '9000000001'),
      businessIdOverride: businessId,
    );
    final c2 = await repo.upsertCustomer(
      Customer(name: 'Party Beta', phone: '9000000002'),
      businessIdOverride: businessId,
    );

    final q1Id = await repo.finalizeQuotation(Quotation(
      businessId: businessId,
      number: 'EST-A1',
      customerId: c1,
      customerName: 'Party Alpha',
      date: '2026-09-20',
      subtotal: 10000,
      taxable: 10000,
      total: 10000,
      status: 'Open',
      lines: [
        InvoiceLine(name: 'Service A', quantity: 1, price: 10000),
      ],
    ));

    await repo.finalizeQuotation(Quotation(
      businessId: businessId,
      number: 'EST-A2',
      customerId: c1,
      customerName: 'Party Alpha',
      date: '2026-09-21',
      subtotal: 20000,
      taxable: 20000,
      total: 20000,
      status: 'Open',
      lines: [
        InvoiceLine(name: 'Service B', quantity: 2, price: 10000),
      ],
    ));

    await repo.finalizeQuotation(Quotation(
      businessId: businessId,
      number: 'EST-B1',
      customerId: c2,
      customerName: 'Party Beta',
      date: '2026-09-22',
      subtotal: 30000,
      taxable: 30000,
      total: 30000,
      status: 'Open',
      lines: [
        InvoiceLine(name: 'Service C', quantity: 3, price: 10000),
      ],
    ));

    // Fetch for c1
    final c1Quotes = await repo.quotationsForParty(businessId, c1);
    expect(c1Quotes.length, 2);
    expect(c1Quotes.map((q) => q.number).toList(), containsAll(['EST-A1', 'EST-A2']));
    expect(c1Quotes.firstWhere((q) => q.number == 'EST-A1').lines.length, 1);
    expect(c1Quotes.firstWhere((q) => q.number == 'EST-A1').lines.first.name, 'Service A');

    // Fetch for c2
    final c2Quotes = await repo.quotationsForParty(businessId, c2);
    expect(c2Quotes.length, 1);
    expect(c2Quotes.first.number, 'EST-B1');

    // Test deleteQuotation
    await repo.deleteQuotation(businessId, q1Id);
    final afterDeleteQuotes = await repo.quotationsForParty(businessId, c1);
    expect(afterDeleteQuotes.length, 1);
    expect(afterDeleteQuotes.first.number, 'EST-A2');
  });
}

