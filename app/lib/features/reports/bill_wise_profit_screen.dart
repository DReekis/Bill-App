import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../sales/invoice_detail_screen.dart';

class BillWiseProfitScreen extends StatefulWidget {
  const BillWiseProfitScreen({super.key});

  @override
  State<BillWiseProfitScreen> createState() => _BillWiseProfitScreenState();
}

class _BillWiseProfitScreenState extends State<BillWiseProfitScreen> {
  String period = 'This Month';
  DateTime? customFrom;
  DateTime? customTo;
  String profitFilter = 'All'; // 'All', 'Profit', 'Loss'
  String searchQuery = '';
  final Set<int> _expandedInvoiceIds = {};

  bool loading = true;
  String? error;
  List<BillProfitRecord> allRecords = [];

  String get fromDateStr {
    final now = DateTime.now();
    switch (period) {
      case 'Today':
        return todayIso();
      case 'This Week':
        return isoDate(now.subtract(Duration(days: now.weekday - 1)));
      case 'This Quarter':
        final qMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return isoDate(DateTime(now.year, qMonth, 1));
      case 'This Year':
        return isoDate(DateTime(now.year, 1, 1));
      case 'Custom':
        return customFrom != null ? isoDate(customFrom!) : isoDate(DateTime(now.year, now.month, 1));
      case 'This Month':
      default:
        return isoDate(DateTime(now.year, now.month, 1));
    }
  }

  String? get toDateStr {
    if (period == 'Custom' && customTo != null) {
      return isoDate(customTo!);
    }
    return null;
  }

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
      final records = await Repository.instance.billWiseProfitReport(
        bizId,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );
      if (!mounted) return;
      setState(() {
        allRecords = records;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  List<BillProfitRecord> get filteredRecords {
    return allRecords.where((r) {
      if (profitFilter == 'Profit' && !r.isProfitable) return false;
      if (profitFilter == 'Loss' && r.isProfitable) return false;
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchNum = r.number.toLowerCase().contains(q);
        final matchName = r.customerName.toLowerCase().contains(q);
        if (!matchNum && !matchName) return false;
      }
      return true;
    }).toList();
  }

  int get totalSales => allRecords.fold(0, (s, r) => s + r.taxable);
  int get totalCogs => allRecords.fold(0, (s, r) => s + r.cogs);
  int get totalProfit => allRecords.fold(0, (s, r) => s + r.profit);
  double get overallMargin => totalSales > 0 ? (totalProfit / totalSales) * 100 : 0.0;
  int get profitableCount => allRecords.where((r) => r.isProfitable).length;
  int get lossCount => allRecords.where((r) => !r.isProfitable).length;

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(
        start: customFrom ?? DateTime(now.year, now.month, 1),
        end: customTo ?? now,
      ),
    );
    if (picked != null) {
      setState(() {
        period = 'Custom';
        customFrom = picked.start;
        customTo = picked.end;
      });
      _load();
    }
  }

  Future<void> _exportExcel() async {
    final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
    final bizName = biz?.name ?? 'Business';
    final excel = xl.Excel.createExcel();
    final sheet = excel['Bill Wise Profit'];

    sheet.appendRow([
      'Invoice No',
      'Date',
      'Customer',
      'Sales (Taxable)',
      'Total Value',
      'COGS (Cost)',
      'Net Profit',
      'Margin %',
      'Status',
    ]);

    for (final r in filteredRecords) {
      sheet.appendRow([
        r.number,
        r.date,
        r.customerName,
        r.taxable / 100.0,
        r.total / 100.0,
        r.cogs / 100.0,
        r.profit / 100.0,
        double.parse(r.margin.toStringAsFixed(1)),
        r.isProfitable ? 'Profit' : 'Loss',
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final filename = 'Bill_Wise_Profit_${period.replaceAll(' ', '_')}_${todayIso()}.xlsx';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Bill Wise Profit Report - $bizName',
    );
  }

  Future<void> _exportPdf() async {
    final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
    final bizName = biz?.name ?? 'Business';
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Bill Wise Profit & Loss Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(bizName, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text('Period: $period ($fromDateStr to ${toDateStr ?? todayIso()})', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${todayIso()}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    pw.Text('Net Profit: Rs ${formatPaise(totalProfit)} (${overallMargin.toStringAsFixed(1)}%)',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: totalProfit >= 0 ? PdfColors.green700 : PdfColors.red700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Invoice No', 'Date', 'Customer', 'Sale (Rs)', 'Cost (Rs)', 'Profit (Rs)', 'Margin'],
            data: filteredRecords
                .map((r) => [
                      r.number,
                      r.date,
                      r.customerName,
                      formatPaise(r.taxable),
                      formatPaise(r.cogs),
                      (r.profit >= 0 ? '+' : '') + formatPaise(r.profit),
                      '${r.margin.toStringAsFixed(1)}%',
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF3F51B5)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Bill_Wise_Profit.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Bill Wise Profit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, size: 20),
            tooltip: 'Export Excel',
            onPressed: allRecords.isEmpty ? null : _exportExcel,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined, size: 20),
            tooltip: 'Print / Export PDF',
            onPressed: allRecords.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Period selector pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in ['Today', 'This Week', 'This Month', 'This Quarter', 'This Year'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p),
                        selected: period == p,
                        onSelected: (sel) {
                          if (sel) {
                            setState(() => period = p);
                            _load();
                          }
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.date_range_rounded, size: 16),
                      label: Text(period == 'Custom' && customFrom != null
                          ? '${displayDate(isoDate(customFrom!))} - ${displayDate(isoDate(customTo ?? DateTime.now()))}'
                          : 'Custom Date'),
                      backgroundColor: period == 'Custom' ? StitchColors.primary.withValues(alpha: 0.15) : null,
                      onPressed: _selectCustomRange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Top KPI Banner Card
            _buildKpiBanner(),
            const SizedBox(height: 14),

            // Search Bar & Filter Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
              ),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by bill no. or party name...',
                  hintStyle: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                  border: InputBorder.none,
                  icon: Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                ),
                onChanged: (val) => setState(() => searchQuery = val.trim()),
              ),
            ),
            const SizedBox(height: 10),

            // Profit / Loss filter chips
            Row(
              children: [
                _filterChip('All', 'All (${allRecords.length})', null),
                const SizedBox(width: 8),
                _filterChip('Profit', 'Profit ($profitableCount)', const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                _filterChip('Loss', 'Loss ($lossCount)', const Color(0xFFDC2626)),
              ],
            ),
            const SizedBox(height: 12),

            // Content List
            if (loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
                child: Text('Error loading report: $error', style: const TextStyle(color: Color(0xFF991B1B))),
              )
            else if (filteredRecords.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      searchQuery.isNotEmpty ? 'No invoices match "$searchQuery"' : 'No invoices generated for this period',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                    ),
                  ],
                ),
              )
            else
              for (final record in filteredRecords) ...[
                _buildBillCard(record),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpiBanner() {
    final isPos = totalProfit >= 0;
    final profitColor = isPos ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Net Profit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      (isPos ? '+' : '') + formatPaise(totalProfit),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: profitColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: profitColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isPos ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 18, color: profitColor),
                    const SizedBox(width: 4),
                    Text(
                      '${overallMargin.toStringAsFixed(1)}% Margin',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: profitColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _kpiSubItem(
                  label: 'Total Turnover',
                  value: formatPaise(totalSales),
                  icon: Icons.currency_rupee_rounded,
                  color: const Color(0xFF1E3A8A),
                ),
              ),
              Container(width: 1, height: 32, color: StitchColors.outline),
              Expanded(
                child: _kpiSubItem(
                  label: 'COGS (Cost)',
                  value: formatPaise(totalCogs),
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF64748B),
                ),
              ),
              Container(width: 1, height: 32, color: StitchColors.outline),
              Expanded(
                child: _kpiSubItem(
                  label: 'Bills Count',
                  value: '${allRecords.length}',
                  icon: Icons.receipt_outlined,
                  color: const Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiSubItem({required String label, required String value, required IconData icon, required Color color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _filterChip(String key, String label, Color? activeColor) {
    final sel = profitFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: activeColor?.withValues(alpha: 0.15) ?? StitchColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: sel ? (activeColor ?? StitchColors.primary) : StitchColors.textPrimary,
      ),
      onSelected: (val) {
        if (val) setState(() => profitFilter = key);
      },
    );
  }

  Widget _buildBillCard(BillProfitRecord record) {
    final isExpanded = _expandedInvoiceIds.contains(record.invoiceId);
    final profitColor = record.isProfitable ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final profitBg = record.isProfitable ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedInvoiceIds.remove(record.invoiceId);
                } else {
                  _expandedInvoiceIds.add(record.invoiceId);
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, size: 20, color: Color(0xFF4F46E5)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  record.number,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: StitchColors.textPrimary),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(color: profitBg, borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    '${record.margin >= 0 ? '+' : ''}${record.margin.toStringAsFixed(1)}%',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: profitColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  record.customerName,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                ),
                                const Text(' • ', style: TextStyle(color: StitchColors.textSecondary)),
                                Text(
                                  displayDate(record.date),
                                  style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sale Amount', style: TextStyle(fontSize: 10.5, color: StitchColors.textSecondary)),
                            const SizedBox(height: 1),
                            Text(formatPaise(record.taxable), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Cost (COGS)', style: TextStyle(fontSize: 10.5, color: StitchColors.textSecondary)),
                            const SizedBox(height: 1),
                            Text(formatPaise(record.cogs), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Gross Profit', style: TextStyle(fontSize: 10.5, color: StitchColors.textSecondary)),
                            const SizedBox(height: 1),
                            Text(
                              (record.profit >= 0 ? '+' : '') + formatPaise(record.profit),
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: profitColor),
                            ),
                          ],
                        ),
                        Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20, color: StitchColors.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFAFAFA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Item Breakdown', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: record.invoiceId)),
                          );
                        },
                        child: const Row(
                          children: [
                            Text('View Invoice', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                            Icon(Icons.chevron_right_rounded, size: 16, color: StitchColors.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (record.items.isEmpty)
                    const Text('No itemized records found', style: TextStyle(fontSize: 12, color: Colors.grey))
                  else
                    for (final it in record.items) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  Text('${it.quantity} ${it.unit} @ Rs ${formatPaise(it.salePrice)}',
                                      style: const TextStyle(fontSize: 10.5, color: StitchColors.textSecondary)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    (it.profit >= 0 ? '+' : '') + formatPaise(it.profit),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: it.profit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                    ),
                                  ),
                                  Text(
                                    'Cost: Rs ${formatPaise(it.costPrice)} (${it.margin.toStringAsFixed(0)}%)',
                                    style: const TextStyle(fontSize: 10, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (it != record.items.last) const Divider(height: 8, color: Color(0xFFE2E8F0)),
                    ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
