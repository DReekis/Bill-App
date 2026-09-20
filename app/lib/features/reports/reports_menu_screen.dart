import 'package:flutter/material.dart';
import '../../theme/stitch_theme.dart';
import '../banking/cash_bank_hub_screen.dart';
import '../gst/gst_center_screen.dart';
import '../shell/transaction_history_screen.dart';
import 'day_book_screen.dart';
import 'balance_sheet_screen.dart';
import 'pl_report_screen.dart';
import 'bank_transfer_form.dart';
import 'reports_screen.dart';

class ReportsMenuScreen extends StatelessWidget {
  const ReportsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Compliance', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportTile(
            icon: Icons.insights_rounded,
            title: 'Business Analytics & Insights',
            subtitle: 'Sales, Profit, Expenses & Best Selling Items',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.account_balance_outlined,
            title: 'GST Compliance Center',
            subtitle: 'GSTR-1, GSTR-2B, GSTR-3B & HSN Summary',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GstCenterScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Cash & Bank Accounts Hub',
            subtitle: 'Live balances, transfers & cheque register',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashBankHubScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.assignment_outlined,
            title: 'Orders & Estimates',
            subtitle: 'Pending and converted quotes',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.auto_stories_outlined,
            title: 'Day Book',
            subtitle: 'Daily transaction log',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DayBookScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Balance Sheet',
            subtitle: 'Assets, Liabilities & Equity',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BalanceSheetScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.analytics_outlined,
            title: 'Profit & Loss',
            subtitle: 'Income Statement',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PLReportScreen())),
          ),
          const SizedBox(height: 16),
          _ReportTile(
            icon: Icons.swap_horiz_rounded,
            title: 'Bank Transfer',
            subtitle: 'Move funds between accounts',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankTransferForm())),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: StitchColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: StitchColors.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: StitchColors.textSecondary),
            ],
          ),
        ),
      );
}
