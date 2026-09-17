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

  test('Bank accounts creation, updates, and Cash & Bank Summary balances', () async {
    final bank1Id = await repo.upsertBankAccount(BankAccount(
      bankName: 'HDFC Bank',
      accountName: 'Sharma Electronics',
      accountNumber: '5010048291024',
      ifsc: 'HDFC0001234',
      accountType: 'Current',
      openingBalance: 5000000, // ₹50,000
    ));

    final bank2Id = await repo.upsertBankAccount(BankAccount(
      bankName: 'ICICI Bank',
      accountName: 'Sharma Electronics',
      accountNumber: '1029482910',
      ifsc: 'ICIC0000012',
      accountType: 'Current',
      openingBalance: 2500000, // ₹25,000
    ));

    expect(bank1Id, greaterThan(0));
    expect(bank2Id, greaterThan(0));

    // Transfer ₹10,000 from HDFC to ICICI
    await repo.recordTransfer(
      fromAccount: 'bank:$bank1Id',
      toAccount: 'bank:$bank2Id',
      amount: 1000000,
      date: isoDate(DateTime.now()),
      note: 'Fund balance transfer',
    );

    final summary = await repo.getCashAndBankSummary(businessId);
    expect(summary.accounts.length, 2);

    final hdfc = summary.accounts.firstWhere((a) => a.account.id == bank1Id);
    final icici = summary.accounts.firstWhere((a) => a.account.id == bank2Id);

    // HDFC was 50k, transfer out 10k => 40k
    expect(hdfc.currentBalance, 4000000);
    // ICICI was 25k, transfer in 10k => 35k
    expect(icici.currentBalance, 3500000);
    // Total bank balance remains 75k
    expect(summary.totalBankBalance, 7500000);
  });

  test('Cheque lifecycle and atomic double-entry ledger reversals on bounce', () async {
    final custId = await repo.upsertCustomer(Customer(
      name: 'Pooja Textiles',
      openingBalance: 2000000, // Customer owes ₹20,000
    ));

    final bankId = await repo.upsertBankAccount(BankAccount(
      bankName: 'State Bank of India',
      accountNumber: '3029102938',
      openingBalance: 10000000, // ₹1,00,000
    ));

    // 1. Record Inward Cheque from Customer (₹20,000)
    final chqId = await repo.upsertCheque(Cheque(
      businessId: businessId,
      chequeNumber: '000842',
      bankAccountId: bankId,
      partyType: 'customer',
      partyId: custId,
      partyName: 'Pooja Textiles',
      amount: 2000000, // ₹20,000
      date: isoDate(DateTime.now()),
      type: 'inward',
      status: 'Pending',
    ));

    var summary = await repo.getCashAndBankSummary(businessId);
    expect(summary.pendingChequesInward, 2000000);

    // 2. Mark Cheque as Cleared
    await repo.updateChequeStatus(chqId, 'Cleared', clearingDate: isoDate(DateTime.now()));

    summary = await repo.getCashAndBankSummary(businessId);
    expect(summary.pendingChequesInward, 0); // No longer pending

    // Bank balance should now be 1,00,000 + 20,000 = 1,20,000
    final sbi = summary.accounts.firstWhere((a) => a.account.id == bankId);
    expect(sbi.currentBalance, 12000000);

    // 3. Cheque Bounces! (Mark as Bounced)
    await repo.updateChequeStatus(
      chqId,
      'Bounced',
      bounceReason: 'Signature Mismatch',
    );

    summary = await repo.getCashAndBankSummary(businessId);
    final sbiAfterBounce = summary.accounts.firstWhere((a) => a.account.id == bankId);

    // Bank balance should be reversed back to ₹1,00,000!
    expect(sbiAfterBounce.currentBalance, 10000000);

    // Customer ledger should now have a debit of ₹20,000 (debt restored!)
    final customerLedger = await db.rawQuery(
      "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM ledger WHERE business_id = ? AND account = ?",
      [businessId, 'customer:$custId'],
    );
    final custDebt = customerLedger.first['balance'] as num;
    expect(custDebt, 2000000); // Customer owes ₹20,000 again!
  });

  test('accountLedger returns accurate chronological passbook entries', () async {
    final bankId = await repo.upsertBankAccount(BankAccount(
      bankName: 'Axis Bank',
      accountNumber: '912010048291024',
      openingBalance: 0,
    ));

    // 1. Transfer in ₹50,000 from cash to Axis Bank
    await repo.recordTransfer(
      fromAccount: 'cash',
      toAccount: 'bank:$bankId',
      amount: 5000000,
      date: '2026-09-01',
      note: 'Initial cash deposit',
    );

    // 2. Transfer out ₹12,000 from Axis Bank to cash
    await repo.recordTransfer(
      fromAccount: 'bank:$bankId',
      toAccount: 'cash',
      amount: 1200000,
      date: '2026-09-02',
      note: 'ATM cash withdrawal',
    );

    // Query passbook for Axis Bank
    final bankPassbook = await repo.accountLedger(businessId, 'bank:$bankId');
    expect(bankPassbook.length, 2);
    // Most recent first:
    expect(bankPassbook.first.credit, 1200000); // outflow
    expect(bankPassbook.last.debit, 5000000);  // inflow

    // Query passbook for Cash
    final cashPassbook = await repo.accountLedger(businessId, 'cash');
    expect(cashPassbook.length, 2);
  });
}

