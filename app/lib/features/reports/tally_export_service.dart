import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/models.dart';
import '../../data/repositories.dart';

class TallyExportFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeSales;
  final bool includePurchases;
  final bool includeReceipts;
  final bool includePayments;
  final bool includeMasters;

  const TallyExportFilter({
    this.startDate,
    this.endDate,
    this.includeSales = true,
    this.includePurchases = true,
    this.includeReceipts = true,
    this.includePayments = true,
    this.includeMasters = true,
  });
}

class TallyExportSummary {
  final int salesCount;
  final int purchaseCount;
  final int receiptCount;
  final int paymentCount;
  final int ledgerCount;
  final int totalVouchers;
  final String xml;
  final File file;

  const TallyExportSummary({
    required this.salesCount,
    required this.purchaseCount,
    required this.receiptCount,
    required this.paymentCount,
    required this.ledgerCount,
    required this.totalVouchers,
    required this.xml,
    required this.file,
  });
}

class TallyExportService {
  TallyExportService._();
  static final TallyExportService instance = TallyExportService._();

  /// Escapes special XML characters
  static String xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Formats ISO date 'YYYY-MM-DD' into Tally 'YYYYMMDD'
  static String formatTallyDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    final cleaned = isoDate.split('T').first.replaceAll('-', '').trim();
    if (cleaned.length >= 8) {
      return cleaned.substring(0, 8);
    }
    return cleaned;
  }

  /// Converts paise to 2-decimal string
  static String formatRupees(int paise) {
    final abs = paise.abs();
    final d = abs / 100.0;
    return d.toStringAsFixed(2);
  }

  /// Generates the complete Tally Prime XML envelope and saves it to a file
  Future<TallyExportSummary> exportTallyXml({
    required int businessId,
    TallyExportFilter filter = const TallyExportFilter(),
    Directory? outputDir,
  }) async {
    final repo = Repository.instance;
    final business = await repo.getBusiness(businessId);
    final companyName = business?.name ?? 'BillApp Company';

    // 1. Fetch parties
    final customers = await repo.customers(businessId, includeInactive: false);
    final suppliers = await repo.suppliers(businessId, includeInactive: false);

    // 2. Fetch sales invoices
    final allInvoices = await repo.invoices(businessId);
    final filteredInvoices = <Invoice>[];
    if (filter.includeSales) {
      for (final inv in allInvoices) {
        if (_isDateInRange(inv.date, filter.startDate, filter.endDate)) {
          final fullInv = await repo.invoice(businessId, inv.id!);
          filteredInvoices.add(fullInv ?? inv);
        }
      }
    }

    // 3. Fetch purchases & expenses
    final allExpenses = await repo.expenses(businessId);
    final filteredPurchases = <Expense>[];
    final filteredExpensePayments = <Expense>[];
    for (final exp in allExpenses) {
      if (_isDateInRange(exp.date, filter.startDate, filter.endDate)) {
        if (exp.category == 'Purchase') {
          if (filter.includePurchases) filteredPurchases.add(exp);
        } else {
          if (filter.includePayments) filteredExpensePayments.add(exp);
        }
      }
    }

    // 4. Fetch payments (Receipts & Payments Out)
    final allPayments = await repo.payments(businessId);
    final filteredReceipts = <Payment>[];
    final filteredPaymentsOut = <Payment>[];
    for (final pay in allPayments) {
      if (_isDateInRange(pay.date, filter.startDate, filter.endDate)) {
        final isIn = pay.type == 'in' || pay.partyType == 'customer';
        if (isIn) {
          if (filter.includeReceipts) filteredReceipts.add(pay);
        } else {
          if (filter.includePayments) filteredPaymentsOut.add(pay);
        }
      }
    }

    // Build XML Content
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<ENVELOPE>');
    buffer.writeln('  <HEADER>');
    buffer.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buffer.writeln('  </HEADER>');
    buffer.writeln('  <BODY>');
    buffer.writeln('    <IMPORTDATA>');
    buffer.writeln('      <REQUESTDESC>');
    buffer.writeln('        <REPORTNAME>All Masters</REPORTNAME>');
    buffer.writeln('        <STATICVARIABLES>');
    buffer.writeln('          <SVCURRENTCOMPANY>${xmlEscape(companyName)}</SVCURRENTCOMPANY>');
    buffer.writeln('        </STATICVARIABLES>');
    buffer.writeln('      </REQUESTDESC>');
    buffer.writeln('      <REQUESTDATA>');

    int ledgerCount = 0;

    // A. Generate Master Ledgers
    if (filter.includeMasters) {
      // Core Accounting Ledgers
      final standardLedgers = [
        ('Sales Account', 'Sales Accounts'),
        ('Purchase Account', 'Purchase Accounts'),
        ('CGST', 'Duties & Taxes'),
        ('SGST', 'Duties & Taxes'),
        ('IGST', 'Duties & Taxes'),
        ('Round Off', 'Indirect Expenses'),
        ('Cash', 'Cash-in-Hand'),
        ('Bank Account', 'Bank Accounts'),
      ];

      for (final (name, parent) in standardLedgers) {
        buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
        buffer.writeln('          <LEDGER NAME="${xmlEscape(name)}" ACTION="Create">');
        buffer.writeln('            <NAME>${xmlEscape(name)}</NAME>');
        buffer.writeln('            <PARENT>${xmlEscape(parent)}</PARENT>');
        buffer.writeln('            <ISBILLWISEON>No</ISBILLWISEON>');
        buffer.writeln('            <AFFECTSSTOCK>No</AFFECTSSTOCK>');
        buffer.writeln('          </LEDGER>');
        buffer.writeln('        </TALLYMESSAGE>');
        ledgerCount++;
      }

      // Customer Ledgers (Sundry Debtors)
      for (final cust in customers) {
        buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
        buffer.writeln('          <LEDGER NAME="${xmlEscape(cust.name)}" ACTION="Create">');
        buffer.writeln('            <NAME>${xmlEscape(cust.name)}</NAME>');
        buffer.writeln('            <PARENT>Sundry Debtors</PARENT>');
        buffer.writeln('            <ISBILLWISEON>Yes</ISBILLWISEON>');
        buffer.writeln('            <AFFECTSSTOCK>No</AFFECTSSTOCK>');
        buffer.writeln('            <COUNTRYNAME>India</COUNTRYNAME>');
        if (cust.state != null && cust.state!.isNotEmpty) {
          buffer.writeln('            <LEDSTATENAME>${xmlEscape(cust.state!)}</LEDSTATENAME>');
        }
        if (cust.gstin != null && cust.gstin!.isNotEmpty) {
          buffer.writeln('            <PARTYGSTIN>${xmlEscape(cust.gstin!)}</PARTYGSTIN>');
        }
        buffer.writeln('          </LEDGER>');
        buffer.writeln('        </TALLYMESSAGE>');
        ledgerCount++;
      }

      // Supplier Ledgers (Sundry Creditors)
      for (final sup in suppliers) {
        buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
        buffer.writeln('          <LEDGER NAME="${xmlEscape(sup.name)}" ACTION="Create">');
        buffer.writeln('            <NAME>${xmlEscape(sup.name)}</NAME>');
        buffer.writeln('            <PARENT>Sundry Creditors</PARENT>');
        buffer.writeln('            <ISBILLWISEON>Yes</ISBILLWISEON>');
        buffer.writeln('            <AFFECTSSTOCK>No</AFFECTSSTOCK>');
        buffer.writeln('            <COUNTRYNAME>India</COUNTRYNAME>');
        if (sup.state != null && sup.state!.isNotEmpty) {
          buffer.writeln('            <LEDSTATENAME>${xmlEscape(sup.state!)}</LEDSTATENAME>');
        }
        if (sup.gstin != null && sup.gstin!.isNotEmpty) {
          buffer.writeln('            <PARTYGSTIN>${xmlEscape(sup.gstin!)}</PARTYGSTIN>');
        }
        buffer.writeln('          </LEDGER>');
        buffer.writeln('        </TALLYMESSAGE>');
        ledgerCount++;
      }
    }

    // B. Generate Sales Vouchers
    for (final inv in filteredInvoices) {
      final tDate = formatTallyDate(inv.date);
      final partyName = (inv.customerName != null && inv.customerName!.isNotEmpty)
          ? inv.customerName!
          : 'Cash Customer';
      final invNumber = inv.number;
      final totalPaise = inv.total;
      final taxablePaise = inv.taxable;
      final cgstPaise = inv.cgst;
      final sgstPaise = inv.sgst;
      final igstPaise = inv.igst;
      final roundOffPaise = inv.roundOff;

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Sales" ACTION="Create" OBJVIEW="Invoice Voucher View">');
      buffer.writeln('            <DATE>$tDate</DATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${xmlEscape(invNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <REFERENCE>${xmlEscape(invNumber)}</REFERENCE>');
      buffer.writeln('            <PARTYLEDGERNAME>${xmlEscape(partyName)}</PARTYLEDGERNAME>');
      buffer.writeln('            <PERSISTEDVIEW>Invoice Voucher View</PERSISTEDVIEW>');
      buffer.writeln('            <ISINVOICE>Yes</ISINVOICE>');
      buffer.writeln('            <NARRATION>Tax Invoice ${xmlEscape(invNumber)}</NARRATION>');

      // Party Ledger Entry (Debit in Tally is deemed positive, negative amount)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(partyName)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-${formatRupees(totalPaise)}</AMOUNT>');
      buffer.writeln('              <BILLALLOCATIONS.LIST>');
      buffer.writeln('                <NAME>${xmlEscape(invNumber)}</NAME>');
      buffer.writeln('                <BILLTYPE>New Ref</BILLTYPE>');
      buffer.writeln('                <AMOUNT>-${formatRupees(totalPaise)}</AMOUNT>');
      buffer.writeln('              </BILLALLOCATIONS.LIST>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Sales Ledger Entry (Credit)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>Sales Account</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>${formatRupees(taxablePaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // CGST Entry
      if (cgstPaise > 0) {
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>CGST</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>${formatRupees(cgstPaise)}</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');
      }

      // SGST Entry
      if (sgstPaise > 0) {
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>SGST</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>${formatRupees(sgstPaise)}</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');
      }

      // IGST Entry
      if (igstPaise > 0) {
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>IGST</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>${formatRupees(igstPaise)}</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');
      }

      // Round Off Entry
      if (roundOffPaise != 0) {
        final isDebit = roundOffPaise < 0;
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>Round Off</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>${isDebit ? "Yes" : "No"}</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>${isDebit ? "-" : ""}${formatRupees(roundOffPaise.abs())}</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');
      }

      // Inventory Item Entries
      for (final line in inv.lines) {
        final itemName = line.name.isNotEmpty ? line.name : 'Item';
        final qty = line.quantity > 0 ? line.quantity : 1.0;
        final unit = line.unit != null && line.unit!.isNotEmpty ? line.unit! : 'pcs';
        final lineAmt = (line.price * qty).round();

        buffer.writeln('            <ALLINVENTORYENTRIES.LIST>');
        buffer.writeln('              <STOCKITEMNAME>${xmlEscape(itemName)}</STOCKITEMNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <RATE>${formatRupees(line.price)}/$unit</RATE>');
        buffer.writeln('              <ACTUALQTY>$qty $unit</ACTUALQTY>');
        buffer.writeln('              <BILLEDQTY>$qty $unit</BILLEDQTY>');
        buffer.writeln('              <AMOUNT>${formatRupees(lineAmt)}</AMOUNT>');
        buffer.writeln('            </ALLINVENTORYENTRIES.LIST>');
      }

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    // C. Generate Purchase Vouchers
    for (final pur in filteredPurchases) {
      final tDate = formatTallyDate(pur.date);
      final supplierName = (pur.vendor != null && pur.vendor!.isNotEmpty)
          ? pur.vendor!
          : 'Supplier';
      final purNumber = 'PUR-${pur.id}';
      final amountPaise = pur.amount;

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Purchase" ACTION="Create">');
      buffer.writeln('            <DATE>$tDate</DATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Purchase</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${xmlEscape(purNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <REFERENCE>${xmlEscape(purNumber)}</REFERENCE>');
      buffer.writeln('            <PARTYLEDGERNAME>${xmlEscape(supplierName)}</PARTYLEDGERNAME>');
      buffer.writeln('            <NARRATION>Purchase Bill ${xmlEscape(purNumber)} - ${xmlEscape(pur.description ?? '')}</NARRATION>');

      // Supplier Credited (Positive in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(supplierName)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('              <BILLALLOCATIONS.LIST>');
      buffer.writeln('                <NAME>${xmlEscape(purNumber)}</NAME>');
      buffer.writeln('                <BILLTYPE>New Ref</BILLTYPE>');
      buffer.writeln('                <AMOUNT>${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('              </BILLALLOCATIONS.LIST>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Purchase Account Debited (Negative in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>Purchase Account</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    // D. Generate Receipt Vouchers (Payment In)
    for (final rcpt in filteredReceipts) {
      final tDate = formatTallyDate(rcpt.date);
      final partyName = (rcpt.partyName != null && rcpt.partyName!.isNotEmpty)
          ? rcpt.partyName!
          : 'Customer';
      final rcptNumber = (rcpt.reference != null && rcpt.reference!.isNotEmpty)
          ? rcpt.reference!
          : 'RCPT-${rcpt.id}';
      final cashBankLedger = rcpt.mode == 'Bank' ? 'Bank Account' : 'Cash';
      final amountPaise = rcpt.amount;

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Receipt" ACTION="Create">');
      buffer.writeln('            <DATE>$tDate</DATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Receipt</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${xmlEscape(rcptNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <PARTYLEDGERNAME>${xmlEscape(partyName)}</PARTYLEDGERNAME>');
      buffer.writeln('            <NARRATION>Payment received from ${xmlEscape(partyName)} - ${xmlEscape(rcpt.notes ?? '')}</NARRATION>');

      // Cash/Bank Debited (Negative in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(cashBankLedger)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Customer Credited (Positive in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(partyName)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    // E. Generate Payment Vouchers (Payment Out)
    for (final pay in filteredPaymentsOut) {
      final tDate = formatTallyDate(pay.date);
      final partyName = (pay.partyName != null && pay.partyName!.isNotEmpty)
          ? pay.partyName!
          : 'Supplier';
      final payNumber = (pay.reference != null && pay.reference!.isNotEmpty)
          ? pay.reference!
          : 'PAY-${pay.id}';
      final cashBankLedger = pay.mode == 'Bank' ? 'Bank Account' : 'Cash';
      final amountPaise = pay.amount;

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Payment" ACTION="Create">');
      buffer.writeln('            <DATE>$tDate</DATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Payment</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${xmlEscape(payNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <PARTYLEDGERNAME>${xmlEscape(partyName)}</PARTYLEDGERNAME>');
      buffer.writeln('            <NARRATION>Payment made to ${xmlEscape(partyName)} - ${xmlEscape(pay.notes ?? '')}</NARRATION>');

      // Supplier / Expense Debited (Negative in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(partyName)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Cash/Bank Credited (Positive in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(cashBankLedger)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    // F. Generate Expense Vouchers (Operating Expenses)
    for (final exp in filteredExpensePayments) {
      final tDate = formatTallyDate(exp.date);
      final expenseLedger = exp.category.isNotEmpty ? exp.category : 'General Expenses';
      final expNumber = 'EXP-${exp.id}';
      final cashBankLedger = exp.mode == 'Bank' ? 'Bank Account' : 'Cash';
      final amountPaise = exp.amount;

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Payment" ACTION="Create">');
      buffer.writeln('            <DATE>$tDate</DATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Payment</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${xmlEscape(expNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <PARTYLEDGERNAME>${xmlEscape(expenseLedger)}</PARTYLEDGERNAME>');
      buffer.writeln('            <NARRATION>Expense: ${xmlEscape(exp.description ?? expenseLedger)}</NARRATION>');

      // Expense Account Debited (Negative in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(expenseLedger)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Cash/Bank Credited (Positive in Tally)
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${xmlEscape(cashBankLedger)}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>${formatRupees(amountPaise)}</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    // Close XML Envelope
    buffer.writeln('      </REQUESTDATA>');
    buffer.writeln('    </IMPORTDATA>');
    buffer.writeln('  </BODY>');
    buffer.writeln('</ENVELOPE>');

    final xmlString = buffer.toString();

    // Save to temp directory for sharing / export
    final tempDir = outputDir ?? await getTemporaryDirectory();
    final sanitizeBizName = companyName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final nowStamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${tempDir.path}/tally_${sanitizeBizName}_$nowStamp.xml');
    await file.writeAsString(xmlString, flush: true);

    final totalVouchers = filteredInvoices.length +
        filteredPurchases.length +
        filteredReceipts.length +
        filteredPaymentsOut.length +
        filteredExpensePayments.length;

    return TallyExportSummary(
      salesCount: filteredInvoices.length,
      purchaseCount: filteredPurchases.length,
      receiptCount: filteredReceipts.length,
      paymentCount: filteredPaymentsOut.length + filteredExpensePayments.length,
      ledgerCount: ledgerCount,
      totalVouchers: totalVouchers,
      xml: xmlString,
      file: file,
    );
  }

  static bool _isDateInRange(String dateStr, DateTime? start, DateTime? end) {
    if (start == null && end == null) return true;
    try {
      final date = DateTime.parse(dateStr.split('T').first);
      if (start != null) {
        final startDay = DateTime(start.year, start.month, start.day);
        if (date.isBefore(startDay)) return false;
      }
      if (end != null) {
        final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
        if (date.isAfter(endDay)) return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}
