import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../../l10n/app_localizations.dart';
import 'invoice_builder_screen.dart';
import 'invoice_detail_screen.dart';
import '../purchases/purchase_builder_screen.dart';

/// Unified Transactions Hub displaying Sales, Purchases, Payments In/Out, and Expenses.
class TransactionListTab extends StatefulWidget {
  const TransactionListTab({super.key});

  @override
  State<TransactionListTab> createState() => _TransactionListTabState();
}

/// Backwards compatibility alias
typedef InvoiceListTab = TransactionListTab;

class _TransactionListTabState extends State<TransactionListTab> {
  List<TransactionRecord>? _transactions;
  String _activeFilter = 'All';
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  static const _filterOptions = [
    'All',
    'Sales',
    'Purchases',
    'Payment In',
    'Payment Out',
    'Expenses',
  ];

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final all = await Repository.instance.recentTransactions(businessId, limit: 300);
    if (!mounted) return;
    setState(() => _transactions = all);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TransactionRecord> _getFiltered() {
    final all = _transactions ?? const <TransactionRecord>[];
    return all.where((t) {
      // Type Filter
      final matchType = switch (_activeFilter) {
        'Sales' => t.type == TransactionType.sale,
        'Purchases' => t.type == TransactionType.purchase,
        'Payment In' => t.type == TransactionType.paymentIn,
        'Payment Out' => t.type == TransactionType.paymentOut,
        'Expenses' => t.type == TransactionType.expense,
        _ => true,
      };

      // Search Query
      final q = _query.trim().toLowerCase();
      final matchQuery = q.isEmpty ||
          t.number.toLowerCase().contains(q) ||
          (t.partyName ?? '').toLowerCase().contains(q) ||
          (t.notes ?? '').toLowerCase().contains(q);

      return matchType && matchQuery;
    }).toList();
  }

  void _showDetails(TransactionRecord tx) {
    if (tx.type == TransactionType.sale && tx.refId != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => InvoiceDetailScreen(invoiceId: tx.refId!)))
          .then((_) => _load());
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tx.isInflow
                          ? StitchColors.success.withValues(alpha: 0.12)
                          : StitchColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tx.typeLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tx.isInflow ? StitchColors.success : StitchColors.error,
                      ),
                    ),
                  ),
                  Text(
                    tx.date,
                    style: const TextStyle(color: StitchColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tx.number,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: StitchColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _detailItem('Party / Vendor', tx.partyName ?? 'Direct Vendor'),
                    const Divider(height: 20),
                    _detailItem('Amount', formatPaise(tx.amount),
                        valueColor: tx.isInflow ? StitchColors.success : StitchColors.error,
                        isBold: true),
                    const Divider(height: 20),
                    _detailItem('Payment Mode', tx.paymentMode ?? 'Cash'),
                    const Divider(height: 20),
                    _detailItem('Status', tx.status),
                    if (tx.notes != null && tx.notes!.isNotEmpty) ...[
                      const Divider(height: 20),
                      _detailItem('Notes', tx.notes!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value, {Color? valueColor, bool isBold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: StitchColors.textSecondary, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? StitchColors.textPrimary,
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();

    var inflow = 0;
    var outflow = 0;
    for (final t in filtered) {
      if (t.isInflow) {
        inflow += t.amount;
      } else {
        outflow += t.amount;
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search transactions, parties, notes...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),

          // Filter Chips Horizontal Scroll
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _filterOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filterOptions[i];
                final isSel = _activeFilter == f;
                return ChoiceChip(
                  label: Text(f, style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    color: isSel ? Colors.white : StitchColors.textPrimary,
                  )),
                  selected: isSel,
                  selectedColor: StitchColors.primary,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  showCheckmark: false,
                  onSelected: (selected) {
                    if (selected) setState(() => _activeFilter = f);
                  },
                );
              },
            ),
          ),

          // Financial Summary Strip
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: StitchColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StitchColors.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Inflow', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('+${formatPaise(inflow)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.success)),
                  ],
                ),
                Container(height: 24, width: 1, color: Colors.grey.shade300),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Outflow', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('-${formatPaise(outflow)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.error)),
                  ],
                ),
                Container(height: 24, width: 1, color: Colors.grey.shade300),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Transactions', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${filtered.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.primary)),
                  ],
                ),
              ],
            ),
          ),

          // List or Empty State
          Expanded(
            child: _transactions == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : filtered.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 40),
                          AppEmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: 'No transactions found',
                            subtitle: _query.isNotEmpty
                                ? 'No transactions matching "$_query"'
                                : 'No ${_activeFilter == 'All' ? '' : _activeFilter.toLowerCase()} transactions recorded yet',
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                label: const Text('Create Sale'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()),
                                  ).then((_) => _load());
                                },
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                                label: const Text('Add Purchase'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const PurchaseBuilderScreen()),
                                  ).then((_) => _load());
                                },
                              ),
                            ],
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final (icon, bg, fg) = switch (item.type) {
                            TransactionType.sale => (Icons.shopping_cart_outlined, const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
                            TransactionType.purchase => (Icons.shopping_bag_outlined, const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
                            TransactionType.paymentIn => (Icons.call_received_rounded, const Color(0xFFE0F2F1), const Color(0xFF00695C)),
                            TransactionType.paymentOut => (Icons.call_made_rounded, const Color(0xFFFFF3E0), const Color(0xFFE65100)),
                            TransactionType.expense => (Icons.receipt_long_outlined, const Color(0xFFF3E5F5), const Color(0xFF7B1FA2)),
                            _ => (Icons.description_outlined, const Color(0xFFECEFF1), const Color(0xFF455A64)),
                          };

                          final isPositive = item.isInflow;
                          final prefix = isPositive ? '+' : '-';
                          final amountColor = isPositive ? StitchColors.success : StitchColors.error;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () => _showDetails(item),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: Icon(icon, color: fg, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  item.number,
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: StitchColors.textPrimary),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: bg,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  item.typeLabel,
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${item.partyName ?? 'Direct'} • ${item.date} • ${item.paymentMode ?? 'Cash'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$prefix${formatPaise(item.amount)}',
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: amountColor),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.status,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                          ),
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
          ),
        ],
      ),
    );
  }
}

class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('transactions')),
      ),
      body: const SafeArea(
        child: TransactionListTab(),
      ),
    );
  }
}
