import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/orders/orders_screen.dart';
import 'package:billket/features/sales/delivery_challan_builder_screen.dart';
import 'package:billket/l10n/app_localizations.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late Business business;
  late int customerId;
  late int supplierId;
  late int productId;
  late Session session;

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
      name: 'Apex Logistics & Supplies',
      ownerName: 'Apex Owner',
      taxRegistered: true,
      termsChallan: 'Goods dispatched at consignee risk. Subject to verification.',
    ));
    business = (await repo.getBusiness(businessId))!;
    session = repo.session;
    session.businessId = businessId;

    customerId = await repo.upsertCustomer(
      Customer(
        name: 'Metro Retailers',
        phone: '9876543210',
        billingAddress: '101 Trade Center, Bangalore',
        shippingAddress: 'Warehouse B, Electronic City',
      ),
      businessIdOverride: businessId,
    );

    supplierId = await repo.upsertSupplier(
      Supplier(
        name: 'National Distributors',
        phone: '9123456789',
        address: '55 Industrial Estate',
      ),
      businessIdOverride: businessId,
    );

    productId = await repo.upsertProduct(
      Product(
        name: 'LED Panel 40W',
        salePrice: 120000,
        purchasePrice: 90000,
        stock: 100,
        unit: 'pc',
      ),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    AppDatabase.instance.resetConnection();
    await db.close();
  });

  Widget buildTestApp(Widget child) {
    return ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('Delivery Challan Protocol (BillBook Style)', () {
    test('Sequential numbering auto-increments for Delivery Challans', () async {
      final initialPeek = await repo.peekNextChallanNumber(businessId);
      expect(initialPeek, 'DC-0001');

      final challanId = await repo.finalizeDeliveryChallan(DeliveryChallan(
        businessId: businessId,
        number: initialPeek,
        customerId: customerId,
        customerName: 'Metro Retailers',
        date: todayIso(),
        vehicleNo: 'KA 01 AB 1234',
        transportDetails: 'VRL Express • LR-8849',
        address: 'Warehouse B, Electronic City',
        status: 'Pending',
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'LED Panel 40W',
            quantity: 10,
            price: 120000,
            unit: 'pc',
          ),
        ],
      ));
      expect(challanId, greaterThan(0));

      final nextPeek = await repo.peekNextChallanNumber(businessId);
      expect(nextPeek, 'DC-0002');
    });

    test('Delivery Challan linked to Invoice stores vehicle and retrieves accurately', () async {
      // 1. Create a sales invoice
      final quote = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 10, price: 120000, gstRate: 18)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );
      final line = quote.lines.first;
      final invoiceId = await repo.finalizeSale(
        businessId: businessId,
        number: 'INV-1001',
        customerId: customerId,
        customerName: 'Metro Retailers',
        date: todayIso(),
        gstType: 'intra',
        amountPaid: 0,
        quote: quote,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'LED Panel 40W',
            quantity: 10,
            price: 120000,
            taxable: line.taxable.paise,
            tax: line.tax.paise,
            unit: 'pc',
          ),
        ],
      );

      // 2. Create Delivery Challan for this invoice with vehicle number
      final challanNumber = await repo.nextChallanNumber(businessId);
      final challanId = await repo.finalizeDeliveryChallan(DeliveryChallan(
        businessId: businessId,
        number: challanNumber,
        customerId: customerId,
        customerName: 'Metro Retailers',
        date: todayIso(),
        invoiceId: invoiceId,
        invoiceNumber: 'INV-1001',
        vehicleNo: 'KA 04 MC 9988',
        transportDetails: 'BlueDart Logistics • LR-5544',
        address: 'Warehouse B, Electronic City',
        notes: 'Delivered in good condition',
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'LED Panel 40W',
            quantity: 10,
            price: 120000,
            unit: 'pc',
          ),
        ],
      ));

      // 3. Query challans for invoice
      final challans = await repo.deliveryChallansForInvoice(businessId, invoiceId);
      expect(challans.length, 1);
      final fetched = challans.first;
      expect(fetched.id, challanId);
      expect(fetched.number, challanNumber);
      expect(fetched.invoiceId, invoiceId);
      expect(fetched.invoiceNumber, 'INV-1001');
      expect(fetched.vehicleNo, 'KA 04 MC 9988');
      expect(fetched.transportDetails, 'BlueDart Logistics • LR-5544');
      expect(fetched.lines.length, 1);
      expect(fetched.lines.first.quantity, 10);
      expect(fetched.lines.first.unit, 'pc');

      // 4. Generate Delivery Challan PDF
      final pdfBytes = await buildDeliveryChallanPdf(
        business: business,
        challan: fetched,
      );
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('Orders Section & Builder Toggle (BillBook Style)', () {
    testWidgets('OrdersScreen renders Sale Orders and Purchase Orders tabs and KPIs', (tester) async {
      // Seed a sale order and purchase order
      await tester.runAsync(() async {
        await repo.finalizeSalesOrder(SalesOrder(
          businessId: businessId,
          number: 'SO-0001',
          customerId: customerId,
          customerName: 'Metro Retailers',
          date: todayIso(),
          total: 500000,
          status: 'Pending',
          lines: [
            InvoiceLine(name: 'LED Panel 40W', quantity: 5, price: 100000, unit: 'pc'),
          ],
        ));

        await repo.finalizePurchaseOrder(PurchaseOrder(
          businessId: businessId,
          number: 'PO-0001',
          supplierId: supplierId,
          supplierName: 'National Distributors',
          date: todayIso(),
          total: 450000,
          status: 'Pending',
          lines: [
            InvoiceLine(name: 'LED Panel 40W', quantity: 5, price: 90000, unit: 'pc'),
          ],
        ));
      });

      Future<void> pumpUntilLoaded(WidgetTester tester) async {
        for (int i = 0; i < 30; i++) {
          await tester.runAsync(() async {
            await Future.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(buildTestApp(const OrdersScreen()));
      await pumpUntilLoaded(tester);

      // Check AppBar and Tabs
      expect(find.text('Orders Hub'), findsOneWidget);
      expect(find.textContaining('Sale Orders (1)'), findsOneWidget);
      expect(find.textContaining('Purchase Orders (1)'), findsOneWidget);

      // Check KPIs
      expect(find.text('Total Orders'), findsOneWidget);
      expect(find.text('Total Value'), findsOneWidget);
      expect(find.text('Open / Pending'), findsWidgets);

      // Check Sale Order item card
      expect(find.text('SO-0001'), findsOneWidget);
      expect(find.text('Metro Retailers'), findsOneWidget);

      // Switch to Purchase Orders Tab
      await tester.tap(find.textContaining('Purchase Orders (1)'));
      await tester.pumpAndSettle();

      // Check Purchase Order item card
      expect(find.text('PO-0001'), findsOneWidget);
      expect(find.text('National Distributors'), findsOneWidget);
    });

    testWidgets('DeliveryChallanBuilderScreen initializes from Invoice with vehicle and address fields', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Future<void> pumpUntilLoaded(WidgetTester tester) async {
        for (int i = 0; i < 30; i++) {
          await tester.runAsync(() async {
            await Future.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();
      }

      final invoice = Invoice(
        id: 99,
        businessId: businessId,
        number: 'INV-9901',
        customerId: customerId,
        customerName: 'Metro Retailers',
        date: todayIso(),
        shipToAddress: 'Plot 42, Peenya Industrial Area',
        vehicleNumber: 'KA 05 CD 5678',
        lrRrNumber: 'VRL-7788',
        total: 240000,
        lines: [
          InvoiceLine(productId: productId, name: 'LED Panel 40W', quantity: 2, price: 120000, unit: 'pc'),
        ],
      );

      await tester.pumpWidget(buildTestApp(DeliveryChallanBuilderScreen(fromInvoice: invoice)));
      await pumpUntilLoaded(tester);

      // Verify header and banner
      expect(find.text('Create Delivery Challan'), findsOneWidget);
      expect(find.textContaining('Dispatching items for Invoice INV-9901'), findsOneWidget);

      // Verify Vehicle field and prefilled info
      expect(find.text('Vehicle Number *'), findsOneWidget);
      expect(find.text('KA 05 CD 5678'), findsOneWidget);
      expect(find.text('VRL-7788'), findsOneWidget);
      expect(find.text('Plot 42, Peenya Industrial Area'), findsOneWidget);

      // Verify item prefilled
      expect(find.text('LED Panel 40W'), findsOneWidget);
      expect(find.text('Generate Delivery Challan'), findsOneWidget);
    });
  });
}
