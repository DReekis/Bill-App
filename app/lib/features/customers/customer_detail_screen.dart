import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../finance/ledger_entry_tile.dart';
import '../../finance/simple_invoice_row.dart';
import '../../finance/simple_quotation_row.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../../utils/widgets.dart';
import '../payments/payment_form.dart';
import '../sales/invoice_builder_screen.dart';
import '../sales/invoice_detail_screen.dart';
import '../sales/quotation_builder_screen.dart';
import '../sales/quotation_detail_screen.dart';
import 'customer_form.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _TimelineEntry {
  _TimelineEntry({
    required this.date,
    required this.id,
    required this.widget,
  });

  final String date;
  final int id;
  final Widget widget;
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer? customer;
  int balance = 0;
  List<LedgerEntry>? ledger;
  List<Invoice>? invoiceList;
  List<Quotation>? quotationList;
  int segment = 0; // 0: Statement (All), 1: Invoices, 2: Estimates

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final c = await repo.customer(businessId, widget.customerId);
    final bal = await repo.partyBalance(businessId, 'customer', widget.customerId);
    final l = await repo.partyLedger(businessId, 'customer', widget.customerId);
    final inv = await repo.invoicesForParty(businessId, 'customer', widget.customerId);
    final quotes = await repo.quotationsForParty(businessId, widget.customerId);
    if (!mounted) return;
    setState(() {
      customer = c;
      balance = bal;
      ledger = l;
      invoiceList = inv;
      quotationList = quotes;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _edit() {
    final c = customer;
    if (c == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomerFormSheet(
        businessId: context.read<Session>().businessId!,
        onSaved: _load,
        customer: c,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final invCount = invoiceList?.length ?? 0;
    final quoteCount = quotationList?.length ?? 0;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(c?.name ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Customer',
          ),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                // Top Customer Summary Card
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InitialsAvatar(c.name, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(
                                  RowString([c.phone, c.gstin, c.state]).join('  •  '),
                                  style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _labelValue(
                              'To receive',
                              formatPaise(balance),
                              balance > 0 ? StitchColors.warning : StitchColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: _labelValue(
                              'Credit limit',
                              formatPaise(c.creditLimit),
                              StitchColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: _labelValue(
                              'Payment terms',
                              c.paymentTermsDays == 0 ? 'Spot' : '${c.paymentTermsDays} days',
                              StitchColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Action Buttons Row (BillBook Style: New Sale | + Estimate | Payment In)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => InvoiceBuilderScreen(customerId: c.id)))
                            .then((_) => _load()),
                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                        label: const Text('New sale', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: StitchColors.primary,
                          side: const BorderSide(color: StitchColors.primary, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => QuotationBuilderScreen(customerId: c.id)))
                            .then((_) => _load()),
                        icon: const Icon(Icons.request_quote_outlined, size: 16),
                        label: const Text('+ Estimate', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: StitchColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(
                              builder: (_) => PaymentFormScreen(partyType: 'customer', partyId: c.id, partyName: c.name),
                            ))
                            .then((_) => _load()),
                        icon: const Icon(Icons.currency_rupee_rounded, size: 16),
                        label: const Text('Payment in', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Segmented Activity Selector
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 0, label: Text('Statement')),
                    ButtonSegment(value: 1, label: Text('Invoices ($invCount)')),
                    ButtonSegment(value: 2, label: Text('Estimates ($quoteCount)')),
                  ],
                  selected: {segment},
                  onSelectionChanged: (s) => setState(() => segment = s.first),
                ),
                const SizedBox(height: 12),

                // Selected Tab Section
                if (segment == 0)
                  ..._statementSection()
                else if (segment == 1)
                  ..._invoiceSection()
                else
                  ..._estimateSection(),
              ],
            ),
    );
  }

  /// Full chronological Statement including Estimates, Invoices, and Payments
  List<Widget> _statementSection() {
    final invs = invoiceList;
    final quotes = quotationList;
    final led = ledger;

    if (invs == null || quotes == null || led == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }

    final entries = <_TimelineEntry>[];

    // 1. Add Estimates (Quotations)
    for (final q in quotes) {
      entries.add(_TimelineEntry(
        date: q.date,
        id: q.id ?? 0,
        widget: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SimpleQuotationRow(
            quotation: q,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => QuotationDetailScreen(quotationId: q.id!)))
                .then((_) => _load()),
            onShare: () async {
              final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
              if (biz != null) await shareQuotation(business: biz, quotation: q);
            },
            onConvert: q.status.toLowerCase() == 'converted'
                ? null
                : () async {
                    try {
                      final invId = await Repository.instance.convertQuotationToInvoice(q.id!);
                      if (!mounted) return;
                      showAppMessage(context, 'Estimate converted to Invoice ✓');
                      _load();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: invId)),
                      );
                    } catch (e) {
                      if (mounted) showAppMessage(context, 'Convert failed: $e', error: true);
                    }
                  },
          ),
        ),
      ));
    }

    // 2. Add Invoices
    for (final inv in invs) {
      entries.add(_TimelineEntry(
        date: inv.date,
        id: inv.id ?? 0,
        widget: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SimpleInvoiceRow(
            invoice: inv,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id!)))
                .then((_) => _load()),
          ),
        ),
      ));
    }

    // 3. Add Payments & Opening balances from Ledger (skip invoice sales since they're already listed above)
    for (final entry in led) {
      final isSaleInvoice = entry.note != null &&
          (entry.note!.startsWith('Sale #') || entry.note!.startsWith('Invoice #'));
      if (isSaleInvoice) continue;

      entries.add(_TimelineEntry(
        date: entry.date,
        id: entry.id ?? 0,
        widget: LedgerEntryTile(entry: entry, mode: 'due'),
      ));
    }

    if (entries.isEmpty) {
      return const [
        AppEmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'No transactions yet',
          subtitle: 'Estimates, sales, and payments for this contact will show here.',
        ),
      ];
    }

    // Sort all chronological transactions newest first
    entries.sort((a, b) {
      final dateComp = b.date.compareTo(a.date);
      if (dateComp != 0) return dateComp;
      return b.id.compareTo(a.id);
    });

    return entries.map((e) => e.widget).toList();
  }

  /// Invoices Section
  List<Widget> _invoiceSection() {
    final inv = invoiceList;
    if (inv == null) {
      return const [
        Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ];
    }
    if (inv.isEmpty) {
      return [
        AppEmptyState(
          icon: Icons.receipt_outlined,
          title: 'No invoices yet',
          subtitle: 'Create invoices to record official sales for this customer.',
          action: OutlinedButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => InvoiceBuilderScreen(customerId: widget.customerId)))
                .then((_) => _load()),
            child: const Text('New Sale'),
          ),
        ),
      ];
    }
    return inv
        .map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SimpleInvoiceRow(
                invoice: i,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: i.id!)))
                    .then((_) => _load()),
              ),
            ))
        .toList();
  }

  /// Estimates / Quotations Section (BillBook Style)
  List<Widget> _estimateSection() {
    final quotes = quotationList;
    if (quotes == null) {
      return const [
        Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ];
    }
    if (quotes.isEmpty) {
      return [
        AppEmptyState(
          icon: Icons.request_quote_outlined,
          title: 'No estimates yet',
          subtitle: 'Create quotations / estimates to share draft pricing before invoicing.',
          action: FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create Estimate'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => QuotationBuilderScreen(customerId: widget.customerId)))
                .then((_) => _load()),
          ),
        ),
      ];
    }
    return quotes
        .map((q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SimpleQuotationRow(
                quotation: q,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => QuotationDetailScreen(quotationId: q.id!)))
                    .then((_) => _load()),
                onShare: () async {
                  final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
                  if (biz != null) await shareQuotation(business: biz, quotation: q);
                },
                onConvert: q.status.toLowerCase() == 'converted'
                    ? null
                    : () async {
                        try {
                          final invId = await Repository.instance.convertQuotationToInvoice(q.id!);
                          if (!mounted) return;
                          showAppMessage(context, 'Estimate converted to Invoice ✓');
                          _load();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: invId)),
                          );
                        } catch (e) {
                          if (mounted) showAppMessage(context, 'Convert failed: $e', error: true);
                        }
                      },
              ),
            ))
        .toList();
  }

  Widget _labelValue(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      );
}

class RowString {
  RowString(this.items);
  final List<String?> items;
  String join(String sep) => items.where((e) => e != null && e.isNotEmpty).join(sep);
}