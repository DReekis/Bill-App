import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../suppliers/supplier_form.dart';

class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({
    super.key,
    required this.partyType,
    this.partyId,
    this.partyName,
    this.initialAmount,
    this.initialInvoiceId,
  });

  final String partyType;
  final int? partyId;
  final String? partyName;
  final int? initialAmount;
  final int? initialInvoiceId;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _amount = TextEditingController();
  String? mode;
  String date = todayIso();
  bool saving = false;
  List<Invoice>? unpaidInvoices;
  final Set<int> selected = {};
  int? partyId;
  String? partyName;

  bool get isCustomer => widget.partyType == 'customer';

  @override
  void initState() {
    super.initState();
    mode = 'Cash';
    partyId = widget.partyId;
    partyName = widget.partyName;
    if (widget.initialInvoiceId != null) {
      selected.add(widget.initialInvoiceId!);
    }
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      final amt = widget.initialAmount!;
      _amount.text = (amt % 100 == 0) ? '${amt ~/ 100}' : (amt / 100).toStringAsFixed(2);
    }
    _amount.addListener(() => setState(() {}));
    if (partyId != null || partyName != null) {
      _loadParties();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadParties() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final id = partyId;
    final isWalkIn = partyName == 'Walk-in customer' || (id == null && isCustomer && partyName != null);

    List<Invoice> invoices = [];
    if (isCustomer) {
      invoices = await repo.invoicesForParty(businessId, 'customer', id);
      if (id != null) {
        final cust = await repo.customer(businessId, id);
        if (cust != null) partyName = cust.name;
      } else if (isWalkIn) {
        partyName = 'Walk-in customer';
      }
    } else {
      if (id != null) {
        final supp = await repo.supplier(businessId, id);
        if (supp != null) partyName = supp.name;
      }
    }

    if (!mounted) return;
    setState(() {
      final filtered = invoices.where((i) => i.status != 'Paid' && i.status != 'Cancelled').toList();
      unpaidInvoices = filtered;

      if (widget.initialInvoiceId != null && filtered.any((i) => i.id == widget.initialInvoiceId)) {
        selected.add(widget.initialInvoiceId!);
      }

      if (_amount.text.trim().isEmpty) {
        if (selected.isNotEmpty) {
          final totalSelected = filtered.where((i) => selected.contains(i.id)).fold<int>(0, (s, i) => s + i.outstanding.paise);
          if (totalSelected > 0) {
            _amount.text = (totalSelected % 100 == 0) ? '${totalSelected ~/ 100}' : (totalSelected / 100).toStringAsFixed(2);
          }
        } else if (filtered.length == 1) {
          final single = filtered.first;
          if (single.id != null) {
            selected.add(single.id!);
            final amt = single.outstanding.paise;
            if (amt > 0) {
              _amount.text = (amt % 100 == 0) ? '${amt ~/ 100}' : (amt / 100).toStringAsFixed(2);
            }
          }
        }
      }
    });
  }

  Future<void> _pickParty() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final picked = await showModalBottomSheet<_PartySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PartyPickerSheet(
        isCustomer: isCustomer,
        businessId: businessId,
      ),
    );
    if (picked == null) return;
    setState(() {
      partyId = picked.id;
      partyName = picked.name;
      selected.clear();
      _amount.clear();
      unpaidInvoices = null;
    });
    await _loadParties();
  }

  void _toggleInvoiceSelection(Invoice i, bool? value) {
    setState(() {
      if (value == true) {
        selected.add(i.id!);
      } else {
        selected.remove(i.id);
      }
      final unpaid = unpaidInvoices ?? const <Invoice>[];
      final totalSelected = unpaid.where((inv) => selected.contains(inv.id)).fold<int>(0, (s, inv) => s + inv.outstanding.paise);
      if (totalSelected > 0) {
        _amount.text = (totalSelected % 100 == 0)
            ? '${totalSelected ~/ 100}'
            : (totalSelected / 100).toStringAsFixed(2);
      } else if (selected.isEmpty) {
        _amount.clear();
      }
    });
  }

  Future<void> _save() async {
    final effectivePartyName = partyName?.trim();
    final isWalkIn = isCustomer && (effectivePartyName == 'Walk-in customer' || (partyId == null && effectivePartyName != null && effectivePartyName.isNotEmpty));
    if (partyId == null && !isWalkIn) {
      showAppMessage(context, isCustomer ? 'Select a customer' : 'Select a supplier', error: true);
      return;
    }
    final amount = _toPaise(_amount.text);
    if (amount <= 0) {
      showAppMessage(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Repository.instance.recordPayment(
        businessId: context.read<Session>().businessId!,
        partyType: widget.partyType,
        amount: amount,
        date: date,
        mode: mode ?? 'Cash',
        invoiceIds: selected.isEmpty ? null : selected.toList(),
        partyId: partyId,
        partyName: partyName ?? (isWalkIn ? 'Walk-in customer' : null),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _toPaise(_amount.text);
    final unpaid = unpaidInvoices ?? const <Invoice>[];
    final unallocated = amount - unpaid.where((i) => selected.contains(i.id)).fold<int>(0, (s, i) => s + i.outstanding.paise);
    final isWalkIn = partyName == 'Walk-in customer';

    return Scaffold(
      appBar: AppBar(
        title: Text(isCustomer ? 'Payment in' : 'Payment out'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check_rounded)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Party', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickParty,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  if (isWalkIn) ...[
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_walk_rounded, size: 18, color: StitchColors.primary),
                    ),
                  ] else if (partyName != null && partyName!.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InitialsAvatar(partyName!, size: 32),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      partyName ?? (isCustomer ? 'Select customer' : 'Select supplier'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: (partyId == null && partyName == null)
                            ? StitchColors.textSecondary
                            : StitchColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: StitchColors.textSecondary),
                ]),
              ),
            ),
            const Divider(height: 24),
            AppAmountField(controller: _amount, label: 'Amount (₹)'),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: mode,
              isExpanded: true,
              decoration: inputDecoration('Payment mode'),
              items: paymentModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => mode = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppDateField(
              date: date,
              label: 'Payment date',
              onDateSelected: (d) => setState(() => date = d),
            ),
          ),
        ]),
        if (unpaid.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Allocate to invoices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tap to select which outstanding invoices this payment settles.',
              style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: unpaid.map((i) => CheckboxListTile(
                      value: selected.contains(i.id),
                      onChanged: (v) => _toggleInvoiceSelection(i, v),
                      title: Text(i.number, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${displayDate(i.date)} • outstanding ${formatPaise(i.outstanding.paise)}',
                          style: const TextStyle(fontSize: 11.5)),
                      secondary: Text(formatPaise(i.outstanding.paise), style: moneyStyle(fontSize: 12)),
                    )).toList(),
              ),
            ),
          ),
          if (unallocated > 0) ...[
            const SizedBox(height: 8),
            Text('${formatPaise(unallocated)} will be kept as advance',
                style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
          ],
        ] else if (unpaidInvoices != null) ...[
          const SizedBox(height: 16),
          const Text('No outstanding invoices — payment will be recorded as advance.',
              style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: AsyncButton(
            loading: saving,
            label: '${isCustomer ? 'Receive' : 'Pay'} ${amount > 0 ? formatPaise(amount) : 'amount'}',
            onPressed: _save,
          ),
        ),
      ]),
    );
  }
}

class _PartySelection {
  final int? id;
  final String name;
  const _PartySelection({this.id, required this.name});
}

class _PartyPickerSheet extends StatefulWidget {
  const _PartyPickerSheet({
    required this.isCustomer,
    required this.businessId,
  });

  final bool isCustomer;
  final int businessId;

  @override
  State<_PartyPickerSheet> createState() => _PartyPickerSheetState();
}

class _PartyPickerSheetState extends State<_PartyPickerSheet> {
  final _searchController = TextEditingController();
  List<({int? id, String name, String? phone})> _parties = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = Repository.instance;
    final Object result = widget.isCustomer
        ? await repo.customers(widget.businessId)
        : await repo.suppliers(widget.businessId);
    if (!mounted) return;
    setState(() {
      _parties = result is List<Customer>
          ? result.map((c) => (id: c.id, name: c.name, phone: c.phone)).toList()
          : (result as List<Supplier>)
              .map((s) => (id: s.id, name: s.name, phone: s.phone))
              .toList();
      _loading = false;
    });
  }

  Future<void> _addNewParty() async {
    if (widget.isCustomer) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => CustomerFormSheet(
          businessId: widget.businessId,
          onSaved: () async {},
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SupplierFormSheet(
          businessId: widget.businessId,
          onSaved: () async {},
        ),
      );
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _parties.where((p) {
      if (query.isEmpty) return true;
      final nameMatch = p.name.toLowerCase().contains(query);
      final phoneMatch = p.phone != null && p.phone!.toLowerCase().contains(query);
      return nameMatch || phoneMatch;
    }).toList();

    final showWalkIn = widget.isCustomer &&
        (query.isEmpty || 'walk-in customer'.contains(query) || 'walkin'.contains(query));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: StitchColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isCustomer ? 'Select Customer' : 'Select Supplier',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: StitchColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addNewParty,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(widget.isCustomer ? 'New' : 'New'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.isCustomer ? 'Search customer or phone...' : 'Search supplier or phone...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (showWalkIn) ...[
                          ListTile(
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: StitchColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.directions_walk_rounded,
                                color: StitchColors.primary,
                                size: 20,
                              ),
                            ),
                            title: const Text(
                              'Walk-in customer',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                            ),
                            subtitle: const Text(
                              'Direct cash sales • No account',
                              style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: StitchColors.textSecondary),
                            onTap: () {
                              Navigator.pop(
                                context,
                                const _PartySelection(id: null, name: 'Walk-in customer'),
                              );
                            },
                          ),
                          const Divider(height: 1, indent: 68),
                        ],
                        if (filtered.isEmpty && !showWalkIn) ...[
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 40, color: StitchColors.textSecondary.withValues(alpha: 0.5)),
                                const SizedBox(height: 8),
                                Text(
                                  'No ${widget.isCustomer ? 'customers' : 'suppliers'} found',
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          ...filtered.map((party) => ListTile(
                                leading: InitialsAvatar(party.name, size: 38),
                                title: Text(
                                  party.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                                ),
                                subtitle: (party.phone != null && party.phone!.isNotEmpty)
                                    ? Text(
                                        party.phone!,
                                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                      )
                                    : null,
                                trailing: const Icon(Icons.chevron_right_rounded, color: StitchColors.textSecondary),
                                onTap: () {
                                  Navigator.pop(
                                    context,
                                    _PartySelection(id: party.id, name: party.name),
                                  );
                                },
                              )),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}