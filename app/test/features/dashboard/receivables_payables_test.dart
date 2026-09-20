import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/l10n/app_localizations.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late Session session;

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
      name: 'Agarwal Traders',
      state: 'Delhi',
      gstin: '07AAAAA0000A1Z5',
      taxRegistered: true,
      upiId: 'agarwal@upi',
    ));
    session = Session()..businessId = businessId;
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  test('receivablesSummary aggregates customer balances and overdue invoices', () async {
    // 1. Create a customer with opening balance of ₹5,000 (500000 paise)
    final custId = await repo.upsertCustomer(Customer(
      name: 'Rajesh Kumar',
      phone: '9876543210',
      openingBalance: 500000,
    ));

    // 2. Insert an overdue invoice of ₹3,000 for this customer
    final invId = await db.insert('invoices', {
      'business_id': businessId,
      'number': 'INV-101',
      'customer_id': custId,
      'customer_name': 'Rajesh Kumar',
      'date': '2026-09-01',
      'due_date': '2026-09-10', // Overdue
      'total': 300000,
      'amount_paid': 100000, // ₹2,000 pending
      'status': 'Partially Paid',
    });

    // Ledger entry for invoice
    await db.insert('ledger', {
      'business_id': businessId,
      'date': '2026-09-01',
      'account': 'customer:$custId',
      'debit': 300000,
      'credit': 100000,
      'ref_type': 'invoice',
      'ref_id': invId,
      'note': 'Invoice INV-101',
    });

    final summary = await repo.receivablesSummary(businessId);

    // Total receivable = 5,000 (opening balance) + 2,000 (invoice pending) = 7,000
    expect(summary.totalReceivable, 700000);
    expect(summary.partyCount, 1);
    expect(summary.overdueCount, 1);
    expect(summary.items.first.customerName, 'Rajesh Kumar');
    expect(summary.items.first.pendingInvoices.length, 1);
    expect(summary.items.first.pendingInvoices.first.isOverdue, true);
    expect(summary.items.first.pendingInvoices.first.pendingAmount, 200000);
  });

  test('receivablesSummary handles walk-in unassigned unpaid invoices', () async {
    // Insert an unpaid walk-in invoice
    await db.insert('invoices', {
      'business_id': businessId,
      'number': 'INV-WALK-01',
      'customer_id': null,
      'customer_name': 'Walk-in Sharma',
      'date': '2026-09-15',
      'due_date': '2026-09-18',
      'total': 150000,
      'amount_paid': 0,
      'status': 'Unpaid',
    });

    final summary = await repo.receivablesSummary(businessId);

    expect(summary.totalReceivable, 150000);
    expect(summary.partyCount, 1);
    expect(summary.items.first.customerName, 'Walk-in Sharma');
    expect(summary.items.first.balance, 150000);
  });

  test('payablesSummary aggregates supplier credit balances', () async {
    // Create a supplier with opening balance of ₹15,000 (1500000 paise)
    final suppId = await repo.upsertSupplier(Supplier(
      name: 'Tata Steel Dist',
      phone: '9123456780',
      openingBalance: 1500000,
    ));
    expect(suppId, greaterThan(0));

    final summary = await repo.payablesSummary(businessId);

    expect(summary.totalPayable, 1500000);
    expect(summary.partyCount, 1);
    expect(summary.items.first.supplierName, 'Tata Steel Dist');
    expect(summary.items.first.balance, 1500000);
  });

  test('payablesSummary returns 0 when no supplier balance exists', () async {
    final summary = await repo.payablesSummary(businessId);
    expect(summary.totalPayable, 0);
    expect(summary.partyCount, 0);
    expect(summary.items, isEmpty);
  });

  test('payablesSummary tracks credit and advance purchases with remaining balance', () async {
    final suppId = await repo.upsertSupplier(Supplier(
      name: 'ABC Wholesalers',
      phone: '9876543210',
      openingBalance: 0,
    ));

    // Owner buys goods: 10 items at ₹1,000 each = ₹10,000 total (1000000 paise).
    // Pays ₹3,000 (300000 paise) advance, leaving ₹7,000 balance due.
    await repo.createPurchase(
      businessId: businessId,
      supplierId: suppId,
      supplierName: 'ABC Wholesalers',
      date: '2026-09-20',
      items: [
        (null, 'Raw Cotton Bales', 10.0, 100000, 0), // 10 * ₹1000 = ₹10,000
      ],
      amountPaid: 300000, // ₹3,000 advance
      paymentMode: 'Advance',
      notes: 'Bill #PO-101 (Advance ₹3,000)',
    );

    final summary = await repo.payablesSummary(businessId);

    // Balance owed is total (10,000) - amountPaid (3,000) = ₹7,000 (700000 paise)
    expect(summary.totalPayable, 700000);
    expect(summary.partyCount, 1);
    expect(summary.items.first.supplierName, 'ABC Wholesalers');
    expect(summary.items.first.balance, 700000);
  });

  testWidgets('Cash flow summary row displays To Collect and To Pay cards with tap handlers', (tester) async {
    var tappedReceivables = false;
    var tappedPayables = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (ctx) {
                  return Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: const ValueKey('to_collect_card'),
                          onTap: () => tappedReceivables = true,
                          child: const Text('₹42,500\n5 parties'),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          key: const ValueKey('to_pay_card'),
                          onTap: () => tappedPayables = true,
                          child: const Text('₹18,200\n3 suppliers'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('₹42,500'), findsOneWidget);
    expect(find.textContaining('₹18,200'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('to_collect_card')));
    expect(tappedReceivables, isTrue);

    await tester.tap(find.byKey(const ValueKey('to_pay_card')));
    expect(tappedPayables, isTrue);
  });
}
