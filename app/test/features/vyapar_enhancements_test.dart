import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/core/units.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/reports/cashflow_report_screen.dart';
import 'package:billket/features/reports/date_filter_bar.dart';
import 'package:billket/features/reports/pl_report_screen.dart';
import 'package:billket/features/reports/stock_summary_report_screen.dart';

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
      name: 'Trade Enterprise',
      ownerName: 'Vyapar Trader',
      taxRegistered: true,
    ));
    session = repo.session;
    session.businessId = businessId;
  });

  tearDown(() async {
    AppDatabase.instance.resetConnection();
    await db.close();
  });

  Widget wrapWithSession(Widget child) {
    return ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        home: child,
      ),
    );
  }

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

  group('Task 1: Global Date Filter Enhancement', () {
    testWidgets('GlobalDateFilterBar renders preset chips and Custom Range button', (tester) async {
      DateTime? changedStart;
      DateTime? changedEnd;
      String? changedLabel;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalDateFilterBar(
              selectedPeriod: 'This Month',
              onRangeChanged: (start, end, label) {
                changedStart = start;
                changedEnd = end;
                changedLabel = label;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('This Year'), findsOneWidget);
      expect(find.text('Custom Range'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);

      // Select 'Today' preset
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(changedLabel, 'Today');
      expect(changedStart, isNotNull);
      expect(changedEnd, isNotNull);
      expect(changedStart, changedEnd);
    });

    testWidgets('PLReportScreen integrates GlobalDateFilterBar and displays P&L metrics', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Seed some invoice and expense data
      await tester.runAsync(() async {
        await repo.upsertCustomer(
          Customer(name: 'Client A', phone: '1234567890'),
          businessIdOverride: businessId,
        );
        await db.insert('invoices', {
          'business_id': businessId,
          'number': 'INV-0001',
          'customer_name': 'Client A',
          'date': '2026-10-01',
          'taxable': 100000,
          'cgst': 9000,
          'sgst': 9000,
          'igst': 0,
          'total': 118000,
          'amount_paid': 118000,
          'status': 'Paid',
        });
        await repo.recordExpense(
          businessId: businessId,
          category: 'Rent',
          amount: 20000, // Rs 200
          mode: 'Cash',
          date: '2026-10-02',
          description: 'Office Rent',
        );
      });

      await tester.pumpWidget(wrapWithSession(const PLReportScreen()));
      await pumpUntilLoaded(tester);

      // Check GlobalDateFilterBar is present at top
      expect(find.byType(GlobalDateFilterBar), findsOneWidget);
      expect(find.text('Income Statement (P&L)'), findsOneWidget);
      expect(find.text('Operating Revenue'), findsOneWidget);
      expect(find.text('Operating Expenses'), findsOneWidget);
      expect(find.text('NET PROFIT'), findsOneWidget);
    });
  });

  group('Task 2: Stock Summary Report Updates', () {
    testWidgets('StockSummaryReportScreen has valuation toggle, updates formulas, and has Excel export button', (tester) async {
      await tester.runAsync(() async {
        await repo.upsertProduct(
          Product(
            name: 'Steel Rods',
            unit: 'TON',
            stock: 10,
            purchasePrice: 4000000, // Rs 40,000 / TON
            salePrice: 5000000, // Rs 50,000 / TON
            costAverage: 4000000,
          ),
          businessIdOverride: businessId,
        );
      });

      await tester.pumpWidget(wrapWithSession(const StockSummaryReportScreen()));
      await pumpUntilLoaded(tester);

      // Verify Valuation Toggle exists at top
      expect(find.text('Valuation:'), findsOneWidget);
      expect(find.text('Cost Price'), findsOneWidget);
      expect(find.text('Sale Price'), findsOneWidget);

      // Verify dedicated Excel export button in AppBar
      expect(find.byTooltip('Export to Excel (.xlsx)'), findsOneWidget);

      // Initial Valuation is Cost Price (10 * 40,000 = 400,000 -> Rs 4,00,000.00)
      expect(find.text('Total Inventory Value (Cost)'), findsOneWidget);
      expect(find.text('Stock Value (Cost)'), findsOneWidget);

      // Toggle to Sale Price
      await tester.tap(find.text('Sale Price'));
      await tester.pumpAndSettle();

      // Should now show Total Inventory Value (Sale) and Stock Value (Sale)
      expect(find.text('Total Inventory Value (Sale)'), findsOneWidget);
      expect(find.text('Stock Value (Sale)'), findsOneWidget);
    });
  });

  group('Task 3: Vyapar-Style Cash Flow Statement', () {
    testWidgets('CashflowReportScreen renders 4 summary cards, account filter, tabs, and rows', (tester) async {
      await tester.runAsync(() async {
        // 1. Transaction strictly preceding active filter (Preceding date: 2026-09-15) -> Opening Cash
        await db.insert('ledger', {
          'business_id': businessId,
          'date': '2026-09-15',
          'account': 'cash',
          'debit': 50000, // +Rs 500
          'credit': 0,
          'ref_type': 'opening',
          'note': 'Initial Cash Reserve',
        });

        // 2. Transaction within period (Money In: 2026-10-05)
        final pInId = await db.insert('payments', {
          'business_id': businessId,
          'party_type': 'customer',
          'party_id': 1,
          'party_name': 'Sharma Traders',
          'amount': 30000, // +Rs 300
          'mode': 'Cash',
          'date': '2026-10-05',
          'type': 'in',
        });
        await db.insert('ledger', {
          'business_id': businessId,
          'date': '2026-10-05',
          'account': 'cash',
          'debit': 30000,
          'credit': 0,
          'ref_type': 'payment',
          'ref_id': pInId,
          'note': 'Receipt from Sharma Traders',
        });

        // 3. Transaction within period (Money Out: 2026-10-06)
        final expId = await db.insert('expenses', {
          'business_id': businessId,
          'category': 'Transport',
          'amount': 10000, // -Rs 100
          'mode': 'Cash',
          'date': '2026-10-06',
          'vendor': 'City Cargo',
        });
        await db.insert('ledger', {
          'business_id': businessId,
          'date': '2026-10-06',
          'account': 'cash',
          'debit': 0,
          'credit': 10000,
          'ref_type': 'expense',
          'ref_id': expId,
          'note': 'Freight charge',
        });
      });

      // Query repository directly to test business logic
      await tester.runAsync(() async {
        final data = await repo.getCashflowReport(
          businessId,
          accountType: 'all',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 31),
        );

        // Opening cash = 50,000 paise (Rs 500)
        expect(data.openingCash, 50000);
        // Money in = 30,000 paise (Rs 300)
        expect(data.moneyIn, 30000);
        // Money out = 10,000 paise (Rs 100)
        expect(data.moneyOut, 10000);
        // Closing cash = Opening (50,000) + Money In (30,000) - Money Out (10,000) = 70,000 paise (Rs 700)
        expect(data.closingCash, 70000);

        expect(data.moneyInList.length, 1);
        expect(data.moneyInList.first.partyName, 'Sharma Traders');
        expect(data.moneyInList.first.transactionType, 'Sales');

        expect(data.moneyOutList.length, 1);
        expect(data.moneyOutList.first.partyName, 'City Cargo');
        expect(data.moneyOutList.first.transactionType, 'Expense');
      });

      // Pump the UI
      await tester.pumpWidget(wrapWithSession(const CashflowReportScreen()));
      await pumpUntilLoaded(tester);

      // Verify Header Summary Cards
      expect(find.text('Opening Cash'), findsOneWidget);
      expect(find.text('Money In (+)'), findsOneWidget);
      expect(find.text('Money Out (-)'), findsOneWidget);
      expect(find.text('Closing Cash'), findsOneWidget);

      // Verify Account Dropdown Filter exists
      expect(find.text('All Accounts'), findsOneWidget);

      // Verify Tabs: Money In & Money Out
      expect(find.textContaining('Money In'), findsWidgets);
      expect(find.textContaining('Money Out'), findsWidgets);

      // Check transaction rows in active tab (Money In)
      expect(find.text('Sharma Traders'), findsOneWidget);

      // Switch to Money Out tab
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();

      expect(find.text('City Cargo'), findsOneWidget);
    });
  });

  group('Task 4: Expand Measurement Units in Item Master', () {
    test('Industrial and trade units are present and matched correctly', () {
      final tradeUnits = [
        ('bag', 'BAG'),
        ('bundle', 'BDL'),
        ('roll', 'ROL'),
        ('sheet', 'SHT'),
        ('tin', 'TIN'),
        ('ton', 'TON'),
        ('quintal', 'QTL'),
        ('cft', 'CFT'),
      ];

      for (final (input, expectedCode) in tradeUnits) {
        final matched = matchAppUnit(input);
        expect(matched, isNotNull, reason: 'Failed to match $input');
        expect(matched!.code, expectedCode);
      }
    });

    test('Saving product with trade units persists cleanly to SQLite database', () async {
      for (final code in ['BAG', 'BDL', 'ROL', 'SHT', 'TIN', 'TON', 'QTL', 'CFT']) {
        final prodId = await repo.upsertProduct(
          Product(
            name: 'Item in $code',
            unit: code,
            stock: 50,
            purchasePrice: 10000,
            salePrice: 15000,
          ),
          businessIdOverride: businessId,
        );

        final prods = await repo.products(businessId);
        final loaded = prods.firstWhere((p) => p.id == prodId);
        expect(loaded, isNotNull);
        expect(loaded.unit, code);
      }
    });
  });
}
