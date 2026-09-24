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

class StockSummaryReportScreen extends StatefulWidget {
  const StockSummaryReportScreen({super.key});

  @override
  State<StockSummaryReportScreen> createState() => _StockSummaryReportScreenState();
}

class _StockSummaryReportScreenState extends State<StockSummaryReportScreen> {
  bool loading = true;
  String? error;
  List<Product> allProducts = [];
  String searchQuery = '';
  String selectedCategory = 'All';
  String statusFilter = 'All'; // 'All', 'In Stock', 'Low Stock', 'Out of Stock'

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
      final prods = await Repository.instance.products(bizId);
      if (!mounted) return;
      setState(() {
        allProducts = prods;
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

  List<String> get categories {
    final set = <String>{'All'};
    for (final p in allProducts) {
      if (p.category != null && p.category!.trim().isNotEmpty) {
        set.add(p.category!.trim());
      }
    }
    return set.toList();
  }

  List<Product> get filteredProducts {
    return allProducts.where((p) {
      if (selectedCategory != 'All' && p.category != selectedCategory) return false;
      if (statusFilter == 'In Stock' && p.stock <= 0) return false;
      if (statusFilter == 'Low Stock' && (p.stock <= 0 || p.stock > p.lowStockThreshold)) return false;
      if (statusFilter == 'Out of Stock' && p.stock > 0) return false;

      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchName = p.name.toLowerCase().contains(q);
        final matchSku = p.sku?.toLowerCase().contains(q) ?? false;
        if (!matchName && !matchSku) return false;
      }
      return true;
    }).toList();
  }

  int get totalStockUnits => allProducts.fold(0, (s, p) => s + (p.stock > 0 ? p.stock : 0));
  int get totalCostValue => allProducts.fold(0, (s, p) => s + (p.stock > 0 ? (p.stock * p.purchasePrice) : 0));
  int get totalSaleValue => allProducts.fold(0, (s, p) => s + (p.stock > 0 ? (p.stock * p.salePrice) : 0));
  int get potentialProfit => totalSaleValue - totalCostValue;
  double get potentialMargin => totalSaleValue > 0 ? (potentialProfit / totalSaleValue) * 100 : 0.0;
  int get lowStockCount => allProducts.where((p) => p.stock > 0 && p.stock <= p.lowStockThreshold).length;
  int get outOfStockCount => allProducts.where((p) => p.stock <= 0).length;

  Future<void> _exportExcel() async {
    final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
    final bizName = biz?.name ?? 'Business';
    final excel = xl.Excel.createExcel();
    final sheet = excel['Stock Summary'];

    sheet.appendRow([
      'Item Name',
      'Category',
      'SKU',
      'HSN',
      'Stock Qty',
      'Unit',
      'Purchase Price (Rs)',
      'Sale Price (Rs)',
      'Stock Value @ Cost (Rs)',
      'Stock Value @ Sale (Rs)',
      'Status',
    ]);

    for (final p in filteredProducts) {
      final status = p.stock <= 0 ? 'Out of Stock' : (p.stock <= p.lowStockThreshold ? 'Low Stock' : 'In Stock');
      sheet.appendRow([
        p.name,
        p.category ?? '-',
        p.sku ?? '-',
        p.hsn ?? '-',
        p.stock,
        p.unit,
        p.purchasePrice / 100.0,
        p.salePrice / 100.0,
        (p.stock * p.purchasePrice) / 100.0,
        (p.stock * p.salePrice) / 100.0,
        status,
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final filename = 'Stock_Summary_${todayIso()}.xlsx';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Stock Summary Report - $bizName',
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
                    pw.Text('Stock Summary & Inventory Valuation Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(bizName, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text('Date: ${todayIso()} • ${filteredProducts.length} Items Listed', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Cost Value: Rs ${formatPaise(totalCostValue)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    pw.Text('Retail Value: Rs ${formatPaise(totalSaleValue)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Item Name', 'Category', 'Stock', 'Purchase (Rs)', 'Sale (Rs)', 'Cost Val (Rs)', 'Status'],
            data: filteredProducts
                .map((p) => [
                      p.name,
                      p.category ?? '-',
                      '${p.stock} ${p.unit}',
                      formatPaise(p.purchasePrice),
                      formatPaise(p.salePrice),
                      formatPaise(p.stock * p.purchasePrice),
                      p.stock <= 0 ? 'Out of Stock' : (p.stock <= p.lowStockThreshold ? 'Low Stock' : 'In Stock'),
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
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Stock_Summary.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Stock Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, size: 20),
            tooltip: 'Export Excel',
            onPressed: allProducts.isEmpty ? null : _exportExcel,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined, size: 20),
            tooltip: 'Print / Export PDF',
            onPressed: allProducts.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // KPI Summary Header
            _buildValuationBanner(),
            const SizedBox(height: 14),

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
                  hintText: 'Search product or SKU...',
                  hintStyle: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                  border: InputBorder.none,
                  icon: Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                ),
                onChanged: (val) => setState(() => searchQuery = val.trim()),
              ),
            ),
            const SizedBox(height: 10),

            // Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusChip('All', 'All (${allProducts.length})', null),
                  const SizedBox(width: 8),
                  _statusChip('In Stock', 'In Stock (${allProducts.where((p) => p.stock > 0).length})', const Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  _statusChip('Low Stock', 'Low Stock ($lowStockCount)', const Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  _statusChip('Out of Stock', 'Out of Stock ($outOfStockCount)', const Color(0xFFDC2626)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category Chips if any
            if (categories.length > 2) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final sel = selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(cat),
                        selected: sel,
                        onSelected: (val) {
                          if (val) setState(() => selectedCategory = cat);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
                child: Text('Error loading inventory: $error', style: const TextStyle(color: Color(0xFF991B1B))),
              )
            else if (filteredProducts.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      searchQuery.isNotEmpty ? 'No products match "$searchQuery"' : 'No items found in this filter',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                    ),
                  ],
                ),
              )
            else
              for (final prod in filteredProducts) ...[
                _buildProductTile(prod),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildValuationBanner() {
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
                    const Text('Total Inventory Value (Cost)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      formatPaise(totalCostValue),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 16, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      '${potentialMargin.toStringAsFixed(1)}% Est. Margin',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
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
                child: _valMetric('Retail Value', formatPaise(totalSaleValue), const Color(0xFF0F172A)),
              ),
              Container(width: 1, height: 28, color: StitchColors.outline),
              Expanded(
                child: _valMetric('Total Units', '$totalStockUnits pcs', const Color(0xFF4F46E5)),
              ),
              Container(width: 1, height: 28, color: StitchColors.outline),
              Expanded(
                child: _valMetric('Low / Out', '$lowStockCount / $outOfStockCount', const Color(0xFFDC2626)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _statusChip(String key, String label, Color? activeColor) {
    final sel = statusFilter == key;
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
        if (val) setState(() => statusFilter = key);
      },
    );
  }

  Widget _buildProductTile(Product p) {
    final isOut = p.stock <= 0;
    final isLow = !isOut && p.stock <= p.lowStockThreshold;

    final badgeColor = isOut ? const Color(0xFFDC2626) : (isLow ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    final badgeBg = isOut ? const Color(0xFFFEE2E2) : (isLow ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7));
    final badgeText = isOut ? 'Out of Stock' : (isLow ? 'Low Stock' : 'In Stock');

    final costVal = p.stock * p.purchasePrice;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2_outlined, size: 20, color: StitchColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            badgeText,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.category ?? "General"} • SKU: ${p.sku ?? "N/A"}',
                      style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Available Stock', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary)),
                    const SizedBox(height: 1),
                    Text(
                      '${p.stock} ${p.unit}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: isOut ? const Color(0xFFDC2626) : StitchColors.textPrimary),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Buy / Sell Rate', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary)),
                    const SizedBox(height: 1),
                    Text(
                      'Rs ${formatPaise(p.purchasePrice)} / ${formatPaise(p.salePrice)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Stock Value (Cost)', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary)),
                    const SizedBox(height: 1),
                    Text(
                      formatPaise(costVal),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
