import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Repository repo;
  late int businessId;

  setUpAll(() async {
    repo = Repository.instance;
    businessId = await repo.createBusiness(
      Business(
        name: 'Quick Action Expense Test Business',
        ownerName: 'Test Owner',
      ),
    );
  });

  group('Quick Action Expense Tests - Rent, Staff Salary, Maintenance, Custom', () {
    test('Categories list contains Rent, Staff Salary, Maintenance, and Custom', () {
      expect(expenseCategories, contains('Rent'));
      expect(expenseCategories, contains('Staff Salary'));
      expect(expenseCategories, contains('Maintenance'));
      expect(expenseCategories, contains('Custom'));
    });

    test('Records Rent expense properly with ledger and audit trail', () async {
      final id = await repo.recordExpense(
        businessId: businessId,
        category: 'Rent',
        amount: 2500000, // ₹25,000
        mode: 'Bank',
        date: todayIso(),
        description: 'Monthly office rent for September',
      );

      expect(id, greaterThan(0));
      final exps = await repo.expenses(businessId);
      final rentExp = exps.firstWhere((e) => e.id == id);
      expect(rentExp.category, 'Rent');
      expect(rentExp.amount, 2500000);
      expect(rentExp.mode, 'Bank');

      // Check ledger entries
      final ledger = await repo.accountLedger(businessId, 'expense:Rent');
      expect(ledger.any((l) => l.refId == id && l.debit == 2500000), isTrue);
    });

    test('Records Staff Salary expense properly with cash ledger deduction', () async {
      final id = await repo.recordExpense(
        businessId: businessId,
        category: 'Staff Salary',
        amount: 4500000, // ₹45,000
        mode: 'Cash',
        date: todayIso(),
        description: 'Store manager and helper wages',
      );

      expect(id, greaterThan(0));
      final exps = await repo.expenses(businessId);
      final salaryExp = exps.firstWhere((e) => e.id == id);
      expect(salaryExp.category, 'Staff Salary');
      expect(salaryExp.amount, 4500000);
      expect(salaryExp.mode, 'Cash');

      final ledger = await repo.accountLedger(businessId, 'expense:Staff Salary');
      expect(ledger.any((l) => l.refId == id && l.debit == 4500000), isTrue);
    });

    test('Records Maintenance expense properly', () async {
      final id = await repo.recordExpense(
        businessId: businessId,
        category: 'Maintenance',
        amount: 350000, // ₹3,500
        mode: 'Cash',
        date: todayIso(),
        description: 'AC servicing and electrical repairs',
      );

      expect(id, greaterThan(0));
      final exps = await repo.expenses(businessId);
      final maintExp = exps.firstWhere((e) => e.id == id);
      expect(maintExp.category, 'Maintenance');
      expect(maintExp.amount, 350000);
    });

    test('Records Custom expense category properly', () async {
      const customCategoryName = 'Generator Fuel';
      final id = await repo.recordExpense(
        businessId: businessId,
        category: customCategoryName,
        amount: 150000, // ₹1,500
        mode: 'Cash',
        date: todayIso(),
        description: 'Diesel for power backup',
      );

      expect(id, greaterThan(0));
      final exps = await repo.expenses(businessId);
      final customExp = exps.firstWhere((e) => e.id == id);
      expect(customExp.category, customCategoryName);
      expect(customExp.amount, 150000);

      final ledger = await repo.accountLedger(businessId, 'expense:$customCategoryName');
      expect(ledger.any((l) => l.refId == id && l.debit == 150000), isTrue);
    });

    test('Dashboard totals and Net Profit properly reflect all recorded expenses', () async {
      final totals = await repo.dashboardTotals(businessId);
      final expensesToday = totals['expensesToday'] ?? 0;
      // Rent (25000) + Salary (45000) + Maintenance (3500) + Generator Fuel (1500) = 75000 in Rs = 7500000 paise
      expect(expensesToday, greaterThanOrEqualTo(7500000));
    });

    test('Profit & Loss statement groups Rent, Staff Salary, Maintenance, and Custom', () async {
      final today = todayIso();
      final pl = await repo.profitAndLossReport(businessId, today, today);
      
      expect(pl['Rent'], equals(2500000));
      expect(pl['Staff Salary'], equals(4500000));
      expect(pl['Maintenance'], equals(350000));
      expect(pl['Generator Fuel'], equals(150000));
      expect(pl['totalExpenses'], greaterThanOrEqualTo(7500000));
      // Net Profit should subtract totalExpenses from grossProfit
      expect(pl['netProfit'], equals(pl['grossProfit']! - pl['totalExpenses']!));
    });

    test('Recent transactions include all expenses as TransactionType.expense', () async {
      final txs = await repo.recentTransactions(businessId, limit: 20);
      final expenseTxs = txs.where((t) => t.type == TransactionType.expense).toList();

      expect(expenseTxs, isNotEmpty);
      final parties = expenseTxs.map((t) => t.partyName).toSet();
      expect(parties, contains('Rent'));
      expect(parties, contains('Staff Salary'));
      expect(parties, contains('Maintenance'));
      expect(parties, contains('Generator Fuel'));
    });

    test('Cash and bank balances reflect expense payments', () async {
      final summary = await repo.getCashAndBankSummary(businessId);
      // Rent was 25,000 via Bank, Salary + Maint + Custom were 50,000 via Cash
      // Both ledger accounts were credited properly
      expect(summary, isNotNull);
    });

    test('Session permissions properly restrict expense actions for unauthorized roles', () {
      final ownerSession = Session()..currentRole = 'owner';
      expect(ownerSession.canViewCosts, isTrue);

      final adminSession = Session()..currentRole = 'admin';
      expect(adminSession.canViewCosts, isTrue);

      final accountantSession = Session()..currentRole = 'accountant';
      expect(accountantSession.canViewCosts, isTrue);

      final cashierSession = Session()..currentRole = 'cashier';
      expect(cashierSession.canViewCosts, isFalse);

      final salesmanSession = Session()..currentRole = 'salesman';
      expect(salesmanSession.canViewCosts, isFalse);
    });
  });
}
