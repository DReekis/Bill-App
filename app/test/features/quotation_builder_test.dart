import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/customers/party_form.dart';
import 'package:billket/features/inventory/multi_product_picker_sheet.dart';
import 'package:billket/features/sales/quotation_builder_screen.dart';
import 'package:billket/l10n/app_localizations.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
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
      name: 'Tech Traders',
      state: 'Karnataka',
      taxRegistered: true,
    ));
    session = repo.session;
    session.businessId = businessId;

    // Seed a customer and two products
    await repo.upsertCustomer(
      Customer(name: 'Client Alpha', phone: '9988776655', state: 'Karnataka'),
      businessIdOverride: businessId,
    );
    await repo.upsertProduct(
      Product(name: 'Monitor 4K', salePrice: 2000000, gstRate: 18, unit: 'pc'),
      businessIdOverride: businessId,
    );
    await repo.upsertProduct(
      Product(name: 'Wireless Mouse', salePrice: 150000, gstRate: 18, unit: 'pc'),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    AppDatabase.instance.resetConnection();
  });

  Widget buildTestWidget() {
    return ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuotationBuilderScreen(businessId: businessId),
      ),
    );
  }

  testWidgets('QuotationBuilderScreen renders inline Add Customer button and Add Items', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Verify AppBar
    expect(find.text('New Estimate'), findsOneWidget);

    // Verify Client/Customer header and Inline Add Customer button
    expect(find.text('CLIENT / CUSTOMER'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget); // Inline Add button next to dropdown
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);

    // Verify Items section and Add Items button
    expect(find.text('ITEMS (0)'), findsOneWidget);
    expect(find.text('Add Items'), findsOneWidget);

    // Verify Empty State
    expect(find.text('No items added to estimate'), findsOneWidget);
    expect(find.text('Check off multiple products at once with bulk addition.'), findsOneWidget);
    expect(find.text('Save Estimate'), findsOneWidget);
  });

  testWidgets('Tapping inline Add Customer opens CustomerFormSheet without resetting draft', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Tap "+ Add" customer button
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Customer / Party sheet should be open
    expect(find.byType(PartyFormSheet), findsOneWidget);

    // Dismiss the bottom sheet
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Back on estimate builder
    expect(find.text('New Estimate'), findsOneWidget);
  });

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      if (find.text('Loading clients...').evaluate().isEmpty) {
        break;
      }
    }
  }

  testWidgets('Bulk item picker allows selection and merges duplicates', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await pumpUntilLoaded(tester);

    // Open item picker
    await tester.tap(find.text('Add Items'));
    await tester.pumpAndSettle();


    expect(find.text('Select Estimate Items'), findsOneWidget);
    expect(find.text('Monitor 4K'), findsWidgets);
    expect(find.text('Wireless Mouse'), findsWidgets);

    // Bulk select all products via "Select All"
    await tester.tap(find.text('Select All'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Tap "Add to Estimate" button in bottom bar
    await tester.tap(find.textContaining('Add to Estimate'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Verify items are in the draft
    expect(find.text('ITEMS (2)'), findsOneWidget);
    expect(find.text('Monitor 4K'), findsOneWidget);
    expect(find.text('Wireless Mouse'), findsOneWidget);

    // Now open picker AGAIN to select "Monitor 4K"
    await tester.tap(find.text('Add Items'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Tap "Add" button for Monitor 4K inside the picker sheet
    await tester.tap(find.descendant(of: find.byType(MultiProductPickerSheet), matching: find.text('Add')).first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Submit selection
    await tester.tap(find.textContaining('Add to Estimate'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // MUST NOT create a duplicate row for Monitor 4K!
    // Items count should STILL be 2, and Monitor 4K should have quantity auto-incremented to 2 pc!
    expect(find.text('ITEMS (2)'), findsOneWidget);
    expect(find.text('2 pc'), findsOneWidget); // Monitor 4K quantity is 2 pc!

    // Pump past the 3-second showAppMessage timers
    await tester.pump(const Duration(seconds: 4));
  });
}


