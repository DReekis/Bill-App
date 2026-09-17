import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';

class HsnSummaryScreen extends StatefulWidget {
  const HsnSummaryScreen({
    super.key,
    this.fromDate,
    this.toDate,
  });

  final DateTime? fromDate;
  final DateTime? toDate;

  @override
  State<HsnSummaryScreen> createState() => _HsnSummaryScreenState();
}

class _HsnSummaryScreenState extends State<HsnSummaryScreen> {
  bool loading = true;
  List<HsnTaxSummaryItem> allItems = [];
  List<HsnTaxSummaryItem> filteredItems = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => loading = true);

    try {
      final items = await Repository.instance.getHsnSummary(
        bizId,
        from: widget.fromDate,
        to: widget.toDate,
      );
      if (!mounted) return;
      setState(() {
        allItems = items;
        filteredItems = items;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => filteredItems = allItems);
      return;
    }
    setState(() {
      filteredItems = allItems.where((i) {
        return i.hsn.toLowerCase().contains(q) || i.description.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _exportHsn() {
    final csv = StringBuffer()
      ..writeln('HSN Code,Description,UQC,Quantity,Taxable Value,GST Rate,Total Tax,Total Value');
    for (final i in filteredItems) {
      final taxable = i.taxableValue / 100.0;
      final tax = i.totalTax / 100.0;
      final val = i.totalValue / 100.0;
      final desc = i.description.replaceAll(',', ' ');
      csv.writeln('${i.hsn},$desc,${i.uqc},${i.totalQuantity},$taxable,${i.gstRate}%,$tax,$val');
    }
    Share.share(csv.toString(), subject: 'HSN Tax Summary Export');
  }

  @override
  Widget build(BuildContext context) {
    int totalTaxable = 0;
    int totalTax = 0;
    for (final i in filteredItems) {
      totalTaxable += i.taxableValue;
      totalTax += i.totalTax;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('HSN Tax Summary', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_rounded, color: StitchColors.primary),
            onPressed: _exportHsn,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // Search Input
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StitchColors.outline),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search HSN Code or Description...',
                      hintStyle: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, color: StitchColors.textSecondary, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearch('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Top Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StitchColors.outline),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: StitchColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.category_rounded, color: StitchColors.primary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total HSN Categorized', style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                                const SizedBox(height: 2),
                                Text(
                                  '${filteredItems.length} HSN Codes',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: StitchColors.outline),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Taxable Value', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                const SizedBox(height: 2),
                                Text(
                                  formatPaise(totalTaxable),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total GST Collected', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                const SizedBox(height: 2),
                                Text(
                                  formatPaise(totalTax),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: StitchColors.success),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Table / Card List
                if (filteredItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: const Text('No HSN codes found', style: TextStyle(color: StitchColors.textSecondary)),
                  )
                  else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: StitchColors.outline),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: StitchColors.outline),
                      itemBuilder: (context, idx) {
                        final item = filteredItems[idx];
                        return Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF4FF),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'HSN ${item.hsn}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                            color: StitchColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${item.gstRate}% GST',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: StitchColors.success),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    formatPaise(item.totalValue),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.description,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Qty Sold: ${item.totalQuantity.toStringAsFixed(1)} ${item.uqc}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                  Text(
                                    'Taxable: ${formatPaise(item.taxableValue)} • Tax: ${formatPaise(item.totalTax)}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
