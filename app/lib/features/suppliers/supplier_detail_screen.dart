import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../finance/ledger_entry_tile.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../payments/payment_form.dart';
import '../purchases/purchase_builder_screen.dart';
import 'supplier_form.dart';

class SupplierDetailScreen extends StatefulWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});
  final int supplierId;
  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  Supplier? supplier;
  int balance = 0;
  List<LedgerEntry>? ledger;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final s = await repo.supplier(businessId, widget.supplierId);
    final bal = await repo.partyBalance(businessId, 'supplier', widget.supplierId);
    final l = await repo.partyLedger(businessId, 'supplier', widget.supplierId);
    if (!mounted) return;
    setState(() {
      supplier = s;
      balance = bal;
      ledger = l;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _edit() {
    final s = supplier;
    if (s == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SupplierFormSheet(
        businessId: context.read<Session>().businessId!,
        onSaved: _load,
        supplier: s,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.name ?? 'Supplier'),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 80), children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    InitialsAvatar(s.name, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          [s.phone, s.gstin, s.state].where((e) => e != null && e.isNotEmpty).join('  •  '),
                          style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                        ),
                      ]),
                    ),
                  ]),
                  const Divider(height: 20),
                  Row(children: [
                    Expanded(
                      child: _labelValue('We owe', formatPaise(balance),
                          balance > 0 ? StitchColors.error : StitchColors.textSecondary),
                    ),
                    Expanded(
                      child: _labelValue('Credit period',
                          s.creditPeriodDays == 0 ? 'Spot' : '${s.creditPeriodDays} days',
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
                        builder: (_) => PurchaseBuilderScreen(initialSupplierId: s.id))),
                    icon: const Icon(Icons.local_shipping_rounded, size: 18),
                    label: const Text('New purchase'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PaymentFormScreen(partyType: 'supplier', partyId: s.id, partyName: s.name))),
                    icon: const Icon(Icons.call_made_rounded, size: 18),
                    label: const Text('Payment out'),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              const Text('Ledger', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ..._ledgerSection(),
            ]),
    );
  }

  List<Widget> _ledgerSection() {
    final l = ledger;
    if (l == null) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
    if (l.isEmpty) return const [AppEmptyState(icon: Icons.receipt_long_rounded, title: 'No transactions yet')];
    return l.map((entry) => LedgerEntryTile(entry: entry, mode: 'supplier')).toList();
  }

  Widget _labelValue(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]);
}