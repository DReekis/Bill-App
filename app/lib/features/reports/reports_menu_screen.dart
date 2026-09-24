import 'package:flutter/material.dart';

import '../../theme/stitch_theme.dart';
import '../banking/cash_bank_hub_screen.dart';
import '../dashboard/payables_screen.dart';
import '../dashboard/receivables_screen.dart';
import '../gst/gst_center_screen.dart';
import '../shell/transaction_history_screen.dart';
import 'balance_sheet_screen.dart';
import 'bill_wise_profit_screen.dart';
import 'day_book_screen.dart';
import 'party_statement_selector_screen.dart';
import 'pl_report_screen.dart';
import 'reports_screen.dart';
import 'sales_summary_report_screen.dart';
import 'stock_summary_report_screen.dart';

class ReportsMenuScreen extends StatelessWidget {
  const ReportsMenuScreen({super.key, this.isTab = false});
  final bool isTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Reports', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        automaticallyImplyLeading: !isTab,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Business Analytics & Insights Hero Banner
          _buildAnalyticsHeroBanner(context),
          const SizedBox(height: 20),

          // Section 1: POPULAR
          _buildSectionHeader('Popular'),
          const SizedBox(height: 8),
          _buildReportCardContainer([
            _ReportListItem(
              icon: Icons.receipt_long_outlined,
              title: 'Bill wise profit',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BillWiseProfitScreen())),
            ),
            _ReportListItem(
              icon: Icons.currency_rupee_rounded,
              title: 'Sales Summary',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesSummaryReportScreen())),
            ),
            _ReportListItem(
              icon: Icons.menu_book_outlined,
              title: 'Daybook',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DayBookScreen())),
            ),
            _ReportListItem(
              icon: Icons.trending_up_rounded,
              title: 'Profit and Loss',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PLReportScreen())),
            ),
            _ReportListItem(
              icon: Icons.badge_outlined,
              title: 'Party Statement (Ledger)',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyStatementSelectorScreen())),
            ),
            _ReportListItem(
              icon: Icons.inventory_2_outlined,
              title: 'Stock Summary',
              subtitle: 'A summary of price & stock of all items',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockSummaryReportScreen())),
            ),
            _ReportListItem(
              icon: Icons.balance_rounded,
              title: 'Balance Sheet',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BalanceSheetScreen())),
            ),
            _ReportListItem(
              icon: Icons.account_balance_outlined,
              title: 'Cash and Bank (All Payments)',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashBankHubScreen())),
            ),
          ]),
          const SizedBox(height: 24),

          // Section 2: MORE
          _buildSectionHeader('More'),
          const SizedBox(height: 8),
          _buildReportCardContainer([
            _ReportListItem(
              icon: Icons.people_outline_rounded,
              title: 'Party Reports',
              onTap: () => _showPartyReportsModal(context),
            ),
            _ReportListItem(
              icon: Icons.widgets_outlined,
              title: 'Item Reports',
              onTap: () => _showItemReportsModal(context),
            ),
            _ReportListItem(
              icon: Icons.receipt_outlined,
              title: 'GST Reports',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GstCenterScreen())),
            ),
            _ReportListItem(
              icon: Icons.shopping_cart_outlined,
              title: 'Transaction Reports',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildAnalyticsHeroBanner(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.insights_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Analytics & Insights',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Turnover trends, expenses & top selling items',
                    style: TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildReportCardContainer(List<_ReportListItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(
                height: 1,
                thickness: 0.8,
                indent: 56,
                color: Color(0xFFF1F5F9),
              ),
          ],
        ],
      ),
    );
  }

  void _showPartyReportsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Party Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: StitchColors.primary),
              title: const Text('Party Statement (Ledger)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Complete chronological account statement'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyStatementSelectorScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_received_rounded, color: Color(0xFF1B8A4C)),
              title: const Text('All Receivables (Customer Balances)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Customers with outstanding balance to collect'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivablesScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_made_rounded, color: Color(0xFFC62828)),
              title: const Text('All Payables (Supplier Balances)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Suppliers with balance to pay'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PayablesScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showItemReportsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Item & Inventory Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: StitchColors.primary),
              title: const Text('Stock Summary', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Inventory valuation and current quantities'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StockSummaryReportScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              title: const Text('Low Stock Alerts', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Items running below reorder threshold'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StockSummaryReportScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline_rounded, color: Color(0xFF4F46E5)),
              title: const Text('Best Selling Products', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Top items ranked by volume & revenue'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportListItem extends StatelessWidget {
  const _ReportListItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF5B4DBC), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF5B4DBC)),
            ],
          ),
        ),
      ),
    );
  }
}
