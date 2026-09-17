import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

class Gstr3bScreen extends StatefulWidget {
  const Gstr3bScreen({
    super.key,
    this.summary,
    this.period = 'Current Month',
  });

  final GstTaxSummary? summary;
  final String period;

  @override
  State<Gstr3bScreen> createState() => _Gstr3bScreenState();
}

class _Gstr3bScreenState extends State<Gstr3bScreen> {
  bool loading = true;
  Gstr3bSummary? gstr3b;

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
      final s = await Repository.instance.getGstr3bData(bizId, period: widget.period);
      if (!mounted) return;
      setState(() {
        gstr3b = s;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _shareWithCa() {
    final g = gstr3b;
    if (g == null) return;
    final text = StringBuffer()
      ..writeln('GSTR-3B MONTHLY FILING COMPUTATION')
      ..writeln('Period: ${g.period}')
      ..writeln('----------------------------------------')
      ..writeln('3.1 Outward Taxable Supplies: ${formatPaise(g.outwardTaxableSupplies)}')
      ..writeln('  CGST: ${formatPaise(g.outwardCgst)}')
      ..writeln('  SGST: ${formatPaise(g.outwardSgst)}')
      ..writeln('  IGST: ${formatPaise(g.outwardIgst)}')
      ..writeln('----------------------------------------')
      ..writeln('4. Eligible Input Tax Credit (ITC):')
      ..writeln('  CGST ITC: ${formatPaise(g.itcAvailableCgst)}')
      ..writeln('  SGST ITC: ${formatPaise(g.itcAvailableSgst)}')
      ..writeln('  IGST ITC: ${formatPaise(g.itcAvailableIgst)}')
      ..writeln('----------------------------------------')
      ..writeln('6.1 NET TAX PAYABLE (IN CASH): ${formatPaise(g.totalTaxPayableCash)}')
      ..writeln('  Net CGST Payable: ${formatPaise(g.netTaxPayableCgst)}')
      ..writeln('  Net SGST Payable: ${formatPaise(g.netTaxPayableSgst)}')
      ..writeln('  Net IGST Payable: ${formatPaise(g.netTaxPayableIgst)}')
      ..writeln('Generated via Billket GST Center');

    Share.share(text.toString(), subject: 'GSTR-3B Filing Summary (${g.period})');
  }

  @override
  Widget build(BuildContext context) {
    final g = gstr3b;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('GSTR-3B Monthly Return', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Share with CA',
            icon: const Icon(Icons.share_outlined, color: StitchColors.primary),
            onPressed: _shareWithCa,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // Period Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: StitchColors.outline),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: StitchColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            widget.period,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StitchColors.primary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Ready to File',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: StitchColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Table 3.1 Card: Outward Supplies
                _tableCard(
                  title: '3.1 Outward Taxable Supplies',
                  subtitle: 'Sales & services made during this tax period',
                  rows: [
                    ('Total Taxable Value', formatPaise(g?.outwardTaxableSupplies ?? 0), false),
                    ('Integrated Tax (IGST)', formatPaise(g?.outwardIgst ?? 0), false),
                    ('Central Tax (CGST)', formatPaise(g?.outwardCgst ?? 0), false),
                    ('State/UT Tax (SGST)', formatPaise(g?.outwardSgst ?? 0), false),
                    ('Cess', '₹0.00', false),
                  ],
                ),
                const SizedBox(height: 14),

                // Table 4 Card: Eligible ITC
                _tableCard(
                  title: '4. Eligible Input Tax Credit (ITC)',
                  subtitle: 'Taxes paid on business purchases & expenses',
                  rows: [
                    ('All Other ITC - Central Tax', formatPaise(g?.itcAvailableCgst ?? 0), false),
                    ('All Other ITC - State Tax', formatPaise(g?.itcAvailableSgst ?? 0), false),
                    ('All Other ITC - Integrated Tax', formatPaise(g?.itcAvailableIgst ?? 0), false),
                    ('Ineligible ITC (Section 17(5))', '₹0.00', false),
                  ],
                ),
                const SizedBox(height: 14),

                // Table 6.1 Card: Payment of Tax
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StitchColors.primary.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(color: StitchColors.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '6.1 Payment of Tax (Net Cash)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.primary),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: StitchColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Cash Ledger',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: StitchColors.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Tax Payable in Cash', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            formatPaise(g?.totalTaxPayableCash ?? 0),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: StitchColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: StitchColors.outline),
                      const SizedBox(height: 10),
                      _pillRow('Net CGST Payable', formatPaise(g?.netTaxPayableCgst ?? 0)),
                      const SizedBox(height: 4),
                      _pillRow('Net SGST Payable', formatPaise(g?.netTaxPayableSgst ?? 0)),
                      const SizedBox(height: 4),
                      _pillRow('Net IGST Payable', formatPaise(g?.netTaxPayableIgst ?? 0)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Share button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: StitchColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _shareWithCa,
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  label: const Text('Share GSTR-3B Computation with CA', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }

  Widget _tableCard({
    required String title,
    required String subtitle,
    required List<(String, String, bool)> rows,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: StitchColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
            const SizedBox(height: 12),
            const Divider(height: 1, color: StitchColors.outline),
            const SizedBox(height: 8),
            for (final r in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                    Text(
                      r.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: r.$3 ? FontWeight.w800 : FontWeight.w600,
                        color: StitchColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _pillRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      );
}
