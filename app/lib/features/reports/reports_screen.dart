import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import 'reports_menu_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'This month';
  Map<String, int>? totals;
  List<(String, int)>? expenses;
  List<(String, int, int)>? products;
  String? loadError;

  String get fromDate {
    final now = DateTime.now();
    switch (period) {
      case 'Today':
        return todayIso();
      case 'This week':
        return isoDate(now.subtract(Duration(days: now.weekday - 1)));
      case 'This year':
        return isoDate(DateTime(now.year, 1, 1));
      default:
        return isoDate(DateTime(now.year, now.month, 1));
    }
  }

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final from = fromDate;
    try {
      final t = await repo.periodTotals(businessId, from);
      final e = await repo.expenseBreakdown(businessId, from);
      final p = await repo.bestProducts(businessId, from);
      if (!mounted) return;
      setState(() {
        loadError = null;
        totals = t;
        expenses = e;
        products = p;
      });
    } catch (e) {
      // never leave the screen spinning forever on a query failure
      if (!mounted) return;
      setState(() => loadError = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = totals;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & analytics'),
        actions: [
          IconButton(
            tooltip: 'All Reports & Statements',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ReportsMenuScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Today', label: Text('Today')),
              ButtonSegment(value: 'This week', label: Text('Week')),
              ButtonSegment(value: 'This month', label: Text('Month')),
              ButtonSegment(value: 'This year', label: Text('Year')),
            ],
            selected: {period},
            onSelectionChanged: (s) {
              setState(() => period = s.first);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (loadError != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load reports: $loadError',
                  style: const TextStyle(fontSize: 13, color: StitchColors.error)),
            )
          else if (t == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [
                StatCard(label: 'Sales', value: formatPaise(t['sales']!), icon: Icons.trending_up_rounded, color: StitchColors.success),
                StatCard(label: 'Profit', value: formatPaise(t['profit']!), icon: Icons.savings_outlined, color: t['profit']! >= 0 ? StitchColors.success : StitchColors.error),
                StatCard(label: 'Purchases', value: formatPaise(t['purchases']!), icon: Icons.local_shipping_rounded, color: StitchColors.error),
                StatCard(label: 'Expenses', value: formatPaise(t['expenses']!), icon: Icons.currency_rupee_rounded, color: StitchColors.error),
                StatCard(label: 'Tax collected', value: formatPaise(_taxPaise(t)), icon: Icons.account_balance_rounded, color: StitchColors.warning),
                StatCard(label: 'Collected', value: formatPaise(t['collected']!), icon: Icons.savings_rounded, color: StitchColors.success),
              ],
            ),
          const SizedBox(height: 20),
          const Text('Expense breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (expenses == null)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (expenses!.isEmpty)
            const AppEmptyState(icon: Icons.pie_chart_outline_rounded, title: 'No expenses this period')
          else
            ...expenses!.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(children: [
                      Expanded(child: Text(e.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      Text(formatPaise(e.$2), style: moneyStyle(fontSize: 13)),
                    ]),
                  ),
                )),
          if (products != null && products!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Best sellers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...products!.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(children: [
                      Expanded(
                        child: Text(p.$1, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text('${_qty(p.$2)} sold', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      const SizedBox(width: 12),
                      Text(formatPaise(p.$3), style: moneyStyle(fontSize: 13)),
                    ]),
                  ),
                )),
          ],
        ]),
      ),
    );
  }

  int _taxPaise(Map<String, int> t) {
    final salesTaxable = t['taxable']!;
    final total = t['sales']!;
    return total - salesTaxable;
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}