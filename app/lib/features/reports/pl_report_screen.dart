import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

class PLReportScreen extends StatefulWidget {
  const PLReportScreen({super.key});

  @override
  State<PLReportScreen> createState() => _PLReportScreenState();
}

class _PLReportScreenState extends State<PLReportScreen> {
  Map<String, int>? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    // For simplicity, showing current month P&L
    final now = DateTime.now();
    final first = isoDate(DateTime(now.year, now.month, 1));
    final last = todayIso();
    final res = await Repository.instance.profitAndLossReport(bizId, first, last);
    setState(() => data = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Income Statement (P&L)', style: TextStyle(fontWeight: FontWeight.w800))),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader('Operating Revenue'),
                _buildRow('Gross Sales', data!['grossSales']!),
                _buildRow('Sales Returns', -(data!['salesReturn']!), isNegative: true),
                const Divider(),
                _buildRow('Net Revenue', data!['netSales']!, isBold: true),
                const SizedBox(height: 24),
                _buildHeader('Cost of Goods Sold'),
                _buildRow('COGS', data!['cogs']!, isNegative: true),
                const Divider(),
                _buildRow('GROSS PROFIT', data!['grossProfit']!, isBold: true, color: StitchColors.primary),
                const SizedBox(height: 32),
                _buildHeader('Operating Expenses'),
                ...data!.entries
                    .where((e) => !['grossSales', 'salesReturn', 'netSales', 'cogs', 'grossProfit', 'totalExpenses', 'netProfit'].contains(e.key))
                    .map((e) => _buildRow(e.key, e.value)),
                const Divider(),
                _buildRow('Total Expenses', data!['totalExpenses']!, isBold: true),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (data!['netProfit']! >= 0 ? StitchColors.success : StitchColors.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('NET PROFIT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: data!['netProfit']! >= 0 ? StitchColors.success : StitchColors.error)),
                      Text(formatPaise(data!['netProfit']!), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: data!['netProfit']! >= 0 ? StitchColors.success : StitchColors.error)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
      );

  Widget _buildRow(String label, int value, {bool isBold = false, bool isNegative = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 15, fontWeight: isBold ? FontWeight.w800 : FontWeight.w500)),
            Text(formatPaise(value), style: TextStyle(fontSize: 15, fontWeight: isBold ? FontWeight.w800 : FontWeight.w700, color: color)),
          ],
        ),
      );
}
