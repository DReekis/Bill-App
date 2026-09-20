import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customer_form.dart';
import '../suppliers/supplier_detail_screen.dart';
import '../suppliers/supplier_form.dart';
import '../../l10n/app_localizations.dart';

class PartiesTab extends StatefulWidget {
  const PartiesTab({super.key});
  @override
  State<PartiesTab> createState() => _PartiesTabState();
}

class _PartiesTabState extends State<PartiesTab> {
  int segment = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text(l10n.isHindi ? 'ग्राहक' : 'Customers')),
            ButtonSegment(value: 1, label: Text(l10n.isHindi ? 'सप्लायर' : 'Suppliers')),
          ],
          selected: {segment},
          onSelectionChanged: (s) => setState(() => segment = s.first),
        ),
      ),
      Expanded(
        child: segment == 0 ? const CustomerListTab() : const SupplierListTab(),
      ),
    ]);
  }
}

class CustomerListTab extends StatefulWidget {
  const CustomerListTab({super.key});
  @override
  State<CustomerListTab> createState() => _CustomerListTabState();
}

class _CustomerListTabState extends State<CustomerListTab> {
  final search = TextEditingController();
  List<CustomerLite>? items;
  String query = '';

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final customers = await repo.customers(businessId);
    final resolved = await Future.wait(customers.map((c) async => CustomerLite(
          c,
          await repo.partyBalance(businessId, 'customer', c.id!),
        )));
    if (!mounted) return;
    setState(() => items = resolved);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _add() {
    final businessId = context.read<Session>().businessId!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerFormSheet(onSaved: _load, businessId: businessId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = items ?? const <CustomerLite>[];
    final filtered = query.trim().isEmpty
        ? all
        : all.where((c) => (c.name.toLowerCase().contains(query.toLowerCase())) ||
            (c.phone ?? '').contains(query)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: search,
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: context.l10n.isHindi ? 'ग्राहक या फोन खोजें' : 'Search customers or phone',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: FilledButton(
              onPressed: _add,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: const Icon(Icons.person_add_alt_1_rounded, size: 20),
            ),
          ),
        ]),
      ),
      Expanded(
        child: items == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : filtered.isEmpty
                ? ListView(children: [
                    AppEmptyState(
                      icon: Icons.people_alt_outlined,
                      title: context.l10n.isHindi ? 'कोई ग्राहक नहीं मिला' : 'No customers found',
                    )
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final c = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CustomerTile(customer: c, onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CustomerDetailScreen(customerId: c.id)));
                          _load();
                        }),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class CustomerLite {
  CustomerLite(this.customer, this.balance);
  final Customer customer;
  final int balance;
  int get id => customer.id!;
  String get name => customer.name;
  String? get phone => customer.phone;
  int get creditLimit => customer.creditLimit;
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});
  final CustomerLite customer;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final balance = customer.balance;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          InitialsAvatar(customer.name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(customer.phone ?? 'No phone', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatPaise(balance),
                style: moneyStyle(
                    fontSize: 13,
                    color: balance > 0
                        ? StitchColors.warning
                        : balance < 0
                            ? StitchColors.success
                            : StitchColors.textSecondary)),
            const SizedBox(height: 3),
            Text(balance > 0 ? 'To receive' : balance < 0 ? 'Advance' : 'Clear',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: balance > 0 ? StitchColors.warning : StitchColors.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class SupplierListTab extends StatefulWidget {
  const SupplierListTab({super.key});
  @override
  State<SupplierListTab> createState() => _SupplierListTabState();
}

class _SupplierListTabState extends State<SupplierListTab> {
  final search = TextEditingController();
  List<SupplierLite>? items;
  String query = '';

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final suppliers = await repo.suppliers(businessId);
    final resolved = await Future.wait(suppliers.map((s) async => SupplierLite(
          s,
          await repo.partyBalance(businessId, 'supplier', s.id!),
        )));
    if (!mounted) return;
    setState(() => items = resolved);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _add() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SupplierFormSheet(
        onSaved: _load,
        businessId: context.read<Session>().businessId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = items ?? const <SupplierLite>[];
    final filtered = query.trim().isEmpty
        ? all
        : all.where((s) => s.name.toLowerCase().contains(query.toLowerCase())).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: search,
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: context.l10n.isHindi ? 'सप्लायर खोजें' : 'Search suppliers',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: FilledButton(
              onPressed: _add,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: const Icon(Icons.storefront_outlined, size: 20),
            ),
          ),
        ]),
      ),
      Expanded(
        child: items == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : filtered.isEmpty
                ? ListView(children: [
                    AppEmptyState(
                      icon: Icons.storefront_outlined,
                      title: context.l10n.isHindi ? 'कोई सप्लायर नहीं मिला' : 'No suppliers found',
                    )
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final s = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SupplierDetailScreen(supplierId: s.id))),
                          borderRadius: BorderRadius.circular(12),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(children: [
                              InitialsAvatar(s.name, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(s.phone ?? 'No phone',
                                      style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(formatPaise(s.balance),
                                    style: moneyStyle(fontSize: 13, color: s.balance > 0 ? StitchColors.error : StitchColors.success)),
                                const SizedBox(height: 3),
                                Text(s.balance > 0 ? 'We owe' : 'Clear',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                              ]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class SupplierLite {
  SupplierLite(this.supplier, this.balance);
  final Supplier supplier;
  final int balance;
  int get id => supplier.id!;
  String get name => supplier.name;
  String? get phone => supplier.phone;
}