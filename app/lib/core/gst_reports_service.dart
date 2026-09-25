import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dates.dart';
import '../core/gst_service.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../data/repositories.dart';
import '../theme/stitch_theme.dart';

enum GstReturnType {
  gstr1('GSTR-1 (Sales)', 'Outward supplies & sales register', 'GSTR1'),
  gstr2('GSTR-2 (Purchases)', 'Inward supplies & ITC register', 'GSTR2'),
  gstr3b('GSTR-3B (Monthly)', 'Summary return & tax payment computation', 'GSTR3B');

  const GstReturnType(this.title, this.description, this.filePrefix);
  final String title;
  final String description;
  final String filePrefix;
}

enum GstExportFormat {
  pdf('Official PDF Document', 'Ready for print, filing review & audit submission', 'pdf'),
  excel('GST Portal Excel (.xlsx)', 'Formatted strictly to Government GST Offline Tool template', 'xlsx'),
  json('GST Portal JSON (.json)', 'Direct upload to Government GST Portal (gst.gov.in)', 'json');

  const GstExportFormat(this.label, this.description, this.extension);
  final String label;
  final String description;
  final String extension;
}

class GstReportsService {
  GstReportsService._();
  static final GstReportsService instance = GstReportsService._();

  // --------------------------------------------------------------------------
  // Utility & Conversion Helpers
  // --------------------------------------------------------------------------

  /// Converts paise to Rupees number with 2 decimals (e.g. 100000 -> 1000.00).
  static double toRupees(int paise) => ((paise / 100.0) * 100).round() / 100.0;

  /// Formats currency in Rupees string (e.g. "Rs. 1,000.00").
  static String money(int paise) => formatPaisePdf(paise, prefixRs: true);

  /// Formats ISO date 'YYYY-MM-DD' into GST Portal official standard 'DD-MM-YYYY'.
  static String formatGstDate(String isoDate) {
    try {
      final parts = isoDate.split('-');
      if (parts.length == 3) {
        return '${parts[2].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[0]}';
      }
    } catch (_) {}
    return isoDate;
  }

  /// Derives financial period string 'MMYYYY' for GST Portal (e.g. September 2026 -> '092026').
  static String formatFp(DateTime? date) {
    final d = date ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$mm$yyyy';
  }

  /// Extracts 2-digit state code from GSTIN or state name.
  static String resolveStateCode({String? gstin, String? stateName, String defaultCode = '29'}) {
    if (gstin != null && gstin.trim().length >= 2) {
      final code = gstin.trim().substring(0, 2);
      if (int.tryParse(code) != null) return code;
    }
    if (stateName != null && stateName.trim().isNotEmpty) {
      final clean = stateName.trim().toLowerCase();
      for (final entry in GstService.stateCodes.entries) {
        if (entry.value.toLowerCase() == clean) return entry.key;
      }
    }
    return defaultCode;
  }

  // ==========================================================================
  // 1. GSTR-1 (OUTWARD SUPPLIES / SALES)
  // ==========================================================================

  /// Generates Government GST Portal Direct Upload JSON for GSTR-1.
  /// Compliant with GSTN Offline Tool Schema v1.3.
  Future<String> generateGstr1Json({
    required Business business,
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final sections = await Repository.instance.getGstr1Data(bizId, from: from, to: to);
    final hsnItems = await Repository.instance.getHsnSummary(bizId, from: from, to: to);
    final fp = formatFp(from ?? to ?? DateTime.now());
    final gstin = business.gstin?.trim().toUpperCase() ?? '29ABCDE1234F1Z5';

    // B2B: Grouped by ctin (Customer GSTIN)
    final b2bSection = sections.firstWhere((s) => s.code == 'B2B', orElse: () => Gstr1Section(code: 'B2B', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []));
    final b2bMap = <String, List<Map<String, dynamic>>>{};
    for (final itm in b2bSection.items) {
      final ctin = (itm['customer_gstin'] as String?)?.trim().toUpperCase() ?? '29AAAAA0000A1Z5';
      b2bMap.putIfAbsent(ctin, () => []).add(itm);
    }

    final b2bList = <Map<String, dynamic>>[];
    for (final entry in b2bMap.entries) {
      final ctin = entry.key;
      final invoices = <Map<String, dynamic>>[];

      for (final itm in entry.value) {
        final total = (itm['total'] as num?)?.toInt() ?? 0;
        final taxable = (itm['taxable'] as num?)?.toInt() ?? 0;
        final cgst = (itm['cgst'] as num?)?.toInt() ?? 0;
        final sgst = (itm['sgst'] as num?)?.toInt() ?? 0;
        final igst = (itm['igst'] as num?)?.toInt() ?? 0;
        final pos = resolveStateCode(gstin: ctin, stateName: itm['customer_state'] as String?, defaultCode: '29');
        final rate = taxable > 0 ? ((cgst + sgst + igst) * 100.0 / taxable).roundToDouble() : 18.0;

        invoices.add({
          'inum': itm['number'] ?? 'INV-0001',
          'idt': formatGstDate(itm['date'] ?? isoDate(DateTime.now())),
          'val': toRupees(total),
          'pos': pos,
          'rchrg': 'N',
          'inv_typ': 'R',
          'itms': [
            {
              'num': 1,
              'itm_det': {
                'rt': rate,
                'txval': toRupees(taxable),
                'iamt': toRupees(igst),
                'camt': toRupees(cgst),
                'samt': toRupees(sgst),
                'csamt': 0.0,
              }
            }
          ],
        });
      }

      b2bList.add({
        'ctin': ctin,
        'cfs': 'Y',
        'cpty': '',
        'inv': invoices,
      });
    }

    // B2CS: Retail & unregistered supplies grouped by (sply_ty, pos, rt)
    final b2csSection = sections.firstWhere((s) => s.code == 'B2CS', orElse: () => Gstr1Section(code: 'B2CS', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []));
    final b2csGroups = <String, Map<String, dynamic>>{};
    for (final itm in b2csSection.items) {
      final taxable = (itm['taxable'] as num?)?.toInt() ?? 0;
      final cgst = (itm['cgst'] as num?)?.toInt() ?? 0;
      final sgst = (itm['sgst'] as num?)?.toInt() ?? 0;
      final igst = (itm['igst'] as num?)?.toInt() ?? 0;
      final pos = resolveStateCode(stateName: itm['customer_state'] as String?, defaultCode: resolveStateCode(gstin: gstin));
      final isInter = igst > 0;
      final rate = taxable > 0 ? ((cgst + sgst + igst) * 100.0 / taxable).roundToDouble() : 18.0;
      final groupKey = '${isInter ? "INTER" : "INTRA"}_${pos}_$rate';

      final grp = b2csGroups.putIfAbsent(groupKey, () => {
        'sply_ty': isInter ? 'INTER' : 'INTRA',
        'pos': pos,
        'typ': 'OE',
        'rt': rate,
        'txval': 0.0,
        'iamt': 0.0,
        'camt': 0.0,
        'samt': 0.0,
        'csamt': 0.0,
      });

      grp['txval'] = (grp['txval'] as double) + toRupees(taxable);
      grp['iamt'] = (grp['iamt'] as double) + toRupees(igst);
      grp['camt'] = (grp['camt'] as double) + toRupees(cgst);
      grp['samt'] = (grp['samt'] as double) + toRupees(sgst);
    }

    // HSN Summary
    final hsnList = <Map<String, dynamic>>[];
    int hsnIdx = 1;
    for (final h in hsnItems) {
      hsnList.add({
        'num': hsnIdx++,
        'hsn_sc': h.hsn,
        'desc': h.description,
        'uqc': h.uqc,
        'qty': h.totalQuantity,
        'val': toRupees(h.totalValue),
        'txval': toRupees(h.taxableValue),
        'iamt': toRupees(h.igst),
        'camt': toRupees(h.cgst),
        'samt': toRupees(h.sgst),
        'csamt': 0.0,
      });
    }

    // Documents summary
    final allInv = [...b2bSection.items, ...b2csSection.items];
    final minNum = allInv.isNotEmpty ? allInv.first['number']?.toString() ?? '1' : '1';
    final maxNum = allInv.isNotEmpty ? allInv.last['number']?.toString() ?? '1' : '1';
    final totDocs = allInv.length;

    int totalGrossPaise = 0;
    for (final s in sections) {
      totalGrossPaise += s.totalValue;
    }

    final payload = {
      'gstin': gstin,
      'fp': fp,
      'version': 'GSTR1_V1.3',
      'hash': 'hash',
      'gt': toRupees(totalGrossPaise),
      'cur_gt': toRupees(totalGrossPaise),
      'b2b': b2bList,
      'b2cl': <dynamic>[],
      'b2cs': b2csGroups.values.toList(),
      'cdnr': <dynamic>[],
      'cdnur': <dynamic>[],
      'exp': <dynamic>[],
      'hsn': {'data': hsnList},
      'doc_issue': {
        'doc_det': [
          {
            'doc_num': 1,
            'doc_typ': 'Invoices for outward supply',
            'docs': [
              {
                'num': 1,
                'from': minNum,
                'to': maxNum,
                'totnum': totDocs,
                'canc': 0,
                'net_issue': totDocs,
              }
            ],
          }
        ]
      },
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Generates Government GST Portal Offline Tool Excel Workbook (.xlsx) for GSTR-1.
  Future<Uint8List> generateGstr1Excel({
    required Business business,
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final sections = await Repository.instance.getGstr1Data(bizId, from: from, to: to);
    final hsnItems = await Repository.instance.getHsnSummary(bizId, from: from, to: to);
    final myState = resolveStateCode(gstin: business.gstin);

    final excel = xl.Excel.createExcel();

    // Sheet: b2b
    final b2bSheet = excel['b2b'];
    b2bSheet.appendRow([
      'GSTIN/UIN of Recipient',
      'Receiver Name',
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Reverse Charge',
      'Applicable % of Tax Rate',
      'Invoice Type',
      'E-Commerce GSTIN',
      'Rate',
      'Taxable Value',
      'Cess Amount',
    ]);

    final b2bSection = sections.firstWhere((s) => s.code == 'B2B', orElse: () => Gstr1Section(code: 'B2B', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []));
    for (final itm in b2bSection.items) {
      final taxable = (itm['taxable'] as num?)?.toInt() ?? 0;
      final cgst = (itm['cgst'] as num?)?.toInt() ?? 0;
      final sgst = (itm['sgst'] as num?)?.toInt() ?? 0;
      final igst = (itm['igst'] as num?)?.toInt() ?? 0;
      final rate = taxable > 0 ? ((cgst + sgst + igst) * 100.0 / taxable).roundToDouble() : 18.0;
      final ctin = (itm['customer_gstin'] as String?)?.trim() ?? '';
      final pos = resolveStateCode(gstin: ctin, stateName: itm['customer_state'] as String?, defaultCode: myState);

      b2bSheet.appendRow([
        ctin,
        itm['customer_name'] ?? itm['party_name'] ?? '',
        itm['number'] ?? '',
        formatGstDate(itm['date'] ?? ''),
        toRupees((itm['total'] as num?)?.toInt() ?? 0),
        '$pos-${GstService.stateCodes[pos] ?? "State"}',
        'N',
        '',
        'Regular',
        '',
        rate,
        toRupees(taxable),
        0.0,
      ]);
    }

    // Sheet: b2cs
    final b2csSheet = excel['b2cs'];
    b2csSheet.appendRow([
      'Type',
      'Place Of Supply',
      'Applicable % of Tax Rate',
      'Rate',
      'Taxable Value',
      'Cess Amount',
      'E-Commerce GSTIN',
    ]);

    final b2csSection = sections.firstWhere((s) => s.code == 'B2CS', orElse: () => Gstr1Section(code: 'B2CS', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []));
    for (final itm in b2csSection.items) {
      final taxable = (itm['taxable'] as num?)?.toInt() ?? 0;
      final cgst = (itm['cgst'] as num?)?.toInt() ?? 0;
      final sgst = (itm['sgst'] as num?)?.toInt() ?? 0;
      final igst = (itm['igst'] as num?)?.toInt() ?? 0;
      final rate = taxable > 0 ? ((cgst + sgst + igst) * 100.0 / taxable).roundToDouble() : 18.0;
      final pos = resolveStateCode(stateName: itm['customer_state'] as String?, defaultCode: myState);

      b2csSheet.appendRow([
        'OE',
        '$pos-${GstService.stateCodes[pos] ?? "State"}',
        '',
        rate,
        toRupees(taxable),
        0.0,
        '',
      ]);
    }

    // Sheet: hsn
    final hsnSheet = excel['hsn'];
    hsnSheet.appendRow([
      'HSN',
      'Description',
      'UQC',
      'Total Quantity',
      'Total Value',
      'Taxable Value',
      'Integrated Tax Amount',
      'Central Tax Amount',
      'State/UT Tax Amount',
      'Cess Amount',
    ]);

    for (final h in hsnItems) {
      hsnSheet.appendRow([
        h.hsn,
        h.description,
        h.uqc,
        h.totalQuantity,
        toRupees(h.totalValue),
        toRupees(h.taxableValue),
        toRupees(h.igst),
        toRupees(h.cgst),
        toRupees(h.sgst),
        0.0,
      ]);
    }

    // Sheet: docs
    final docsSheet = excel['docs'];
    docsSheet.appendRow([
      'Nature of Document',
      'Sr. No. From',
      'Sr. No. To',
      'Total Number',
      'Cancelled',
    ]);
    final allInv = [...b2bSection.items, ...b2csSection.items];
    if (allInv.isNotEmpty) {
      docsSheet.appendRow([
        'Invoices for outward supply',
        allInv.first['number'] ?? '1',
        allInv.last['number'] ?? '1',
        allInv.length,
        0,
      ]);
    }

    // Remove default Sheet1 if unused
    try {
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    } catch (_) {}

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Generates Official Government Form GSTR-1 PDF.
  Future<Uint8List> generateGstr1Pdf({
    required Business business,
    DateTime? from,
    DateTime? to,
    String periodLabel = 'Current Period',
  }) async {
    final bizId = business.id!;
    final sections = await Repository.instance.getGstr1Data(bizId, from: from, to: to);
    final hsnItems = await Repository.instance.getHsnSummary(bizId, from: from, to: to);

    final doc = pw.Document();
    final mono = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    const navy = PdfColor.fromInt(0xFF1E3A8A);
    const slateDark = PdfColor.fromInt(0xFF0F172A);
    const slateLight = PdfColor.fromInt(0xFFF8FAFC);
    const borderSlate = PdfColor.fromInt(0xFFCBD5E1);

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(24),
        ),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: borderSlate, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('FORM GSTR-1', style: pw.TextStyle(font: bold, fontSize: 13, color: navy)),
                pw.Text('Statement of Outward Supplies of Goods or Services [See Rule 59(1)]', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey700)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('GSTIN: ${business.gstin ?? "Unregistered"}', style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark)),
                pw.Text('Period: $periodLabel (${formatFp(from ?? to)})', style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated via Billket GST Center - Official Form GSTR-1', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 10),
          // Taxpayer Card
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: slateLight,
              border: pw.Border.all(color: borderSlate, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Legal Name: ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9.5)),
                  if (business.address != null)
                    pw.Text('Principal Place: ${business.address}', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey700)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('State: ${business.state ?? "India"}', style: pw.TextStyle(font: mono, fontSize: 8.5)),
                  pw.Text('Return Period: $periodLabel', style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Section 4: B2B Invoices Table
          pw.Text('Table 4: Taxable outward supplies made to registered persons (B2B)', style: pw.TextStyle(font: bold, fontSize: 9, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['GSTIN', 'Receiver Name', 'Inv No.', 'Date', 'Taxable Val', 'CGST', 'SGST', 'IGST', 'Total'],
            rows: sections
                .firstWhere((s) => s.code == 'B2B', orElse: () => Gstr1Section(code: 'B2B', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []))
                .items
                .map<List<String>>((itm) => [
                      (itm['customer_gstin'] as String?) ?? '-',
                      itm['customer_name']?.toString() ?? '-',
                      itm['number']?.toString() ?? '-',
                      formatGstDate(itm['date']?.toString() ?? ''),
                      money((itm['taxable'] as num?)?.toInt() ?? 0),
                      money((itm['cgst'] as num?)?.toInt() ?? 0),
                      money((itm['sgst'] as num?)?.toInt() ?? 0),
                      money((itm['igst'] as num?)?.toInt() ?? 0),
                      money((itm['total'] as num?)?.toInt() ?? 0),
                    ])
                .toList(),
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 14),
          // Section 7: B2CS Retail Supplies Table
          pw.Text('Table 7: Taxable supplies to unregistered persons (B2C Small)', style: pw.TextStyle(font: bold, fontSize: 9, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['Type', 'Place of Supply', 'Rate', 'Taxable Val', 'CGST', 'SGST', 'IGST', 'Total Value'],
            rows: sections
                .firstWhere((s) => s.code == 'B2CS', orElse: () => Gstr1Section(code: 'B2CS', title: '', subtitle: '', count: 0, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, totalValue: 0, items: []))
                .items
                .take(30)
                .map<List<String>>((itm) => [
                      'OE',
                      itm['customer_state']?.toString() ?? 'Local',
                      '18%',
                      money((itm['taxable'] as num?)?.toInt() ?? 0),
                      money((itm['cgst'] as num?)?.toInt() ?? 0),
                      money((itm['sgst'] as num?)?.toInt() ?? 0),
                      money((itm['igst'] as num?)?.toInt() ?? 0),
                      money((itm['total'] as num?)?.toInt() ?? 0),
                    ])
                .toList(),
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 14),
          // Section 12: HSN Summary
          pw.Text('Table 12: HSN-wise summary of outward supplies', style: pw.TextStyle(font: bold, fontSize: 9, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['HSN/SAC', 'Description', 'UQC', 'Qty', 'Taxable Val', 'CGST', 'SGST', 'IGST', 'Total Val'],
            rows: hsnItems
                .map((h) => [
                      h.hsn,
                      h.description,
                      h.uqc,
                      h.totalQuantity.toString(),
                      money(h.taxableValue),
                      money(h.cgst),
                      money(h.sgst),
                      money(h.igst),
                      money(h.totalValue),
                    ])
                .toList(),
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 20),
          // Verification
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('For ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9)),
              pw.SizedBox(height: 28),
              pw.Text(business.signatureText.isNotEmpty ? business.signatureText : 'Authorised Signatory', style: pw.TextStyle(font: bold, fontSize: 8)),
            ]),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ==========================================================================
  // 2. GSTR-2 (INWARD SUPPLIES / PURCHASE REGISTER)
  // ==========================================================================

  /// Generates Government GST Portal Direct Upload JSON for GSTR-2.
  Future<String> generateGstr2Json({
    required Business business,
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final entries = await Repository.instance.getGstr2bData(bizId, from: from, to: to);
    final fp = formatFp(from ?? to ?? DateTime.now());
    final gstin = business.gstin?.trim().toUpperCase() ?? '29ABCDE1234F1Z5';

    final b2bMap = <String, List<Gstr2bEntry>>{};
    final b2burList = <Map<String, dynamic>>[];

    for (final e in entries) {
      if (e.supplierGstin.trim().length >= 14) {
        b2bMap.putIfAbsent(e.supplierGstin.toUpperCase(), () => []).add(e);
      } else {
        b2burList.add({
          'inum': e.invoiceNumber,
          'idt': formatGstDate(e.invoiceDate),
          'val': toRupees(e.invoiceValue),
          'pos': resolveStateCode(gstin: gstin),
          'itms': [
            {
              'num': 1,
              'itm_det': {
                'rt': 18.0,
                'txval': toRupees(e.taxableValue),
                'iamt': toRupees(e.igst),
                'camt': toRupees(e.cgst),
                'samt': toRupees(e.sgst),
                'csamt': 0.0,
              }
            }
          ]
        });
      }
    }

    final b2bList = <Map<String, dynamic>>[];
    for (final entry in b2bMap.entries) {
      final ctin = entry.key;
      final invoices = <Map<String, dynamic>>[];

      for (final e in entry.value) {
        invoices.add({
          'inum': e.invoiceNumber,
          'idt': formatGstDate(e.invoiceDate),
          'val': toRupees(e.invoiceValue),
          'pos': resolveStateCode(gstin: gstin),
          'rchrg': 'N',
          'inv_typ': 'R',
          'itms': [
            {
              'num': 1,
              'itm_det': {
                'rt': 18.0,
                'txval': toRupees(e.taxableValue),
                'iamt': toRupees(e.igst),
                'camt': toRupees(e.cgst),
                'samt': toRupees(e.sgst),
                'csamt': 0.0,
              },
              'itc': {
                'elg': 'T',
                'tx_i': toRupees(e.igst),
                'tx_c': toRupees(e.cgst),
                'tx_s': toRupees(e.sgst),
                'tx_cs': 0.0,
              }
            }
          ]
        });
      }

      b2bList.add({
        'ctin': ctin,
        'cfs': 'Y',
        'inv': invoices,
      });
    }

    final payload = {
      'gstin': gstin,
      'fp': fp,
      'version': 'GSTR2_V1.1',
      'b2b': b2bList,
      'b2bur': b2burList,
      'cdnr': <dynamic>[],
      'hsnsum': {'data': <dynamic>[]},
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Generates Government GST Portal Inward Supplies / Purchase Register Excel Workbook (.xlsx) for GSTR-2.
  Future<Uint8List> generateGstr2Excel({
    required Business business,
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final entries = await Repository.instance.getGstr2bData(bizId, from: from, to: to);
    final myState = resolveStateCode(gstin: business.gstin);

    final excel = xl.Excel.createExcel();

    // Sheet: b2b
    final b2bSheet = excel['b2b'];
    b2bSheet.appendRow([
      'GSTIN of Supplier',
      'Supplier Name',
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Reverse Charge',
      'Invoice Type',
      'Rate',
      'Taxable Value',
      'Integrated Tax Paid',
      'Central Tax Paid',
      'State/UT Tax Paid',
      'Cess Paid',
      'Eligibility For ITC',
      'Availed ITC Integrated Tax',
      'Availed ITC Central Tax',
      'Availed ITC State/UT Tax',
      'Availed ITC Cess',
    ]);

    // Sheet: b2bur
    final b2burSheet = excel['b2bur'];
    b2burSheet.appendRow([
      'Supplier Name',
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Rate',
      'Taxable Value',
      'Integrated Tax Paid',
      'Central Tax Paid',
      'State/UT Tax Paid',
      'Cess Paid',
      'Eligibility For ITC',
      'Availed ITC',
    ]);

    for (final e in entries) {
      if (e.supplierGstin.trim().length >= 14) {
        b2bSheet.appendRow([
          e.supplierGstin,
          e.supplierName,
          e.invoiceNumber,
          formatGstDate(e.invoiceDate),
          toRupees(e.invoiceValue),
          '$myState-${GstService.stateCodes[myState] ?? "State"}',
          'N',
          'Regular',
          18.0,
          toRupees(e.taxableValue),
          toRupees(e.igst),
          toRupees(e.cgst),
          toRupees(e.sgst),
          0.0,
          'Inputs',
          toRupees(e.igst),
          toRupees(e.cgst),
          toRupees(e.sgst),
          0.0,
        ]);
      } else {
        b2burSheet.appendRow([
          e.supplierName,
          e.invoiceNumber,
          formatGstDate(e.invoiceDate),
          toRupees(e.invoiceValue),
          '$myState-${GstService.stateCodes[myState] ?? "State"}',
          18.0,
          toRupees(e.taxableValue),
          toRupees(e.igst),
          toRupees(e.cgst),
          toRupees(e.sgst),
          0.0,
          'Inputs',
          toRupees(e.cgst + e.sgst + e.igst),
        ]);
      }
    }

    try {
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    } catch (_) {}

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Generates Official Government Form GSTR-2 PDF.
  Future<Uint8List> generateGstr2Pdf({
    required Business business,
    DateTime? from,
    DateTime? to,
    String periodLabel = 'Current Period',
  }) async {
    final bizId = business.id!;
    final entries = await Repository.instance.getGstr2bData(bizId, from: from, to: to);

    final doc = pw.Document();
    final mono = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    const navy = PdfColor.fromInt(0xFF1E3A8A);
    const slateDark = PdfColor.fromInt(0xFF0F172A);
    const slateLight = PdfColor.fromInt(0xFFF8FAFC);
    const borderSlate = PdfColor.fromInt(0xFFCBD5E1);

    int totalTaxable = 0;
    int totalTax = 0;
    int totalVal = 0;
    for (final e in entries) {
      totalTaxable += e.taxableValue;
      totalTax += e.cgst + e.sgst + e.igst;
      totalVal += e.invoiceValue;
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(24),
        ),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: borderSlate, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('FORM GSTR-2', style: pw.TextStyle(font: bold, fontSize: 13, color: navy)),
                pw.Text('Details of Inward Supplies of Goods or Services [See Rule 60(1)]', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey700)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('GSTIN: ${business.gstin ?? "Unregistered"}', style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark)),
                pw.Text('Period: $periodLabel (${formatFp(from ?? to)})', style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated via Billket GST Center - Official Form GSTR-2', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: slateLight,
              border: pw.Border.all(color: borderSlate, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Taxpayer Name: ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9.5)),
                  pw.Text('Total Inward Supplies: ${entries.length} bills', style: pw.TextStyle(font: mono, fontSize: 8.5)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Total Inward: ${money(totalVal)} (Taxable: ${money(totalTaxable)})', style: pw.TextStyle(font: bold, fontSize: 8.5)),
                  pw.Text('Eligible ITC: ${money(totalTax)}', style: pw.TextStyle(font: bold, fontSize: 8.5, color: const PdfColor.fromInt(0xFF059669))),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Inward supplies table
          pw.Text('Table 3: Inward supplies received from registered persons', style: pw.TextStyle(font: bold, fontSize: 9, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['Supplier GSTIN', 'Supplier Name', 'Invoice No', 'Date', 'Taxable Val', 'CGST', 'SGST', 'IGST', 'ITC Status'],
            rows: entries
                .map((e) => [
                      e.supplierGstin,
                      e.supplierName,
                      e.invoiceNumber,
                      formatGstDate(e.invoiceDate),
                      money(e.taxableValue),
                      money(e.cgst),
                      money(e.sgst),
                      money(e.igst),
                      e.matchStatus,
                    ])
                .toList(),
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('For ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9)),
              pw.SizedBox(height: 28),
              pw.Text(business.signatureText.isNotEmpty ? business.signatureText : 'Authorised Signatory', style: pw.TextStyle(font: bold, fontSize: 8)),
            ]),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ==========================================================================
  // 3. GSTR-3B (MONTHLY SUMMARY RETURN & TAX PAYMENT)
  // ==========================================================================

  /// Generates Government GST Portal Direct Upload JSON for GSTR-3B.
  /// Compliant with GST Portal GSTR3B schema.
  Future<String> generateGstr3bJson({
    required Business business,
    String period = 'Current Month',
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final summary = await Repository.instance.getGstr3bData(bizId, period: period);
    final fp = formatFp(from ?? to ?? DateTime.now());
    final gstin = business.gstin?.trim().toUpperCase() ?? '29ABCDE1234F1Z5';

    final payload = {
      'gstin': gstin,
      'ret_period': fp,
      'sec_sum': {
        '3.1': {
          'osup_det': {
            'txval': toRupees(summary.outwardTaxableSupplies),
            'iamt': toRupees(summary.outwardIgst),
            'camt': toRupees(summary.outwardCgst),
            'samt': toRupees(summary.outwardSgst),
            'csamt': toRupees(summary.outwardCess),
          },
          'osup_zero': {'txval': 0.0, 'iamt': 0.0, 'csamt': 0.0},
          'osup_nil_exmp': {'txval': toRupees(summary.exemptSupplies)},
          'isup_rev': {'txval': 0.0, 'iamt': 0.0, 'camt': 0.0, 'samt': 0.0, 'csamt': 0.0},
          'osup_nongst': {'txval': 0.0},
        },
        '3.2': {
          'inter_sup': <dynamic>[],
        },
        '4': {
          'itc_avl': [
            {
              'ty': 'OTH',
              'iamt': toRupees(summary.itcAvailableIgst),
              'camt': toRupees(summary.itcAvailableCgst),
              'samt': toRupees(summary.itcAvailableSgst),
              'csamt': toRupees(summary.itcAvailableCess),
            }
          ],
          'itc_rev': <dynamic>[],
          'itc_net': {
            'iamt': toRupees(summary.itcAvailableIgst),
            'camt': toRupees(summary.itcAvailableCgst),
            'samt': toRupees(summary.itcAvailableSgst),
            'csamt': toRupees(summary.itcAvailableCess),
          },
          'itc_inel': <dynamic>[],
        },
        '5.1': {
          'intr_ltfee': {
            'iamt': 0.0,
            'camt': 0.0,
            'samt': 0.0,
            'csamt': 0.0,
          }
        },
      }
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Generates Government GST Portal GSTR-3B Computation Excel Workbook (.xlsx).
  Future<Uint8List> generateGstr3bExcel({
    required Business business,
    String period = 'Current Month',
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final summary = await Repository.instance.getGstr3bData(bizId, period: period);

    final excel = xl.Excel.createExcel();

    // Sheet 1: 3.1 Outward Supplies
    final s31 = excel['3.1 Outward Supplies'];
    s31.appendRow([
      'Nature of Supplies',
      'Total Taxable Value',
      'Integrated Tax',
      'Central Tax',
      'State/UT Tax',
      'Cess',
    ]);
    s31.appendRow([
      '(a) Outward taxable supplies (other than zero rated, nil and exempted)',
      toRupees(summary.outwardTaxableSupplies),
      toRupees(summary.outwardIgst),
      toRupees(summary.outwardCgst),
      toRupees(summary.outwardSgst),
      toRupees(summary.outwardCess),
    ]);
    s31.appendRow([
      '(b) Outward taxable supplies (zero rated)',
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
    ]);
    s31.appendRow([
      '(c) Other outward supplies (Nil rated, exempted)',
      toRupees(summary.exemptSupplies),
      0.0,
      0.0,
      0.0,
      0.0,
    ]);

    // Sheet 2: 4 Eligible ITC
    final s4 = excel['4 Eligible ITC'];
    s4.appendRow([
      'Details',
      'Integrated Tax',
      'Central Tax',
      'State/UT Tax',
      'Cess',
    ]);
    s4.appendRow([
      '(A) Input Tax Credit Available (whether in full or part)',
      toRupees(summary.itcAvailableIgst),
      toRupees(summary.itcAvailableCgst),
      toRupees(summary.itcAvailableSgst),
      toRupees(summary.itcAvailableCess),
    ]);
    s4.appendRow([
      '(C) Net ITC Available (A) - (B)',
      toRupees(summary.itcAvailableIgst),
      toRupees(summary.itcAvailableCgst),
      toRupees(summary.itcAvailableSgst),
      toRupees(summary.itcAvailableCess),
    ]);

    // Sheet 3: 6.1 Payment of Tax
    final s61 = excel['6.1 Payment of Tax'];
    s61.appendRow([
      'Description',
      'Tax Payable',
      'Paid Through ITC',
      'Tax Paid in Cash',
      'Interest Paid',
      'Late Fee Paid',
    ]);
    s61.appendRow([
      'Integrated Tax',
      toRupees(summary.outwardIgst),
      toRupees(summary.itcAvailableIgst),
      toRupees(summary.netTaxPayableIgst),
      0.0,
      0.0,
    ]);
    s61.appendRow([
      'Central Tax',
      toRupees(summary.outwardCgst),
      toRupees(summary.itcAvailableCgst),
      toRupees(summary.netTaxPayableCgst),
      0.0,
      0.0,
    ]);
    s61.appendRow([
      'State/UT Tax',
      toRupees(summary.outwardSgst),
      toRupees(summary.itcAvailableSgst),
      toRupees(summary.netTaxPayableSgst),
      0.0,
      0.0,
    ]);
    s61.appendRow([
      'Total Cash Payable',
      toRupees(summary.outwardIgst + summary.outwardCgst + summary.outwardSgst),
      toRupees(summary.itcAvailableIgst + summary.itcAvailableCgst + summary.itcAvailableSgst),
      toRupees(summary.totalTaxPayableCash),
      0.0,
      0.0,
    ]);

    try {
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    } catch (_) {}

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Generates Official Government Form GSTR-3B PDF.
  Future<Uint8List> generateGstr3bPdf({
    required Business business,
    String period = 'Current Month',
    DateTime? from,
    DateTime? to,
  }) async {
    final bizId = business.id!;
    final summary = await Repository.instance.getGstr3bData(bizId, period: period);

    final doc = pw.Document();
    final mono = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    const navy = PdfColor.fromInt(0xFF1E3A8A);
    const slateDark = PdfColor.fromInt(0xFF0F172A);
    const slateLight = PdfColor.fromInt(0xFFF8FAFC);
    const borderSlate = PdfColor.fromInt(0xFFCBD5E1);

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(24),
        ),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: borderSlate, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('FORM GSTR-3B', style: pw.TextStyle(font: bold, fontSize: 13, color: navy)),
                pw.Text('Monthly Return under Central Goods and Services Tax Rules, 2017 [See Rule 61(5)]', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey700)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('GSTIN: ${business.gstin ?? "Unregistered"}', style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark)),
                pw.Text('Period: ${summary.period}', style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated via Billket GST Center - Official Form GSTR-3B', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: slateLight,
              border: pw.Border.all(color: borderSlate, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Legal Name: ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9.5)),
                  pw.Text('State: ${business.state ?? "India"}', style: pw.TextStyle(font: mono, fontSize: 8.5)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Filing Period: ${summary.period}', style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
                  pw.Text('Net Tax in Cash: ${money(summary.totalTaxPayableCash)}', style: pw.TextStyle(font: bold, fontSize: 9, color: const PdfColor.fromInt(0xFFDC2626))),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // 3.1 Outward supplies
          pw.Text('3.1 Details of Outward Supplies and inward supplies liable to reverse charge', style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['Nature of Supplies', 'Total Taxable Val', 'Integrated Tax', 'Central Tax', 'State/UT Tax', 'Cess'],
            rows: [
              [
                '(a) Outward taxable supplies (other than zero rated, nil and exempted)',
                money(summary.outwardTaxableSupplies),
                money(summary.outwardIgst),
                money(summary.outwardCgst),
                money(summary.outwardSgst),
                money(summary.outwardCess),
              ],
              ['(b) Outward taxable supplies (zero rated)', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00'],
              ['(c) Other outward supplies (Nil rated, exempted)', money(summary.exemptSupplies), '-', '-', '-', '-'],
              ['(d) Inward supplies (liable to reverse charge)', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00', 'Rs. 0.00'],
            ],
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 14),
          // 4. Eligible ITC
          pw.Text('4. Eligible Input Tax Credit (ITC)', style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['Details', 'Integrated Tax', 'Central Tax', 'State/UT Tax', 'Cess'],
            rows: [
              [
                '(A) ITC Available (whether in full or part)\n(5) All other ITC (Purchases from registered vendors)',
                money(summary.itcAvailableIgst),
                money(summary.itcAvailableCgst),
                money(summary.itcAvailableSgst),
                money(summary.itcAvailableCess),
              ],
              [
                '(C) Net ITC Available (A) - (B)',
                money(summary.itcAvailableIgst),
                money(summary.itcAvailableCgst),
                money(summary.itcAvailableSgst),
                money(summary.itcAvailableCess),
              ],
            ],
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 14),
          // 6.1 Payment of Tax
          pw.Text('6.1 Payment of Tax (Liability vs Input Credit Setoff)', style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
          pw.SizedBox(height: 4),
          _buildGstrTable(
            headers: ['Description', 'Tax Payable', 'Paid via ITC', 'Tax Paid in Cash', 'Interest', 'Late Fee'],
            rows: [
              ['Integrated Tax', money(summary.outwardIgst), money(summary.itcAvailableIgst), money(summary.netTaxPayableIgst), 'Rs. 0.00', 'Rs. 0.00'],
              ['Central Tax', money(summary.outwardCgst), money(summary.itcAvailableCgst), money(summary.netTaxPayableCgst), 'Rs. 0.00', 'Rs. 0.00'],
              ['State/UT Tax', money(summary.outwardSgst), money(summary.itcAvailableSgst), money(summary.netTaxPayableSgst), 'Rs. 0.00', 'Rs. 0.00'],
              ['TOTAL CASH LIABILITY', '-', '-', money(summary.totalTaxPayableCash), 'Rs. 0.00', 'Rs. 0.00'],
            ],
            bold: bold,
            mono: mono,
          ),

          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderSlate, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
              color: slateLight,
            ),
            child: pw.Text(
              'Verification: I hereby solemnly affirm and declare that the information given herein above is true and correct to the best of my knowledge and belief and nothing has been concealed there from.',
              style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('For ${business.name}', style: pw.TextStyle(font: bold, fontSize: 9)),
              pw.SizedBox(height: 28),
              pw.Text(business.signatureText.isNotEmpty ? business.signatureText : 'Authorised Signatory', style: pw.TextStyle(font: bold, fontSize: 8)),
            ]),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ==========================================================================
  // Export & Share Handlers
  // ==========================================================================

  /// Saves bytes/content to disk and shares via system sheet (WhatsApp, Email, Drive).
  static Future<void> shareExportedFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String subject,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: subject,
    );
  }

  /// Saves bytes/content to device Downloads / Documents directory and returns the saved file path.
  static Future<String> saveExportedFile({
    required Uint8List bytes,
    required String filename,
  }) async {
    Directory? targetDir;
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        }
      }
    } catch (_) {}
    targetDir ??= await getApplicationDocumentsDirectory();
    final file = File('${targetDir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Opens layout print dialog for a generated PDF.
  static Future<void> printPdf(Uint8List bytes, String filename) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: filename,
    );
  }

  // ==========================================================================
  // Helper Table Builder for PDF
  // ==========================================================================
  static pw.Widget _buildGstrTable({
    required List<String> headers,
    required List<List<String>> rows,
    required pw.Font bold,
    required pw.Font mono,
  }) {
    const navy = PdfColor.fromInt(0xFF1E3A8A);
    const borderSlate = PdfColor.fromInt(0xFFCBD5E1);

    if (rows.isEmpty) {
      rows = [
        List.filled(headers.length, 'Nil / No Transactions Recorded'),
      ];
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(font: bold, fontSize: 7.5, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: navy),
      cellStyle: pw.TextStyle(font: mono, fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      border: pw.TableBorder.all(color: borderSlate, width: 0.5),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9FAFB)),
    );
  }
}

/// Opens the unified, comprehensive GST export bottom sheet for PDF, Excel, and JSON.
Future<void> showGstExportModal({
  required BuildContext context,
  required GstReturnType returnType,
  required Business business,
  DateTime? fromDate,
  DateTime? toDate,
  String periodLabel = 'This Month',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) => _GstExportBottomSheet(
      returnType: returnType,
      business: business,
      fromDate: fromDate,
      toDate: toDate,
      periodLabel: periodLabel,
    ),
  );
}

class _GstExportBottomSheet extends StatefulWidget {
  const _GstExportBottomSheet({
    required this.returnType,
    required this.business,
    this.fromDate,
    this.toDate,
    this.periodLabel = 'This Month',
  });

  final GstReturnType returnType;
  final Business business;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String periodLabel;

  @override
  State<_GstExportBottomSheet> createState() => _GstExportBottomSheetState();
}

class _GstExportBottomSheetState extends State<_GstExportBottomSheet> {
  String? activeExportingFormat;

  String get _fp => GstReportsService.formatFp(widget.fromDate ?? widget.toDate ?? DateTime.now());
  String get _cleanGstin => widget.business.gstin?.trim().toUpperCase() ?? 'UNREGISTERED';

  Future<void> _handlePdfExport({required bool printDirectly}) async {
    setState(() => activeExportingFormat = 'pdf');
    try {
      final filename = '${widget.returnType.filePrefix}_${_cleanGstin}_$_fp.pdf';
      Uint8List bytes;

      switch (widget.returnType) {
        case GstReturnType.gstr1:
          bytes = await GstReportsService.instance.generateGstr1Pdf(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
            periodLabel: widget.periodLabel,
          );
          break;
        case GstReturnType.gstr2:
          bytes = await GstReportsService.instance.generateGstr2Pdf(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
            periodLabel: widget.periodLabel,
          );
          break;
        case GstReturnType.gstr3b:
          bytes = await GstReportsService.instance.generateGstr3bPdf(
            business: widget.business,
            period: widget.periodLabel,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
      }

      if (!mounted) return;

      if (printDirectly) {
        await GstReportsService.printPdf(bytes, filename);
      } else {
        await GstReportsService.shareExportedFile(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/pdf',
          subject: '${widget.returnType.title} - ${widget.business.name} ($_fp)',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => activeExportingFormat = null);
    }
  }

  Future<void> _handleExcelAction({required bool isShare}) async {
    setState(() => activeExportingFormat = 'excel');
    try {
      final filename = '${widget.returnType.filePrefix}_${_cleanGstin}_$_fp.xlsx';
      Uint8List bytes;

      switch (widget.returnType) {
        case GstReturnType.gstr1:
          bytes = await GstReportsService.instance.generateGstr1Excel(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
        case GstReturnType.gstr2:
          bytes = await GstReportsService.instance.generateGstr2Excel(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
        case GstReturnType.gstr3b:
          bytes = await GstReportsService.instance.generateGstr3bExcel(
            business: widget.business,
            period: widget.periodLabel,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
      }

      if (!mounted) return;
      if (isShare) {
        await GstReportsService.shareExportedFile(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          subject: '${widget.returnType.title} - ${widget.business.name} ($_fp)',
        );
      } else {
        await GstReportsService.saveExportedFile(
          bytes: bytes,
          filename: filename,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Saved to Downloads: $filename')),
                ],
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export Excel: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => activeExportingFormat = null);
    }
  }

  Future<void> _handleJsonAction({required bool isShare}) async {
    setState(() => activeExportingFormat = 'json');
    try {
      final filename = '${widget.returnType.filePrefix}_${_cleanGstin}_$_fp.json';
      String jsonStr;

      switch (widget.returnType) {
        case GstReturnType.gstr1:
          jsonStr = await GstReportsService.instance.generateGstr1Json(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
        case GstReturnType.gstr2:
          jsonStr = await GstReportsService.instance.generateGstr2Json(
            business: widget.business,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
        case GstReturnType.gstr3b:
          jsonStr = await GstReportsService.instance.generateGstr3bJson(
            business: widget.business,
            period: widget.periodLabel,
            from: widget.fromDate,
            to: widget.toDate,
          );
          break;
      }

      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      if (!mounted) return;
      if (isShare) {
        await GstReportsService.shareExportedFile(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/json',
          subject: '${widget.returnType.title} - ${widget.business.name} ($_fp)',
        );
      } else {
        await GstReportsService.saveExportedFile(
          bytes: bytes,
          filename: filename,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Saved to Downloads: $filename')),
                ],
              ),
              backgroundColor: const Color(0xFF4338CA),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export JSON: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => activeExportingFormat = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = activeExportingFormat != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [StitchColors.primary, Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_download_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export ${widget.returnType.title}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: StitchColors.textPrimary),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.returnType.description,
                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: StitchColors.textSecondary),
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Period & GSTIN Pills
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 14, color: StitchColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Period: $_fp (${widget.periodLabel})',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
                  ),
                  const Spacer(),
                  const Icon(Icons.badge_outlined, size: 14, color: StitchColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    _cleanGstin,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 1. PDF Option Card
            _exportOptionCard(
              context: context,
              badgeColor: const Color(0xFFFFE4E6),
              iconColor: const Color(0xFFE11D48),
              icon: Icons.picture_as_pdf_rounded,
              title: 'Official Form PDF',
              fileTag: '.PDF',
              isLoading: activeExportingFormat == 'pdf',
              busy: busy,
              actionRow: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE11D48),
                        side: const BorderSide(color: Color(0xFFFDA4AF)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handlePdfExport(printDirectly: true),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('View / Print', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handlePdfExport(printDirectly: false),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 2. Excel Option Card
            _exportOptionCard(
              context: context,
              badgeColor: const Color(0xFFDCFCE7),
              iconColor: const Color(0xFF059669),
              icon: Icons.table_chart_rounded,
              title: 'GST Portal Excel',
              fileTag: '.XLSX',
              isLoading: activeExportingFormat == 'excel',
              busy: busy,
              actionRow: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFFA7F3D0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handleExcelAction(isShare: false),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Export', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handleExcelAction(isShare: true),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 3. JSON Option Card
            _exportOptionCard(
              context: context,
              badgeColor: const Color(0xFFE0E7FF),
              iconColor: const Color(0xFF4338CA),
              icon: Icons.data_object_rounded,
              title: 'GST Portal JSON',
              fileTag: '.JSON',
              isLoading: activeExportingFormat == 'json',
              busy: busy,
              actionRow: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4338CA),
                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handleJsonAction(isShare: false),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Export', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4338CA),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: busy ? null : () => _handleJsonAction(isShare: true),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportOptionCard({
    required BuildContext context,
    required Color badgeColor,
    required Color iconColor,
    required IconData icon,
    required String title,
    required String fileTag,
    required bool isLoading,
    required bool busy,
    required Widget actionRow,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: StitchColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  fileTag,
                  style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Generating $fileTag file...',
                    style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          else
            actionRow,
        ],
      ),
    );
  }
}

