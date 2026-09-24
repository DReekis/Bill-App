import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/gst_reports_service.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

class Gstr1ReportScreen extends StatefulWidget {
  const Gstr1ReportScreen({
    super.key,
    this.fromDate,
    this.toDate,
    this.periodLabel = 'This Month',
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final String periodLabel;

  @override
  State<Gstr1ReportScreen> createState() => _Gstr1ReportScreenState();
}

class _Gstr1ReportScreenState extends State<Gstr1ReportScreen> {
  bool loading = true;
  List<Gstr1Section> sections = [];
  Business? business;

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
      final b = await Repository.instance.getBusiness(bizId);
      final s = await Repository.instance.getGstr1Data(
        bizId,
        from: widget.fromDate,
        to: widget.toDate,
      );
      if (!mounted) return;
      setState(() {
        business = b;
        sections = s;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openExportModal() {
    final b = business;
    if (b == null) return;
    showGstExportModal(
      context: context,
      returnType: GstReturnType.gstr1,
      business: b,
      fromDate: widget.fromDate,
      toDate: widget.toDate,
      periodLabel: widget.periodLabel,
    );
  }

  void _exportCsv() {
    final b = business;
    final csv = StringBuffer()
      ..writeln('GSTR-1 Outward Supplies Report - ${b?.name ?? 'Business'}')
      ..writeln('Period,${widget.periodLabel}')
      ..writeln('Section,Invoice/Note No,Date,Customer Name,GSTIN,Taxable Value,CGST,SGST,IGST,Total Value');

    for (final sec in sections) {
      for (final itm in sec.items) {
        final no = itm['number'] ?? '';
        final date = itm['date'] ?? '';
        final name = (itm['customer_name'] ?? itm['party_name'] ?? '').toString().replaceAll(',', ' ');
        final gstin = itm['customer_gstin'] ?? '';
        final taxable = ((itm['taxable'] as num?)?.toInt() ?? 0) / 100.0;
        final cgst = ((itm['cgst'] as num?)?.toInt() ?? 0) / 100.0;
        final sgst = ((itm['sgst'] as num?)?.toInt() ?? 0) / 100.0;
        final igst = ((itm['igst'] as num?)?.toInt() ?? 0) / 100.0;
        final total = ((itm['total'] as num?)?.toInt() ?? 0) / 100.0;
        csv.writeln('${sec.code},$no,$date,$name,$gstin,$taxable,$cgst,$sgst,$igst,$total');
      }
    }

    Share.share(csv.toString(), subject: 'GSTR-1 Report - ${b?.name ?? 'Business'} (${widget.periodLabel})');
  }

  @override
  Widget build(BuildContext context) {
    int totalTaxable = 0;
    int totalTax = 0;
    int totalInvoices = 0;

    for (final s in sections) {
      totalTaxable += s.taxableAmount;
      totalTax += s.totalTax;
      totalInvoices += s.count;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('GSTR-1 Sales Report', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: StitchColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: business != null ? _openExportModal : null,
              icon: const Icon(Icons.file_download_rounded, size: 16),
              label: const Text('Export Return', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          IconButton(
            tooltip: 'Share CSV',
            icon: const Icon(Icons.share_outlined, color: StitchColors.textSecondary),
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // Period Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 14, color: StitchColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            widget.periodLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: StitchColors.primary),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$totalInvoices Records',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: StitchColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Bento Grid Summary Metrics
                Row(
                  children: [
                    Expanded(
                      child: _metricCard('Total Taxable Value', formatPaise(totalTaxable), Icons.payments_outlined, const Color(0xFF2E3192)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricCard('Total Tax Amount', formatPaise(totalTax), Icons.account_balance_outlined, const Color(0xFF059669)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Sections List
                for (final section in sections) ...[
                  _SectionHeader(section: section),
                  const SizedBox(height: 8),
                  if (section.items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: StitchColors.outline),
                      ),
                      child: Center(
                        child: Text(
                          'No ${section.code} entries for this period',
                          style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: StitchColors.outline),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: section.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: StitchColors.outline),
                        itemBuilder: (context, idx) {
                          final itm = section.items[idx];
                          final no = itm['number'] ?? '';
                          final party = itm['customer_name'] ?? itm['party_name'] ?? 'Walk-in';
                          final gstin = itm['customer_gstin'] as String?;
                          final taxable = (itm['taxable'] as num?)?.toInt() ?? 0;
                          final cgst = (itm['cgst'] as num?)?.toInt() ?? 0;
                          final sgst = (itm['sgst'] as num?)?.toInt() ?? 0;
                          final igst = (itm['igst'] as num?)?.toInt() ?? 0;

                          return Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      no.toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StitchColors.primary),
                                    ),
                                    Text(
                                      formatPaise(taxable),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      party.toString(),
                                      style: const TextStyle(fontSize: 13, color: StitchColors.textPrimary, fontWeight: FontWeight.w500),
                                    ),
                                    const Text(
                                      'Taxable',
                                      style: TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                    ),
                                  ],
                                ),
                                if (gstin != null && gstin.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'GSTIN: $gstin',
                                    style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontFamily: 'monospace'),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        igst > 0 ? 'IGST' : 'CGST / SGST',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                      ),
                                      Text(
                                        igst > 0
                                            ? formatPaise(igst)
                                            : '${formatPaise(cgst)} + ${formatPaise(sgst)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: StitchColors.outline),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final Gstr1Section section;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        section.code,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        section.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  section.subtitle,
                  style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: StitchColors.outline),
            ),
            child: Text(
              '${section.count} inv',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      );
}
