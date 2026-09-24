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

class SalesSummaryReportScreen extends StatefulWidget {
  const SalesSummaryReportScreen({super.key});

  @override
  State<SalesSummaryReportScreen> createState() => _SalesSummaryReportScreenState();
}

class _SalesSummaryReportScreenState extends State<SalesSummaryReportScreen> {
  String period = 'This Month';
  DateTime? customFrom;
  DateTime? customTo;
  String searchQuery = '';

  bool loading = true;
  String? error;
  SalesSummaryReportData? data;

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
      final res = await Repository.instance.salesSummaryReport(
        bizId,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );
      if (!mounted) return;
      setState(() {
        data = res;
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
    if (data == null) return;
    final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
    final bizName = biz?.name ?? 'Business';
    final excel = xl.Excel.createExcel();
    final sheet = excel['Sales Summary'];

    sheet.appendRow([
      'Invoice No',
      'Date',
      'Customer',
      'Taxable (Rs)',
      'CGST (Rs)',
      'SGST (Rs)',
      'IGST (Rs)',
      'Total Amount (Rs)',
      'Paid Amount (Rs)',
      'Payment Mode',
      'Status',
    ]);

    for (final inv in data!.invoices) {
      sheet.appendRow([
        inv.number,
        inv.date,
        inv.customerName ?? 'Walk-in',
        inv.taxable / 100.0,
        inv.cgst / 100.0,
        inv.sgst / 100.0,
        inv.igst / 100.0,
        inv.total / 100.0,
        inv.amountPaid / 100.0,
        inv.paymentMode ?? 'Credit',
        inv.status,
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final filename = 'Sales_Summary_${period.replaceAll(' ', '_')}_${todayIso()}.xlsx';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Sales Summary Report - $bizName',
    );
  }

  Future<void> _exportPdf() async {
    if (data == null) return;
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
                    pw.Text('Sales Summary Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(bizName, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text('Period: $period ($fromDateStr to ${toDateStr ?? todayIso()})', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Total Sales: Rs ${formatPaise(data!.totalGrossSales)}',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    pw.Text('${data!.invoiceCount} Invoices Generated', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Invoice No', 'Date', 'Customer', 'Taxable (Rs)', 'Tax (Rs)', 'Total (Rs)', 'Paid (Rs)', 'Status'],
            data: data!.invoices
                .map((inv) => [
                      inv.number,
                      inv.date,
                      inv.customerName ?? 'Walk-in',
                      formatPaise(inv.taxable),
                      formatPaise(inv.cgst + inv.sgst + inv.igst),
                      formatPaise(inv.total),
                      formatPaise(inv.amountPaid),
                      inv.status,
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF3F51B5)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Sales_Summary.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Sales Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, size: 20),
            tooltip: 'Export Excel',
            onPressed: data == null || data!.invoices.isEmpty ? null : _exportExcel,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined, size: 20),
            tooltip: 'Print / Export PDF',
            onPressed: data == null || data!.invoices.isEmpty ? null : _exportPdf,
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
            else if (data != null) ...[
              // Summary KPI Grid
              _buildSummaryHeader(data!),
              const SizedBox(height: 14),

              // Payment Modes Breakdown Card
              _buildPaymentModesCard(data!),
              const SizedBox(height: 14),

              // Tax Summary Card
              _buildTaxCard(data!),
              const SizedBox(height: 16),

              // Search Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search invoice or customer...',
                    hintStyle: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                    border: InputBorder.none,
                    icon: Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                  ),
                  onChanged: (val) => setState(() => searchQuery = val.trim()),
                ),
              ),
              const SizedBox(height: 14),

              // Invoices list header
              Row(
                children: [
                  Text(
                    'Invoices (${data!.invoices.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    'Avg: Rs ${formatPaise(data!.invoiceCount > 0 ? (data!.totalGrossSales / data!.invoiceCount).round() : 0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              for (final inv in data!.invoices.where((i) {
                if (searchQuery.isEmpty) return true;
                final q = searchQuery.toLowerCase();
                return i.number.toLowerCase().contains(q) || (i.customerName?.toLowerCase().contains(q) ?? false);
              })) ...[
                _buildInvoiceTile(inv),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(SalesSummaryReportData d) {
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
                    const Text('Total Gross Sales', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      formatPaise(d.totalGrossSales),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${d.invoiceCount} Bills',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4F46E5)),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _subMetric('Taxable', formatPaise(d.totalTaxable), const Color(0xFF0F172A)),
              ),
              Container(width: 1, height: 28, color: StitchColors.outline),
              Expanded(
                child: _subMetric('Collected', formatPaise(d.totalPaid), const Color(0xFF16A34A)),
              ),
              Container(width: 1, height: 28, color: StitchColors.outline),
              Expanded(
                child: _subMetric('Due (Credit)', formatPaise(d.totalDue), const Color(0xFFDC2626)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _buildPaymentModesCard(SalesSummaryReportData d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Mode Split', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
          const SizedBox(height: 10),
          if (d.paymentModes.isEmpty)
            const Text('No recorded collections yet', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: d.paymentModes.entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${e.key}: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                      Text(formatPaise(e.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTaxCard(SalesSummaryReportData d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total GST Tax Collected', style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(formatPaise(d.totalTax), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            ],
          ),
          Row(
            children: [
              _taxBadge('CGST', formatPaise(d.totalCgst)),
              const SizedBox(width: 6),
              _taxBadge('SGST', formatPaise(d.totalSgst)),
              if (d.totalIgst > 0) ...[
                const SizedBox(width: 6),
                _taxBadge('IGST', formatPaise(d.totalIgst)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _taxBadge(String title, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
          Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildInvoiceTile(Invoice inv) {
    final isPaid = inv.amountPaid >= inv.total;
    return InkWell(
      onTap: () {
        if (inv.id != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id!)));
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_outlined, size: 18, color: StitchColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(inv.number, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isPaid ? 'Paid' : 'Unpaid',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isPaid ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${inv.customerName ?? 'Walk-in'} • ${displayDate(inv.date)}',
                    style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPaise(inv.total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                if (!isPaid && inv.total - inv.amountPaid > 0)
                  Text('Due: Rs ${formatPaise(inv.total - inv.amountPaid)}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: StitchColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
