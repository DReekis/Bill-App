import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/money.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/sales/invoice_builder_screen.dart';
import 'package:billket/utils/pdf_invoice.dart';

void main() {
  late Database db;
  late int businessId;
  late Session session;
  final repo = Repository.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);
    businessId = await repo.createBusiness(Business(
      name: 'Radhe Enterprises',
      state: 'Gujarat',
      taxRegistered: true,
      gstin: '24AAAAA0000A1Z5',
    ));
    session = repo.session;
    session.businessId = businessId;

    await repo.upsertProduct(
      Product(
        name: 'Item',
        salePrice: 12000, // Rs 120.00
        gstRate: 0,
        taxIncluded: false,
        unit: 'PCS',
      ),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    AppDatabase.instance.resetConnection();
    await db.close();
  });

  Future<void> pumpAsync(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Unit dropdown displays clean code without clipped brackets and GST 12% calculates properly', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: const MaterialApp(
          home: InvoiceBuilderScreen(),
        ),
      ),
    );
    await pumpAsync(tester);
    await tester.pumpAndSettle();

    // 1. Add product to bill
    final addProdBtn = find.widgetWithText(OutlinedButton, 'Add Product');
    expect(addProdBtn, findsOneWidget);
    await tester.tap(addProdBtn);
    await pumpAsync(tester);
    await tester.pumpAndSettle();

    // In MultiProductPickerSheet, tap checkbox to select it
    final checkbox = find.byType(Checkbox).first;
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    // Tap 'Add to Bill (1)' button
    final addToBillBtn = find.text('Add to Bill (1)');
    expect(addToBillBtn, findsOneWidget);
    await tester.tap(addToBillBtn);
    await tester.pumpAndSettle();

    // 2. Tap on the item tile to open _LineEditorSheet
    final itemTile = find.text('Item');
    expect(itemTile, findsOneWidget);
    await tester.tap(itemTile);
    await tester.pumpAndSettle();

    // 3. Edit Quantity to 4
    final qtyField = find.widgetWithText(TextField, '1');
    expect(qtyField, findsOneWidget);
    await tester.enterText(qtyField, '4');
    await tester.pumpAndSettle();

    // Verify unit dropdown exists and select BOX
    final unitDropdown = find.byKey(const ValueKey('unit-PCS'));
    expect(unitDropdown, findsOneWidget);
    await tester.tap(unitDropdown);
    await tester.pumpAndSettle();

    // Verify popup menu item shows code and full name cleanly: 'BOX  ·  Boxes'
    final boxOption = find.text('BOX  ·  Boxes').last;
    expect(boxOption, findsOneWidget);
    await tester.tap(boxOption);
    await tester.pumpAndSettle();

    // Check that selected item in closed field displays 'BOX' cleanly without brackets
    expect(find.text('BOX'), findsOneWidget);

    // 4. Change GST % to 12%
    final gstDropdown = find.byKey(const ValueKey('edit-line-gst-0'));
    expect(gstDropdown, findsOneWidget);
    await tester.tap(gstDropdown);
    await tester.pumpAndSettle();

    final gst12 = find.text('12%').last;
    await tester.tap(gst12);
    await tester.pumpAndSettle();

    // Verify live calculation preview shows:
    // Taxable: ₹480, GST (12%): +₹57.60, Line Total: ₹537.60
    expect(find.text('Taxable: ₹480'), findsOneWidget);
    expect(find.text('GST (12%): +₹57.60 '), findsOneWidget);
    expect(find.text('₹537.60'), findsWidgets);

    // 5. Test Tax Mode toggle to 'Inc. GST (Incl. Tax)'
    final inclTaxToggle = find.text('Inc. GST (Incl. Tax)');
    expect(inclTaxToggle, findsOneWidget);
    await tester.tap(inclTaxToggle);
    await tester.pumpAndSettle();

    // In Inclusive mode: 4 * 120 = 480 total, Taxable = 428.57, Tax = 51.43
    expect(find.text('Taxable: ₹428.57'), findsOneWidget);
    expect(find.text('GST (12%): +₹51.43 (incl.)'), findsOneWidget);

    // Switch back to '+ GST (Excl. Tax)'
    final exclTaxToggle = find.text('+ GST (Excl. Tax)');
    expect(exclTaxToggle, findsOneWidget);
    await tester.tap(exclTaxToggle);
    await tester.pumpAndSettle();
    expect(find.text('Taxable: ₹480'), findsOneWidget);
    expect(find.text('GST (12%): +₹57.60 '), findsOneWidget);

    // 6. Tap Apply
    final applyBtn = find.widgetWithText(FilledButton, 'Apply');
    expect(applyBtn, findsOneWidget);
    await tester.tap(applyBtn);
    await tester.pumpAndSettle();

    // Verify item line tile shows updated unit 'BOX' and GST 12% and line total ₹537.60
    expect(find.text('4 BOX × ₹120  · GST 12%'), findsOneWidget);

    // Verify Grand Total in Bill card is ₹538 (₹537.60 rounded off +₹0.40)
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Taxable'), findsOneWidget);
    expect(find.text('CGST'), findsOneWidget);
    expect(find.text('SGST'), findsOneWidget);
    expect(find.text('₹28.80'), findsNWidgets(2)); // CGST 28.80, SGST 28.80
    expect(find.text('Round off'), findsOneWidget);
    expect(find.text('+₹0.40'), findsOneWidget);
    expect(find.text('Grand total'), findsOneWidget);
    expect(find.text('₹538'), findsWidgets);

    // Drain the 3-second showAppMessage timer
    await tester.pump(const Duration(seconds: 4));
  });

  test('End-to-End Invoice persistence with GST 12% and PDF generation', () async {
    // 1. Calculate Quote matching line item: 4 BOX @ ₹120.00, GST 12%
    final lineInput = LineCalcInput(
      quantity: 4,
      price: 12000,
      gstRate: 12,
      taxIncluded: false,
    );
    final quote = BillingEngine.calculateQuote(
      lines: [lineInput],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: true,
      businessState: 'Gujarat',
      customerState: 'Gujarat',
    );

    expect(quote.taxable.paise, 48000);
    expect(quote.cgst.paise, 2880);
    expect(quote.sgst.paise, 2880);
    expect(quote.roundOff.paise, 40);
    expect(quote.total.paise, 53800);

    // 2. Finalize sale into database
    final invId = await repo.finalizeSale(
      businessId: businessId,
      number: 'INV-2026-0001',
      customerId: null,
      customerName: 'Walk-in',
      date: '2026-10-14',
      gstType: 'intra',
      quote: quote,
      lines: [
        InvoiceLine(
          productId: 1,
          name: 'Item',
          hsn: '8471',
          gstRate: 12,
          quantity: 4,
          price: 12000,
          taxable: quote.lines[0].taxable.paise,
          tax: quote.lines[0].tax.paise,
          unit: 'BOX',
        ),
      ],
      amountPaid: quote.total.paise,
    );

    // 3. Verify retrieved invoice from database
    final saved = await repo.invoice(businessId, invId);
    expect(saved, isNotNull);
    expect(saved!.subtotal, 48000);
    expect(saved.taxable, 48000);
    expect(saved.cgst, 2880);
    expect(saved.sgst, 2880);
    expect(saved.igst, 0);
    expect(saved.roundOff, 40);
    expect(saved.total, 53800);

    // Check lines
    expect(saved.lines.length, 1);
    final l = saved.lines.first;
    expect(l.name, 'Item');
    expect(l.unit, 'BOX');
    expect(l.quantity, 4.0);
    expect(l.gstRate, 12);
    expect(l.taxable, 48000);
    expect(l.tax, 5760);

    // 4. Verify PDF generation retains GST breakdown and correct total
    final biz = (await repo.getBusiness(businessId))!;
    final pdfBytes = await buildDocumentPdf(
      business: biz,
      title: 'Tax Invoice',
      number: saved.number,
      date: saved.date,
      partyName: saved.customerName,
      lines: saved.lines,
      subtotal: saved.subtotal,
      discount: saved.discount,
      taxable: saved.taxable,
      igst: saved.igst,
      cgst: saved.cgst,
      sgst: saved.sgst,
      roundOff: saved.roundOff,
      total: saved.total,
      outstandingPaise: saved.outstanding.paise,
    );
    expect(pdfBytes.isNotEmpty, true);
    expect(pdfBytes.length, greaterThan(1000));
  });

  test('BillingEngine calculates quote with GST even if business is not initially marked tax registered', () {
    final quote = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(
          quantity: 4,
          price: 12000,
          gstRate: 12,
          taxIncluded: false,
        ),
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: false,
      gstEnabled: false,
      businessState: 'Gujarat',
      customerState: 'Gujarat',
    );

    expect(quote.taxable, const Money(48000));
    expect(quote.cgst, const Money(2880));
    expect(quote.sgst, const Money(2880));
    expect(quote.total, const Money(53800)); // ₹537.60 rounded off +0.40 = ₹538
  });

  test('BillingEngine calculates quote with Tax Included mode correctly', () {
    final quote = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(
          quantity: 4,
          price: 12000, // Rs 120 inclusive of 12% GST = Rs 480 total
          gstRate: 12,
          taxIncluded: true,
        ),
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
      businessTaxRegistered: true,
      gstEnabled: true,
      businessState: 'Gujarat',
      customerState: 'Gujarat',
    );

    // 480 * 100 / 112 = 428.57
    expect(quote.taxable, const Money(42857));
    expect(quote.cgst, const Money(2572));
    expect(quote.sgst, const Money(2571));
    expect(quote.taxTotal, const Money(5143));
    expect(quote.total, const Money(48000));
  });
}
