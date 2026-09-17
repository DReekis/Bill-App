import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class CashBankHubScreen extends StatefulWidget {
  const CashBankHubScreen({super.key});

  @override
  State<CashBankHubScreen> createState() => _CashBankHubScreenState();
}

class _CashBankHubScreenState extends State<CashBankHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool loading = true;
  CashBankSummary? summary;
  List<Cheque> allCheques = [];
  String chequeTypeFilter = 'all'; // 'all', 'inward', 'outward'
  String chequeStatusFilter = 'all'; // 'all', 'Pending', 'Cleared', 'Bounced'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => loading = true);

    try {
      final s = await Repository.instance.getCashAndBankSummary(bizId);
      final c = await Repository.instance.cheques(bizId);
      if (!mounted) return;
      setState(() {
        summary = s;
        allCheques = c;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showAddBankAccountSheet([BankAccount? existing]) {
    final nameCtrl = TextEditingController(text: existing?.bankName ?? '');
    final acctNameCtrl = TextEditingController(text: existing?.accountName ?? '');
    final numCtrl = TextEditingController(text: existing?.accountNumber ?? '');
    final ifscCtrl = TextEditingController(text: existing?.ifsc ?? '');
    final balCtrl = TextEditingController(text: existing != null ? (existing.openingBalance / 100).toString() : '0');
    String acctType = existing?.accountType ?? 'Current';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existing == null ? 'Add Bank Account' : 'Edit Bank Account',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bank Name *',
                      hintText: 'e.g. HDFC Bank, SBI, ICICI',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: acctNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Account Holder Name',
                      hintText: 'e.g. Sharma Enterprises',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Account Number',
                      hintText: 'e.g. 50100234567890',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ifscCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'IFSC Code',
                            hintText: 'HDFC0001234',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: acctType,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Current', child: Text('Current')),
                            DropdownMenuItem(value: 'Savings', child: Text('Savings')),
                            DropdownMenuItem(value: 'Overdraft', child: Text('OD / CC')),
                          ],
                          onChanged: (val) {
                            if (val != null) setSheetState(() => acctType = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (existing == null)
                    TextField(
                      controller: balCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Opening Balance (₹)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: StitchColors.primary),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          if (mounted) showAppMessage(this.context, 'Bank Name is required', error: true);
                          return;
                        }
                        final opPaise = ((double.tryParse(balCtrl.text.trim()) ?? 0) * 100).round();
                        final acct = BankAccount(
                          id: existing?.id,
                          bankName: name,
                          accountName: acctNameCtrl.text.trim().isNotEmpty ? acctNameCtrl.text.trim() : null,
                          accountNumber: numCtrl.text.trim().isNotEmpty ? numCtrl.text.trim() : null,
                          ifsc: ifscCtrl.text.trim().isNotEmpty ? ifscCtrl.text.trim().toUpperCase() : null,
                          accountType: acctType,
                          openingBalance: existing != null ? existing.openingBalance : opPaise,
                        );
                        await Repository.instance.upsertBankAccount(acct);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        showAppMessage(this.context, 'Bank account saved successfully');
                        _load();
                      },
                      child: const Text('Save Bank Account', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFundTransferDialog() {
    final accounts = summary?.accounts ?? [];
    if (accounts.isEmpty) {
      showAppMessage(context, 'Add at least one bank account first', error: true);
      return;
    }

    String fromAccount = 'cash';
    String toAccount = 'bank:${accounts.first.account.id}';
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Transfer Funds', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: fromAccount,
                  decoration: const InputDecoration(labelText: 'From Account', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: 'cash', child: Text('Cash in Hand')),
                    for (final acc in accounts)
                      DropdownMenuItem(
                        value: 'bank:${acc.account.id}',
                        child: Text(acc.account.bankName),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => fromAccount = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: toAccount,
                  decoration: const InputDecoration(labelText: 'To Account', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: 'cash', child: Text('Cash in Hand')),
                    for (final acc in accounts)
                      DropdownMenuItem(
                        value: 'bank:${acc.account.id}',
                        child: Text(acc.account.bankName),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => toAccount = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Remarks / Reference',
                    hintText: 'e.g. Cash deposit, Interbank transfer',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: StitchColors.primary),
              onPressed: () async {
                if (fromAccount == toAccount) {
                  if (mounted) showAppMessage(this.context, 'From and To accounts cannot be the same', error: true);
                  return;
                }
                final amtPaise = ((double.tryParse(amtCtrl.text.trim()) ?? 0) * 100).round();
                if (amtPaise <= 0) {
                  if (mounted) showAppMessage(this.context, 'Enter a valid positive amount', error: true);
                  return;
                }
                await Repository.instance.recordTransfer(
                  fromAccount: fromAccount,
                  toAccount: toAccount,
                  amount: amtPaise,
                  date: isoDate(DateTime.now()),
                  note: noteCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                showAppMessage(this.context, 'Fund transfer recorded in ledger');
                _load();
              },
              child: const Text('Transfer', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddChequeSheet() {
    final bizId = context.read<Session>().businessId!;
    final accounts = summary?.accounts ?? [];
    final chqNoCtrl = TextEditingController();
    final partyCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String type = 'inward'; // 'inward' or 'outward'
    int? selectedBankAccountId = accounts.isNotEmpty ? accounts.first.account.id : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Record Cheque', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'inward', label: Text('Inward (From Customer)')),
                      ButtonSegment(value: 'outward', label: Text('Outward (To Supplier)')),
                    ],
                    selected: {type},
                    onSelectionChanged: (val) => setSheetState(() => type = val.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: chqNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cheque Number *',
                      hintText: 'e.g. 000124',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: partyCtrl,
                    decoration: InputDecoration(
                      labelText: type == 'inward' ? 'Customer Name *' : 'Supplier Name *',
                      hintText: 'Party Name',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cheque Amount (₹) *',
                      hintText: '0.00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: selectedBankAccountId,
                      decoration: const InputDecoration(labelText: 'Target Bank Account', border: OutlineInputBorder()),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(value: a.account.id, child: Text(a.account.bankName)),
                      ],
                      onChanged: (val) => setSheetState(() => selectedBankAccountId = val),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Optional notes or invoice number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: StitchColors.primary),
                      onPressed: () async {
                        final no = chqNoCtrl.text.trim();
                        final party = partyCtrl.text.trim();
                        final amtPaise = ((double.tryParse(amtCtrl.text.trim()) ?? 0) * 100).round();

                        if (no.isEmpty || party.isEmpty || amtPaise <= 0) {
                          if (mounted) showAppMessage(this.context, 'Please fill in all required fields', error: true);
                          return;
                        }

                        final chq = Cheque(
                          businessId: bizId,
                          chequeNumber: no,
                          partyType: type == 'inward' ? 'customer' : 'supplier',
                          partyName: party,
                          amount: amtPaise,
                          date: isoDate(DateTime.now()),
                          type: type,
                          bankAccountId: selectedBankAccountId,
                          status: 'Pending',
                          notes: notesCtrl.text.trim(),
                        );

                        await Repository.instance.upsertCheque(chq);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        showAppMessage(this.context, 'Cheque recorded successfully');
                        _load();
                      },
                      child: const Text('Record Cheque', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBounceChequeDialog(Cheque cheque) {
    final reasonCtrl = TextEditingController(text: 'Insufficient Funds');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Cheque as Bounced', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cheque #${cheque.chequeNumber} for ${formatPaise(cheque.amount)} will be marked as Bounced.',
              style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 10),
            const Text(
              '⚠️ Reversal ledger entries will automatically restore party debt/payable.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.error),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Bounce Reason', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StitchColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await Repository.instance.updateChequeStatus(
                cheque.id!,
                'Bounced',
                bounceReason: reasonCtrl.text.trim(),
              );
              if (!mounted) return;
              showAppMessage(context, 'Cheque marked as bounced. Ledger reversed.');
              _load();
            },
            child: const Text('Confirm Bounce', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showAccountPassbookSheet({
    required String accountTitle,
    required String accountKey,
    required int currentBalance,
  }) {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filter = 'all'; // 'all', 'inflow', 'outflow'

        return StatefulBuilder(
          builder: (context, setSheetState) => DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Top Drag Handle & Title
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(bottom: BorderSide(color: StitchColors.outline)),
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: StitchColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                accountKey == 'cash' ? Icons.payments_outlined : Icons.account_balance_outlined,
                                color: StitchColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    accountTitle,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'Account Statement & Passbook',
                                    style: TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Export Statement',
                              icon: const Icon(Icons.share_outlined, color: StitchColors.primary),
                              onPressed: () async {
                                final entries = await Repository.instance.accountLedger(bizId, accountKey);
                                final csv = StringBuffer()
                                  ..writeln('Account Statement - $accountTitle')
                                  ..writeln('Current Balance,${formatPaise(currentBalance)}')
                                  ..writeln('Date,Reference,Description,Inflow (Debit),Outflow (Credit)');
                                for (final e in entries) {
                                  final inflow = e.debit > 0 ? (e.debit / 100.0).toStringAsFixed(2) : '0.00';
                                  final outflow = e.credit > 0 ? (e.credit / 100.0).toStringAsFixed(2) : '0.00';
                                  final note = (e.note ?? e.account).replaceAll(',', ' ');
                                  final ref = (e.refType ?? '').replaceAll(',', ' ');
                                  csv.writeln('${e.date},$ref,$note,$inflow,$outflow');
                                }
                                Share.share(csv.toString(), subject: 'Statement - $accountTitle');
                              },
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Current balance strip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Current Ledger Balance',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                              ),
                              Text(
                                formatPaise(currentBalance),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: currentBalance < 0 ? StitchColors.error : StitchColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Filter chips
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: filter == 'all',
                              onSelected: (_) => setSheetState(() => filter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Inflow (+)'),
                              selected: filter == 'inflow',
                              onSelected: (_) => setSheetState(() => filter = 'inflow'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Outflow (-)'),
                              selected: filter == 'outflow',
                              onSelected: (_) => setSheetState(() => filter = 'outflow'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Ledger entries
                  Expanded(
                    child: FutureBuilder<List<LedgerEntry>>(
                      future: Repository.instance.accountLedger(bizId, accountKey),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final entries = snapshot.data ?? [];
                        final filtered = entries.where((e) {
                          if (filter == 'inflow') return e.debit > 0;
                          if (filter == 'outflow') return e.credit > 0;
                          return true;
                        }).toList();

                        if (filtered.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No transactions recorded',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Sales, purchases, payments, and transfers affecting this account will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final e = filtered[idx];
                            final isInflow = e.debit > e.credit;
                            final amount = isInflow ? e.debit : e.credit;
                            final note = e.note?.isNotEmpty == true ? e.note! : e.account;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: StitchColors.outline),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isInflow ? const Color(0xFFE8F5EF) : const Color(0xFFFFECE9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isInflow ? Icons.south_west_rounded : Icons.north_east_rounded,
                                      size: 18,
                                      color: isInflow ? StitchColors.success : StitchColors.error,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          note,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              displayDate(e.date),
                                              style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                            ),
                                            if (e.refType != null) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '• ${e.refType}',
                                                style: const TextStyle(fontSize: 10, color: StitchColors.textTertiary),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isInflow ? "+" : "-"}${formatPaise(amount)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: isInflow ? StitchColors.success : StitchColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Cash & Bank Hub', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: StitchColors.primary,
          unselectedLabelColor: StitchColors.textSecondary,
          indicatorColor: StitchColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          tabs: const [
            Tab(text: 'Accounts & Liquid Assets'),
            Tab(text: 'Cheque Register'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Transfer Funds',
            icon: const Icon(Icons.swap_horiz_rounded, color: StitchColors.primary),
            onPressed: _showFundTransferDialog,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: ACCOUNTS & LIQUID ASSETS
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      // Total Liquid Assets Hero Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF15157D), Color(0xFF2E3192)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF2E3192).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Liquid Assets',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 20),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatPaise(s?.totalLiquidAssets ?? 0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _showAccountPassbookSheet(
                                      accountTitle: 'Cash in Hand',
                                      accountKey: 'cash',
                                      currentBalance: s?.cashInHand ?? 0,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Cash in Hand', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white.withValues(alpha: 0.7)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatPaise(s?.cashInHand ?? 0),
                                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _showAccountPassbookSheet(
                                      accountTitle: 'All Bank Accounts',
                                      accountKey: 'bank',
                                      currentBalance: s?.totalBankBalance ?? 0,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Total Bank Balances', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white.withValues(alpha: 0.7)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatPaise(s?.totalBankBalance ?? 0),
                                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section Header with Add Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bank Accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          TextButton.icon(
                            onPressed: () => _showAddBankAccountSheet(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if ((s?.accounts ?? []).isEmpty)
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.account_balance_outlined, size: 40, color: StitchColors.textTertiary),
                              const SizedBox(height: 10),
                              const Text('No Bank Accounts Configured', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              const Text('Add your company bank accounts to track live balances and cheques.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                              const SizedBox(height: 14),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: StitchColors.primary),
                                onPressed: () => _showAddBankAccountSheet(),
                                child: const Text('Add First Bank Account'),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: s!.accounts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final item = s.accounts[idx];
                            final acc = item.account;
                            final num = acc.accountNumber ?? '';
                            final masked = num.length > 4 ? '•••• ${num.substring(num.length - 4)}' : num;

                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () => _showAccountPassbookSheet(
                                  accountTitle: '${acc.bankName} (${acc.accountType})',
                                  accountKey: 'bank:${acc.id}',
                                  currentBalance: item.currentBalance,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: StitchColors.outline),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF4FF),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.account_balance_rounded, color: StitchColors.primary, size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(acc.bankName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${acc.accountType} • $masked',
                                                  style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (val) async {
                                              if (val == 'edit') {
                                                _showAddBankAccountSheet(acc);
                                              } else if (val == 'delete') {
                                                await Repository.instance.deleteBankAccount(acc.id!);
                                                _load();
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                                              PopupMenuItem(value: 'delete', child: Text('Delete / Deactivate')),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      const Divider(height: 1, color: StitchColors.outline),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Current Balance', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                              const SizedBox(height: 2),
                                              Text(
                                                formatPaise(item.currentBalance),
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                  color: item.currentBalance < 0 ? StitchColors.error : StitchColors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  minimumSize: Size.zero,
                                                  side: const BorderSide(color: StitchColors.outline),
                                                ),
                                                onPressed: () => _showAccountPassbookSheet(
                                                  accountTitle: '${acc.bankName} (${acc.accountType})',
                                                  accountKey: 'bank:${acc.id}',
                                                  currentBalance: item.currentBalance,
                                                ),
                                                icon: const Icon(Icons.receipt_long_rounded, size: 14, color: StitchColors.textSecondary),
                                                label: const Text('Passbook', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textPrimary)),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  minimumSize: Size.zero,
                                                  side: const BorderSide(color: StitchColors.primary),
                                                ),
                                                onPressed: _showFundTransferDialog,
                                                icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: StitchColors.primary),
                                                label: const Text('Transfer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // TAB 2: CHEQUE REGISTER
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      // Uncleared summary banner
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: StitchColors.outline),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Uncleared Deposits', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatPaise(s?.pendingChequesInward ?? 0),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StitchColors.primary),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('Inward Cheques', style: TextStyle(fontSize: 10, color: StitchColors.textTertiary)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: StitchColors.outline),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pending Cleared', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatPaise(s?.pendingChequesOutward ?? 0),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('Outward Supplier', style: TextStyle(fontSize: 10, color: StitchColors.textTertiary)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _chequeFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _chequeFilterChip('Inward', 'inward'),
                            const SizedBox(width: 8),
                            _chequeFilterChip('Outward', 'outward'),
                            const SizedBox(width: 8),
                            _chequeFilterChip('Pending', 'Pending'),
                            const SizedBox(width: 8),
                            _chequeFilterChip('Cleared', 'Cleared'),
                            const SizedBox(width: 8),
                            _chequeFilterChip('Bounced', 'Bounced'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // List of Cheques
                      Builder(
                        builder: (context) {
                          final filtered = allCheques.where((c) {
                            if (chequeTypeFilter == 'inward' && c.type != 'inward') return false;
                            if (chequeTypeFilter == 'outward' && c.type != 'outward') return false;
                            if (chequeStatusFilter != 'all' && c.status != chequeStatusFilter) return false;
                            return true;
                          }).toList();

                          if (filtered.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(32),
                              alignment: Alignment.center,
                              child: const Column(
                                children: [
                                  Icon(Icons.style_outlined, size: 40, color: StitchColors.textTertiary),
                                  SizedBox(height: 10),
                                  Text('No cheques in register', style: TextStyle(color: StitchColors.textSecondary)),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final chq = filtered[idx];
                              final isPending = chq.status == 'Pending';
                              final isCleared = chq.status == 'Cleared';
                              final isBounced = chq.status == 'Bounced';

                              Color statusColor = const Color(0xFFD97706);
                              Color statusBg = const Color(0xFFFEF3C7);
                              if (isCleared) {
                                statusColor = StitchColors.success;
                                statusBg = const Color(0xFFDCFCE7);
                              } else if (isBounced) {
                                statusColor = StitchColors.error;
                                statusBg = const Color(0xFFFEE2E2);
                              }

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: StitchColors.outline),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF4FF),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'CHQ #${chq.chequeNumber}',
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: StitchColors.primary),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              chq.type.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: chq.type == 'inward' ? StitchColors.success : const Color(0xFFD97706),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                                          child: Text(
                                            chq.status,
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            chq.partyName ?? 'Party',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          formatPaise(chq.amount),
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Date: ${chq.date}${chq.clearingDate != null ? ' • Cleared: ${chq.clearingDate}' : ''}',
                                      style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                    ),
                                    if (isBounced && chq.bounceReason != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Reason: ${chq.bounceReason}',
                                        style: const TextStyle(fontSize: 11, color: StitchColors.error, fontWeight: FontWeight.w600),
                                      ),
                                    ],

                                    // Action buttons for Pending or Cleared
                                    if (isPending) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              minimumSize: Size.zero,
                                              side: const BorderSide(color: StitchColors.error),
                                            ),
                                            onPressed: () => _showBounceChequeDialog(chq),
                                            child: const Text('Bounce', style: TextStyle(color: StitchColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: StitchColors.success,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                              minimumSize: Size.zero,
                                            ),
                                            onPressed: () async {
                                              await Repository.instance.updateChequeStatus(
                                                chq.id!,
                                                'Cleared',
                                                clearingDate: isoDate(DateTime.now()),
                                              );
                                              if (!mounted) return;
                                              showAppMessage(this.context, 'Cheque marked as Cleared. Funds updated.');
                                              _load();
                                            },
                                            child: const Text('Mark Cleared', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                    ] else if (isCleared) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => _showBounceChequeDialog(chq),
                                            child: const Text('Bounce Reversal', style: TextStyle(color: StitchColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: StitchColors.primary,
        onPressed: _showAddChequeSheet,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Record Cheque', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _chequeFilterChip(String label, String value) {
    bool active = false;
    if (value == 'all' && chequeTypeFilter == 'all' && chequeStatusFilter == 'all') {
      active = true;
    } else if (value == 'inward' && chequeTypeFilter == 'inward') {
      active = true;
    } else if (value == 'outward' && chequeTypeFilter == 'outward') {
      active = true;
    } else if (['Pending', 'Cleared', 'Bounced'].contains(value) && chequeStatusFilter == value) {
      active = true;
    }

    return InkWell(
      onTap: () {
        setState(() {
          if (value == 'all') {
            chequeTypeFilter = 'all';
            chequeStatusFilter = 'all';
          } else if (value == 'inward' || value == 'outward') {
            chequeTypeFilter = value;
          } else {
            chequeStatusFilter = value;
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? StitchColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? StitchColors.primary : StitchColors.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : StitchColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
