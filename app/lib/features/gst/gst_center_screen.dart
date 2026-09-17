import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import 'gstr1_report_screen.dart';
import 'gstr2b_screen.dart';
import 'gstr3b_screen.dart';
import 'hsn_summary_screen.dart';

class GstCenterScreen extends StatefulWidget {
  const GstCenterScreen({super.key});

  @override
  State<GstCenterScreen> createState() => _GstCenterScreenState();
}

class _GstCenterScreenState extends State<GstCenterScreen> {
  bool loading = true;
  GstTaxSummary? summary;
  Business? business;
  String periodLabel = 'This Month';
  DateTime? fromDate;
  DateTime? toDate;

  @override
  void initState() {
    super.initState();
    _applyPeriod('This Month');
  }

  void _applyPeriod(String label) {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    if (label == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month + 1, 0);
    } else if (label == 'Last Month') {
      from = DateTime(now.year, now.month - 1, 1);
      to = DateTime(now.year, now.month, 0);
    } else if (label == 'This Quarter') {
      final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      from = DateTime(now.year, qStartMonth, 1);
      to = DateTime(now.year, qStartMonth + 3, 0);
    } else {
      from = null;
      to = null;
    }

    setState(() {
      periodLabel = label;
      fromDate = from;
      toDate = to;
    });
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => loading = true);

    try {
      final b = await Repository.instance.getBusiness(bizId);
      final s = await Repository.instance.getGstTaxSummary(bizId, from: fromDate, to: toDate);
      if (!mounted) return;
      setState(() {
        business = b;
        summary = s;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _shareWithCa() {
    if (summary == null) return;
    final b = business;
    final text = StringBuffer()
      ..writeln('GST SUMMARY REPORT')
      ..writeln('Business: ${b?.name ?? 'Business'}')
      ..writeln('GSTIN: ${b?.gstin ?? 'Unregistered'}')
      ..writeln('Period: $periodLabel')
      ..writeln('-----------------------------------')
      ..writeln('Total Sales (Taxable): ${formatPaise(summary!.totalSalesTaxable)}')
      ..writeln('Output CGST: ${formatPaise(summary!.totalOutputCgst)}')
      ..writeln('Output SGST: ${formatPaise(summary!.totalOutputSgst)}')
      ..writeln('Output IGST: ${formatPaise(summary!.totalOutputIgst)}')
      ..writeln('Total Output Tax: ${formatPaise(summary!.totalOutputTax)}')
      ..writeln('-----------------------------------')
      ..writeln('Total Purchases: ${formatPaise(summary!.totalPurchasesTaxable)}')
      ..writeln('Eligible Input Tax Credit: ${formatPaise(summary!.totalInputTaxCredit)}')
      ..writeln('-----------------------------------')
      ..writeln('NET GST PAYABLE: ${formatPaise(summary!.netTaxPayable)}')
      ..writeln('  CGST Payable: ${formatPaise(summary!.netCgstPayable)}')
      ..writeln('  SGST Payable: ${formatPaise(summary!.netSgstPayable)}')
      ..writeln('  IGST Payable: ${formatPaise(summary!.netIgstPayable)}')
      ..writeln('Total Invoices: ${summary!.totalInvoices} (B2B: ${summary!.b2bCount}, B2C: ${summary!.b2cCount})')
      ..writeln('Generated via Billket GST Center');

    Share.share(text.toString(), subject: 'GST Report - ${b?.name ?? 'Business'} ($periodLabel)');
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final b = business;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: StitchColors.primary,
              child: Text(
                (b?.name.isNotEmpty == true ? b!.name[0] : 'G').toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            const Text('GST Center', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share with CA',
            icon: const Icon(Icons.share_outlined, color: StitchColors.primary),
            onPressed: _shareWithCa,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  // Period Selector Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: StitchColors.outline),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        PopupMenuButton<String>(
                          initialValue: periodLabel,
                          onSelected: _applyPeriod,
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 16, color: StitchColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                periodLabel,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StitchColors.primary),
                              ),
                              const Icon(Icons.arrow_drop_down_rounded, color: StitchColors.primary),
                            ],
                          ),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'This Month', child: Text('This Month')),
                            PopupMenuItem(value: 'Last Month', child: Text('Last Month')),
                            PopupMenuItem(value: 'This Quarter', child: Text('This Quarter')),
                            PopupMenuItem(value: 'All Time', child: Text('All Time')),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 16, color: StitchColors.success),
                            const SizedBox(width: 4),
                            Text(
                              b?.gstin?.isNotEmpty == true ? 'GSTIN Active' : 'Unregistered',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Filing Status Alert Banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: const Border(
                        left: BorderSide(color: StitchColors.error, width: 4),
                        top: BorderSide(color: Color(0xFFFEE2E2)),
                        right: BorderSide(color: Color(0xFFFEE2E2)),
                        bottom: BorderSide(color: Color(0xFFFEE2E2)),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: StitchColors.error, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GSTR-3B Monthly Return',
                                style: TextStyle(color: StitchColors.error, fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Review sales & ITC balances before filing to prevent interest & late fees.',
                                style: TextStyle(color: StitchColors.textSecondary.withValues(alpha: 0.9), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: StitchColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => Gstr3bScreen(summary: s, period: periodLabel)),
                          ),
                          child: const Text('Review 3B', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Total GST Payable Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: StitchColors.outline),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total GST Payable (Net)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatPaise(s?.netTaxPayable ?? 0),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: StitchColors.primary,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _taxPill('CGST', formatPaise(s?.netCgstPayable ?? 0)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _taxPill('SGST', formatPaise(s?.netSgstPayable ?? 0)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _taxPill('IGST', formatPaise(s?.netIgstPayable ?? 0)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Output Tax vs Input Tax Credit
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.trending_up_rounded, size: 16, color: StitchColors.error),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Output Tax (Sales)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.error),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                formatPaise(s?.totalOutputTax ?? 0),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'on ${formatPaise(s?.totalSalesTaxable ?? 0)} sales',
                                style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.trending_down_rounded, size: 16, color: StitchColors.success),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Input Tax Credit',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.success),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                formatPaise(s?.totalInputTaxCredit ?? 0),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'from ${formatPaise(s?.totalPurchasesTaxable ?? 0)} purchases',
                                style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Returns & Reports Section
                  const Text(
                    'Returns & GST Reports',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 1.15,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _ReportNavTile(
                        icon: Icons.receipt_long_rounded,
                        badgeColor: const Color(0xFFE1E0FF),
                        iconColor: StitchColors.primary,
                        title: 'GSTR-1',
                        subtitle: 'Outward Supplies',
                        metric: '${s?.totalInvoices ?? 0} Invoices',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Gstr1ReportScreen(fromDate: fromDate, toDate: toDate, periodLabel: periodLabel),
                          ),
                        ),
                      ),
                      _ReportNavTile(
                        icon: Icons.compare_arrows_rounded,
                        badgeColor: const Color(0xFFE0F2FE),
                        iconColor: const Color(0xFF0284C7),
                        title: 'GSTR-2B',
                        subtitle: 'ITC Reconciliation',
                        metric: 'Portal vs Books',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Gstr2bScreen(fromDate: fromDate, toDate: toDate),
                          ),
                        ),
                      ),
                      _ReportNavTile(
                        icon: Icons.description_rounded,
                        badgeColor: const Color(0xFFFEF3C7),
                        iconColor: const Color(0xFFD97706),
                        title: 'GSTR-3B',
                        subtitle: 'Monthly Filing Summary',
                        metric: 'Tax Offset & Cash',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Gstr3bScreen(summary: s, period: periodLabel),
                          ),
                        ),
                      ),
                      _ReportNavTile(
                        icon: Icons.category_rounded,
                        badgeColor: const Color(0xFFDCFCE7),
                        iconColor: StitchColors.success,
                        title: 'HSN Summary',
                        subtitle: 'Tax Rate Breakdown',
                        metric: '${s?.hsnCount ?? 0} HSN Codes',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HsnSummaryScreen(fromDate: fromDate, toDate: toDate),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _taxPill(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: StitchColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
          ],
        ),
      );
}

class _ReportNavTile extends StatelessWidget {
  const _ReportNavTile({
    required this.icon,
    required this.badgeColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.onTap,
  });

  final IconData icon;
  final Color badgeColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StitchColors.outline),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: StitchColors.textTertiary),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(metric, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: iconColor)),
                ],
              ),
            ],
          ),
        ),
      );
}
