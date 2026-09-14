import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  Map<String, int>? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    final res = await Repository.instance.balanceSheet(bizId);
    setState(() => data = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance Sheet', style: TextStyle(fontWeight: FontWeight.w800))),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('ASSETS'),
                _buildRow('Cash in Hand', data!['cash']!),
                _buildRow('Bank Accounts', data!['bank']!),
                _buildRow('Inventory (Stock Value)', data!['stock']!),
                _buildRow('Sundry Debtors (Receivables)', data!['receivables']!),
                const Divider(thickness: 1.5, color: StitchColors.primary),
                _buildRow('Total Assets', data!['totalAssets']!, isTotal: true),
                const SizedBox(height: 32),
                _buildSectionHeader('LIABILITIES'),
                _buildRow('Sundry Creditors (Payables)', data!['payables']!),
                const Divider(thickness: 1.5, color: StitchColors.error),
                _buildRow('Total Liabilities', data!['totalLiabilities']!, isTotal: true),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: StitchColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StitchColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('NET WORTH', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: StitchColors.primary)),
                      Text(formatPaise(data!['equity']!), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: StitchColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.textSecondary, letterSpacing: 1.2)),
      );

  Widget _buildRow(String label, int value, {bool isTotal = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 15, fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600)),
            Text(formatPaise(value), style: TextStyle(fontSize: 15, fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700)),
          ],
        ),
      );
}
