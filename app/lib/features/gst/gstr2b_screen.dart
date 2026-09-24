import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gst_reports_service.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class Gstr2bScreen extends StatefulWidget {
  const Gstr2bScreen({
    super.key,
    this.fromDate,
    this.toDate,
  });

  final DateTime? fromDate;
  final DateTime? toDate;

  @override
  State<Gstr2bScreen> createState() => _Gstr2bScreenState();
}

class _Gstr2bScreenState extends State<Gstr2bScreen> {
  bool loading = true;
  List<Gstr2bEntry> allEntries = [];
  String filterTab = 'All';
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
      final list = await Repository.instance.getGstr2bData(
        bizId,
        from: widget.fromDate,
        to: widget.toDate,
      );
      if (!mounted) return;
      setState(() {
        business = b;
        allEntries = list;
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
      returnType: GstReturnType.gstr2,
      business: b,
      fromDate: widget.fromDate,
      toDate: widget.toDate,
      periodLabel: 'This Month',
    );
  }

  Future<void> _contactSupplier(Gstr2bEntry item) async {
    final bizId = context.read<Session>().businessId;
    String phone = '';
    if (bizId != null) {
      final suppliers = await Repository.instance.suppliers(bizId);
      for (final s in suppliers) {
        if ((item.supplierGstin.isNotEmpty && s.gstin != null && s.gstin!.toLowerCase() == item.supplierGstin.toLowerCase()) ||
            s.name.toLowerCase() == item.supplierName.toLowerCase()) {
          phone = s.phone ?? '';
          break;
        }
      }
    }

    final diffText = item.diffValue != 0 ? ' (Tax discrepancy: ${formatPaise(item.diffTax)})' : '';
    final message = 'Dear ${item.supplierName},\n\n'
        'Regarding Invoice #${item.invoiceNumber} dated ${item.invoiceDate} for ${formatPaise(item.invoiceValue)}$diffText:\n'
        'This invoice status in our GSTR-2B is "${item.matchStatus}".\n'
        'Kindly verify and file/rectify this invoice on the GST Portal so that we can claim eligible Input Tax Credit (ITC).\n\n'
        'Thank you.';

    if (phone.isNotEmpty) {
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final formattedPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;
      final uri = Uri.parse('https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message)}');
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    Share.share(message, subject: 'GST Notice: Invoice #${item.invoiceNumber} - ${item.supplierName}');
  }

  void _accept2b(Gstr2bEntry entry) {
    setState(() {
      final idx = allEntries.indexWhere((e) => e.id == entry.id);
      if (idx != -1) {
        allEntries[idx] = Gstr2bEntry(
          id: entry.id,
          supplierGstin: entry.supplierGstin,
          supplierName: entry.supplierName,
          invoiceNumber: entry.invoiceNumber,
          invoiceDate: entry.invoiceDate,
          invoiceValue: entry.invoiceValue + entry.diffValue,
          taxableValue: entry.taxableValue,
          igst: entry.igst,
          cgst: entry.cgst,
          sgst: entry.sgst,
          itcEligibility: entry.itcEligibility,
          matchStatus: 'Matched',
          expenseId: entry.expenseId,
        );
      }
    });
    showAppMessage(context, 'Accepted GSTR-2B portal value for ${entry.invoiceNumber}');
  }

  @override
  Widget build(BuildContext context) {
    final matchedCount = allEntries.where((e) => e.matchStatus == 'Matched').length;
    final mismatchedCount = allEntries.where((e) => e.matchStatus.contains('Mismatch')).length;
    final missingCount = allEntries.where((e) => e.matchStatus.contains('Missing')).length;

    final displayed = allEntries.where((e) {
      if (filterTab == 'Matched') return e.matchStatus == 'Matched';
      if (filterTab == 'Mismatches') return e.matchStatus.contains('Mismatch');
      if (filterTab == 'Missing') return e.matchStatus.contains('Missing');
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('GSTR-2B Reconciliation', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: StitchColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: business != null ? _openExportModal : null,
              icon: const Icon(Icons.file_download_rounded, size: 16),
              label: const Text('Export GSTR-2', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          IconButton(
            tooltip: 'Sync Portal',
            icon: const Icon(Icons.sync_rounded, color: StitchColors.primary),
            onPressed: () {
              showAppMessage(context, 'GSTR-2B synced with GSTN Portal');
              _load();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // Top Bento Metric Cards
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        'Matched Invoices',
                        matchedCount.toString(),
                        'ITC Ready',
                        StitchColors.success,
                        const Color(0xFFDCFCE7),
                        Icons.check_circle_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCard(
                        'Mismatches',
                        mismatchedCount.toString(),
                        'Needs Review',
                        const Color(0xFFD97706),
                        const Color(0xFFFEF3C7),
                        Icons.error_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCard(
                        'Missing in 2B',
                        missingCount.toString(),
                        'ITC Deferred',
                        StitchColors.error,
                        const Color(0xFFFEE2E2),
                        Icons.warning_amber_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Filter Tabs Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All (${allEntries.length})', 'All'),
                      const SizedBox(width: 8),
                      _filterChip('Matched ($matchedCount)', 'Matched'),
                      const SizedBox(width: 8),
                      _filterChip('Mismatches ($mismatchedCount)', 'Mismatches'),
                      const SizedBox(width: 8),
                      _filterChip('Missing in 2B ($missingCount)', 'Missing'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Entries List
                if (displayed.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: const Text('No invoices in this category', style: TextStyle(color: StitchColors.textSecondary)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final item = displayed[idx];
                      final isMatched = item.matchStatus == 'Matched';
                      final isTaxMismatch = item.matchStatus == 'Tax Mismatch';
                      final isValueMismatch = item.matchStatus == 'Value Mismatch';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isMatched
                                ? StitchColors.outline
                                : (isTaxMismatch || isValueMismatch ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5)),
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.supplierName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Inv: ${item.invoiceNumber} • ${item.invoiceDate}',
                                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isMatched
                                        ? const Color(0xFFDCFCE7)
                                        : (isTaxMismatch || isValueMismatch ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.matchStatus,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isMatched
                                          ? StitchColors.success
                                          : (isTaxMismatch || isValueMismatch ? const Color(0xFFB45309) : StitchColors.error),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Comparison Box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('As per Books', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text('Value: ${formatPaise(item.invoiceValue)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                        Text('Tax: ${formatPaise(item.cgst + item.sgst + item.igst)}', style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1, height: 40, color: StitchColors.outline),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('As per GSTR-2B', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Value: ${formatPaise(item.invoiceValue + item.diffValue)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: item.diffValue != 0 ? StitchColors.error : StitchColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Tax: ${formatPaise(item.cgst + item.sgst + item.igst + item.diffTax)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: item.diffTax != 0 ? const Color(0xFFD97706) : StitchColors.textSecondary,
                                            fontWeight: item.diffTax != 0 ? FontWeight.w700 : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (!isMatched) ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => _contactSupplier(item),
                                    child: const Text('Contact Supplier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: StitchColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      minimumSize: Size.zero,
                                    ),
                                    onPressed: () => _accept2b(item),
                                    child: const Text('Accept 2B', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  Widget _metricCard(String title, String count, String subtitle, Color textColor, Color bgColor, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: StitchColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: textColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: StitchColors.textSecondary)),
          ],
        ),
      );

  Widget _filterChip(String label, String value) {
    final active = filterTab == value;
    return InkWell(
      onTap: () => setState(() => filterTab = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? StitchColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? StitchColors.primary : StitchColors.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : StitchColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
