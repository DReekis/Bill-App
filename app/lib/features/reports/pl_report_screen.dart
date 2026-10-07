import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

import 'date_filter_bar.dart';

class PLReportScreen extends StatefulWidget {
  const PLReportScreen({super.key});

  @override
  State<PLReportScreen> createState() => _PLReportScreenState();
}

class _PLReportScreenState extends State<PLReportScreen> {
  Map<String, int>? data;
  String _period = 'This Month';
  late DateTime _startDate;
  late DateTime _endDate;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final defaultRange = resolvePresetDateRange(_period);
    _startDate = defaultRange.start;
    _endDate = defaultRange.end;
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final from = isoDate(_startDate);
    final to = isoDate(_endDate);
    final res = await Repository.instance.profitAndLossReport(bizId, from, to);
    if (!mounted) return;
    setState(() {
      data = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Income Statement (P&L)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Column(
        children: [
          // Global Date Filter Bar at top of the view
          Container(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlobalDateFilterBar(
                  selectedPeriod: _period,
                  customStart: _startDate,
                  customEnd: _endDate,
                  onRangeChanged: (start, end, label) {
                    setState(() {
                      _startDate = start;
                      _endDate = end;
                      _period = label;
                    });
                    _load();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 14, color: StitchColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Period: ${displayDate(isoDate(_startDate))} to ${displayDate(isoDate(_endDate))}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : data == null
                    ? const Center(child: Text('No P&L data available'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildHeader('Operating Revenue'),
                            _buildRow('Gross Sales', data!['grossSales'] ?? 0),
                            _buildRow('Sales Returns', -(data!['salesReturn'] ?? 0), isNegative: true),
                            const Divider(),
                            _buildRow('Net Revenue', data!['netSales'] ?? 0, isBold: true),
                            const SizedBox(height: 24),
                            _buildHeader('Cost of Goods Sold'),
                            _buildRow('COGS', data!['cogs'] ?? 0, isNegative: true),
                            const Divider(),
                            _buildRow('GROSS PROFIT', data!['grossProfit'] ?? 0, isBold: true, color: StitchColors.primary),
                            const SizedBox(height: 32),
                            _buildHeader('Operating Expenses'),
                            ...data!.entries
                                .where((e) => !['grossSales', 'salesReturn', 'netSales', 'cogs', 'grossProfit', 'totalExpenses', 'netProfit'].contains(e.key))
                                .map((e) => _buildRow(e.key, e.value)),
                            const Divider(),
                            _buildRow('Total Expenses', data!['totalExpenses'] ?? 0, isBold: true),
                            const SizedBox(height: 40),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: ((data!['netProfit'] ?? 0) >= 0 ? StitchColors.success : StitchColors.error).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: ((data!['netProfit'] ?? 0) >= 0 ? StitchColors.success : StitchColors.error).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'NET PROFIT',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: (data!['netProfit'] ?? 0) >= 0 ? StitchColors.success : StitchColors.error,
                                    ),
                                  ),
                                  Text(
                                    formatPaise(data!['netProfit'] ?? 0),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: (data!['netProfit'] ?? 0) >= 0 ? StitchColors.success : StitchColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
