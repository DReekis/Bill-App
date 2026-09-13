import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

class ExportService {
  /// Export sales invoices to Excel
  static Future<void> exportToExcel(
    List<Invoice> invoices, {
    String? businessName,
    String? fileName,
  }) async {
    if (kIsWeb) {
      throw Exception(
          'Excel export is only available on mobile and desktop platforms');
    }

    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Add headers
      final headers = [
        'Invoice Number',
        'Date',
        'Customer',
        'Subtotal',
        'Discount',
        'Tax',
        'Total',
        'Amount Paid',
        'Outstanding',
        'Status',
        'Payment Mode',
      ];

      sheet.appendRow(headers);

      // Add data rows
      for (final invoice in invoices) {
        sheet.appendRow([
          invoice.number,
          invoice.date,
          invoice.customerName ?? 'Walk-in',
          _formatAmount(invoice.subtotal),
          _formatAmount(invoice.discount),
          _formatAmount(invoice.cgst + invoice.sgst + invoice.igst),
          _formatAmount(invoice.total),
          _formatAmount(invoice.amountPaid),
          _formatAmount(invoice.total - invoice.amountPaid),
          invoice.status,
          invoice.paymentMode ?? '-',
        ]);
      }

      // Save and share
      final bytes = excel.encode();
      if (bytes != null) {
        final exportFileName =
            '${fileName ?? "Sales_Report"}-${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$exportFileName');
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Sales Report - $businessName',
        );
      }
    } catch (e) {
      throw Exception('Failed to export to Excel: $e');
    }
  }

  /// Export sales invoices to JSON
  static Future<void> exportToJson(
    List<Invoice> invoices, {
    String? businessName,
    String? fileName,
  }) async {
    if (kIsWeb) {
      throw Exception(
          'JSON export is only available on mobile and desktop platforms');
    }

    try {
      final data = {
        'export_date': DateTime.now().toIso8601String(),
        'business_name': businessName,
        'total_invoices': invoices.length,
        'invoices': invoices
            .map((inv) => {
                  'number': inv.number,
                  'date': inv.date,
                  'customer_name': inv.customerName,
                  'subtotal': inv.subtotal,
                  'discount': inv.discount,
                  'tax': {
                    'cgst': inv.cgst,
                    'sgst': inv.sgst,
                    'igst': inv.igst,
                    'cess': inv.cess,
                  },
                  'total': inv.total,
                  'amount_paid': inv.amountPaid,
                  'outstanding': inv.total - inv.amountPaid,
                  'status': inv.status,
                  'payment_mode': inv.paymentMode,
                  'notes': inv.notes,
                  'lines': inv.lines
                      .map((line) => {
                            'product_name': line.name,
                            'hsn': line.hsn,
                            'quantity': line.quantity,
                            'price': line.price,
                            'discount_percent': line.discountPercent,
                            'gst_rate': line.gstRate,
                            'tax': line.tax,
                          })
                      .toList(),
                })
            .toList(),
      };

      final jsonString = jsonEncode(data);
      final exportFileName =
          '${fileName ?? "Sales_Report"}-${DateTime.now().millisecondsSinceEpoch}.json';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$exportFileName');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Sales Report - $businessName',
      );
    } catch (e) {
      throw Exception('Failed to export to JSON: $e');
    }
  }

  /// Export sales data as CSV
  static Future<void> exportToCsv(
    List<Invoice> invoices, {
    String? businessName,
    String? fileName,
  }) async {
    if (kIsWeb) {
      throw Exception(
          'CSV export is only available on mobile and desktop platforms');
    }

    try {
      final rows = <List<dynamic>>[
        [
          'Invoice Number',
          'Date',
          'Customer',
          'Subtotal',
          'Discount',
          'Tax',
          'Total',
          'Amount Paid',
          'Outstanding',
          'Status',
          'Payment Mode',
        ]
      ];

      for (final invoice in invoices) {
        rows.add([
          invoice.number,
          invoice.date,
          invoice.customerName ?? 'Walk-in',
          _formatAmount(invoice.subtotal),
          _formatAmount(invoice.discount),
          _formatAmount(invoice.cgst + invoice.sgst + invoice.igst),
          _formatAmount(invoice.total),
          _formatAmount(invoice.amountPaid),
          _formatAmount(invoice.total - invoice.amountPaid),
          invoice.status,
          invoice.paymentMode ?? '-',
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final exportFileName =
          '${fileName ?? "Sales_Report"}-${DateTime.now().millisecondsSinceEpoch}.csv';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$exportFileName');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Sales Report - $businessName',
      );
    } catch (e) {
      throw Exception('Failed to export to CSV: $e');
    }
  }

  static String _formatAmount(int paise) {
    return (paise / 100).toStringAsFixed(2);
  }
}
