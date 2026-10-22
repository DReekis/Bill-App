import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/sales/invoice_builder_screen.dart';

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
      name: 'GST Test Traders',
      state: 'Maharashtra',
      taxRegistered: true,
    ));
    session = repo.session;
    session.businessId = businessId;
  });

  tearDown(() async {
    AppDatabase.instance.resetConnection();
    await db.close();
  });

  testWidgets('Add Charge sheet supports typing amounts, percentage calculation, and inline editing', (tester) async {
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
    await tester.pumpAndSettle();

    // 1. In empty state, tap "Add Charge / TCS"
    final addChargeBtn = find.widgetWithText(OutlinedButton, 'Add Charge / TCS');
    expect(addChargeBtn, findsOneWidget);

    await tester.tap(addChargeBtn);
    await tester.pumpAndSettle();

    // 2. Verify Bottom Sheet opens with title, presets and mode toggle
    expect(find.text('Add Additional Charge / TCS'), findsOneWidget);
    expect(find.text('Fixed Amount (₹)'), findsOneWidget);
    expect(find.text('% Calculate from Amount'), findsOneWidget);

    // 3. Test entering an amount in Fixed mode
    final amountFinder = find.widgetWithText(TextField, 'Charge Amount (₹)');
    expect(amountFinder, findsOneWidget);

    await tester.enterText(amountFinder, '150.00');
    await tester.pumpAndSettle();
    expect(find.text('150.00'), findsOneWidget);

    // Test quick amount chip ₹200
    final chip200 = find.text('₹200');
    expect(chip200, findsOneWidget);
    await tester.tap(chip200);
    await tester.pumpAndSettle();
    expect(find.text('200'), findsOneWidget);

    // 4. Switch to Percentage calculation mode
    final percentModeBtn = find.text('% Calculate from Amount');
    await tester.tap(percentModeBtn);
    await tester.pumpAndSettle();

    // Verify Main Amount & Rate (%) fields are present
    final baseAmountFinder = find.widgetWithText(TextField, 'Main / Bill Amount (₹)');
    final rateFinder = find.widgetWithText(TextField, 'Rate (%)');
    expect(baseAmountFinder, findsOneWidget);
    expect(rateFinder, findsOneWidget);

    // Enter Main Amount = 50,000 and Rate = 0.1% (TCS)
    await tester.enterText(baseAmountFinder, '50000');
    await tester.enterText(rateFinder, '0.1');
    await tester.pumpAndSettle();

    // Verify calculated amount preview shows ₹50.00 (50000 * 0.1% = 50)
    expect(find.textContaining('Calculated: ₹50.00'), findsOneWidget);
    expect(find.text('50.00'), findsWidgets);

    // Tap quick chip 2.0%
    final chip2Pct = find.text('2.0%');
    expect(chip2Pct, findsOneWidget);
    await tester.tap(chip2Pct);
    await tester.pumpAndSettle();

    // 50,000 * 2% = ₹1,000.00
    expect(find.textContaining('Calculated: ₹1000.00'), findsOneWidget);

    // 5. Switch to TCS preset
    final tcsPresetChip = find.widgetWithText(ChoiceChip, 'TCS (Sec 206C)');
    await tester.tap(tcsPresetChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('TCS (Sec 206C) is treated as a statutory tax liability'), findsOneWidget);

    // Put Main Amount = 100,000 for TCS @ 0.1% = 100.00
    await tester.enterText(baseAmountFinder, '100000');
    await tester.enterText(rateFinder, '0.1');
    await tester.pumpAndSettle();
    expect(find.textContaining('Calculated: ₹100.00'), findsOneWidget);

    // 6. Submit the charge
    final submitBtn = find.widgetWithText(FilledButton, 'Add Charge');
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    // 7. Verify charge appears on invoice
    expect(find.text('Add Additional Charge / TCS'), findsNothing);
    expect(find.text('TCS (Tax Collected at Source)'), findsOneWidget);
    expect(find.text('Sec 206C'), findsOneWidget);
    expect(find.text('₹100'), findsWidgets);

    // 8. Test EDITING the charge by tapping it directly
    final chargeItem = find.text('TCS (Tax Collected at Source)');
    await tester.tap(chargeItem);
    await tester.pumpAndSettle();

    // Verify Edit sheet opened with existing values
    expect(find.text('Edit Additional Charge / TCS'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update Charge'), findsOneWidget);

    // Modify the final charge amount directly to 125.00
    final editAmountFinder = find.widgetWithText(TextField, 'Final Charge Amount (₹)');
    await tester.enterText(editAmountFinder, '125.00');
    await tester.pumpAndSettle();

    // Tap Update Charge
    final updateBtn = find.widgetWithText(FilledButton, 'Update Charge');
    await tester.tap(updateBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    // Verify updated amount is reflected on the invoice
    expect(find.text('Edit Additional Charge / TCS'), findsNothing);
    expect(find.text('₹125'), findsWidgets);
  });
}
