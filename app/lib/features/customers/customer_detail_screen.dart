import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../finance/ledger_entry_tile.dart';
import '../../finance/simple_invoice_row.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../payments/payment_form.dart';
import '../sales/invoice_builder_screen.dart';
import '../sales/invoice_detail_screen.dart';
import 'customer_form.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer? customer;
  int balance = 0;
  List<LedgerEntry>? ledger;
  List<Invoice>? invoiceList;
  int segment = 0;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final c = await repo.customer(businessId, widget.customerId);
    final bal = await repo.partyBalance(businessId, 'customer', widget.customerId);
    final l = await repo.partyLedger(businessId, 'customer', widget.customerId);
    final inv = await repo.invoicesForParty(businessId, 'customer', widget.customerId);
    if (!mounted) return;
    setState(() {
      customer = c;
      balance = bal;
      ledger = l;
      invoiceList = inv;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Customer'),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 80), children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    InitialsAvatar(c.name, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          RowString([c.phone, c.gstin, c.state]).join('  •  '),
                          style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                        ),
                      ]),
                    ),
                  ]),
                  const Divider(height: 20),
                  Row(children: [
                    Expanded(
                      child: _labelValue('To receive', formatPaise(balance),
                          balance > 0 ? StitchColors.warning : StitchColors.textSecondary),
                    ),
                    Expanded(
                      child: _labelValue('Credit limit', formatPaise(c.creditLimit), StitchColors.textSecondary),
                    ),
                    Expanded(
                      child: _labelValue('Payment terms',
                          c.paymentTermsDays == 0 ? 'Spot' : '${c.paymentTermsDays} days',
                          StitchColors.textSecondary),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => InvoiceBuilderScreen(customerId: c.id),
                    )),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New sale'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: StitchColors.success, foregroundColor: Colors.white),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => PaymentFormScreen(partyType: 'customer', partyId: c.id, partyName: c.name),
                        ))
                        .then((_) => _load()),
                    icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                    label: const Text('Payment in'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Statement')),
                  ButtonSegment(value: 1, label: Text('Invoices')),
                ],
                selected: {segment},
                onSelectionChanged: (s) => setState(() => segment = s.first),
              ),
              const SizedBox(height: 10),
              if (segment == 0)
                ..._ledgerSection()
              else
                ..._invoiceSection(),
            ]),
    );
  }

  List<Widget> _ledgerSection() {
    final l = ledger;
    if (l == null) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
    if (l.isEmpty) return const [AppEmptyState(icon: Icons.receipt_long_rounded, title: 'No transactions yet')];
    return l
        .map((entry) => LedgerEntryTile(entry: entry, mode: 'due'))
        .toList();
  }

  List<Widget> _invoiceSection() {
    final inv = invoiceList;
    if (inv == null) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
    if (inv.isEmpty) return const [AppEmptyState(icon: Icons.receipt_outlined, title: 'No invoices yet')];
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

  Widget _labelValue(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]);
}

class RowString {
  RowString(this.items);
  final List<String?> items;
  String join(String sep) => items.where((e) => e != null && e.isNotEmpty).join(sep);
}