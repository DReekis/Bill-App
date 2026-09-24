import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../customers/customer_detail_screen.dart';

class PartyStatementSelectorScreen extends StatefulWidget {
  const PartyStatementSelectorScreen({super.key});

  @override
  State<PartyStatementSelectorScreen> createState() => _PartyStatementSelectorScreenState();
}

class _PartyStatementSelectorScreenState extends State<PartyStatementSelectorScreen> {
  int tabIndex = 0; // 0: Customers, 1: Suppliers
  bool loading = true;
  String? error;
  String searchQuery = '';

  List<Customer> customers = [];
  List<Supplier> suppliers = [];
  Map<int, int> customerBalances = {};
  Map<int, int> supplierBalances = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => loading = true);
    try {
      final repo = Repository.instance;
      final cList = await repo.customers(bizId);
      final sList = await repo.suppliers(bizId);

      final cBals = <int, int>{};
      for (final c in cList) {
        if (c.id != null) {
          cBals[c.id!] = await repo.customerBalance(bizId, c.id!);
        }
      }

      final sBals = <int, int>{};
      for (final s in sList) {
        if (s.id != null) {
          sBals[s.id!] = await repo.supplierBalance(bizId, s.id!);
        }
      }

      if (!mounted) return;
      setState(() {
        customers = cList;
        suppliers = sList;
        customerBalances = cBals;
        supplierBalances = sBals;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = customers.where((c) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) || (c.phone?.contains(q) ?? false);
    }).toList();

    final filteredSuppliers = suppliers.where((s) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) || (s.phone?.contains(q) ?? false);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Party Statement (Ledger)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Column(
        children: [
          // Segmented Tab
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => tabIndex = 0),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: tabIndex == 0 ? StitchColors.primary : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Customers (${customers.length})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tabIndex == 0 ? Colors.white : StitchColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => tabIndex = 1),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: tabIndex == 1 ? StitchColors.primary : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Suppliers (${suppliers.length})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tabIndex == 1 ? Colors.white : StitchColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search ${tabIndex == 0 ? 'customer' : 'supplier'} by name or phone...',
                      hintStyle: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                    ),
                    onChanged: (val) => setState(() => searchQuery = val.trim()),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : error != null
                      ? Center(child: Text('Error: $error', style: const TextStyle(color: Colors.red)))
                      : tabIndex == 0
                          ? _buildCustomerList(filteredCustomers)
                          : _buildSupplierList(filteredSuppliers),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerList(List<Customer> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          searchQuery.isNotEmpty ? 'No customers matching "$searchQuery"' : 'No customers recorded yet',
          style: const TextStyle(color: StitchColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = list[index];
        final bal = customerBalances[c.id ?? 0] ?? 0;
        final isDue = bal > 0;

        return InkWell(
          onTap: () {
            if (c.id != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id!)),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: StitchColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: StitchColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        c.phone ?? (c.city != null ? c.city! : 'Customer'),
                        style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPaise(bal.abs()),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                    ),
                    Text(
                      bal == 0 ? 'Settled' : (isDue ? 'To Collect' : 'Advance'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: bal == 0 ? Colors.grey : (isDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: StitchColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupplierList(List<Supplier> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          searchQuery.isNotEmpty ? 'No suppliers matching "$searchQuery"' : 'No suppliers recorded yet',
          style: const TextStyle(color: StitchColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final s = list[index];
        final bal = supplierBalances[s.id ?? 0] ?? 0;
        final isDue = bal > 0;

        return InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Supplier: ${s.name} - Ledger balance: ${formatPaise(bal)}')),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF059669).withValues(alpha: 0.1),
                  child: Text(
                    s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        s.phone ?? (s.state != null ? s.state! : 'Supplier'),
                        style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPaise(bal.abs()),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                    ),
                    Text(
                      bal == 0 ? 'Settled' : (isDue ? 'To Pay' : 'Advance'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: bal == 0 ? Colors.grey : (isDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: StitchColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}
