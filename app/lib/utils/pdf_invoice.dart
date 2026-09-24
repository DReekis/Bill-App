import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../data/repositories.dart';

enum InvoicePaperSize {
  a4('A4 Standard', 'Standard office / laser printing (210 × 297 mm)', Icons.description_outlined, PdfPageFormat.a4),
  a5('A5 Compact', 'Half-page voucher format (148 × 210 mm)', Icons.receipt_long_outlined, PdfPageFormat.a5),
  roll80mm('80mm Thermal (3-inch)', 'Counter POS continuous thermal receipt roll', Icons.point_of_sale_rounded, PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm)),
  roll58mm('58mm Thermal (2-inch)', 'Portable handheld mini thermal receipt roll', Icons.receipt_outlined, PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 2.5 * PdfPageFormat.mm));

  const InvoicePaperSize(this.label, this.description, this.icon, this.format);
  final String label;
  final String description;
  final IconData icon;
  final PdfPageFormat format;
}

String getBusinessUpiId(Business business) {
  if (business.upiId != null && business.upiId!.trim().isNotEmpty) {
    return business.upiId!.trim();
  }
  if (business.displayInvoicePhone.isNotEmpty) {
    return '${business.displayInvoicePhone}@upi';
  }
  return 'merchant@upi';
}

String generateUpiPaymentUri({
  required Business business,
  required String invoiceNumber,
  required int amountPaise,
}) {
  final vpa = getBusinessUpiId(business);
  final payeeName = Uri.encodeComponent(business.name.trim());
  final amount = (amountPaise / 100).toStringAsFixed(2);
  final note = Uri.encodeComponent('Invoice $invoiceNumber');
  return 'upi://pay?pa=$vpa&pn=$payeeName&am=$amount&cu=INR&tn=$note';
}

class _GstBreakupItem {
  final String hsn;
  final int gstRate;
  int taxable = 0;
  int tax = 0;

  _GstBreakupItem({
    required this.hsn,
    required this.gstRate,
  });
}

Future<Uint8List> buildDocumentPdf({
  required Business business,
  required String title,
  required String number,
  required String date,
  String? dueDate,
  Customer? customer,
  required String? partyName,
  String? partyPhone,
  String? partyAddress,
  String? partyGstin,
  String? partyState,
  required List<InvoiceLine> lines,
  required int subtotal,
  required int discount,
  required int taxable,
  required int igst,
  required int cgst,
  required int sgst,
  required int roundOff,
  required int total,
  required int outstandingPaise,
  String? notes,
  String? termsText,
  BankAccount? bankAccount,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final doc = pw.Document();
  final mono = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();

  // Premium corporate BillBook styling palette
  const navy = PdfColor.fromInt(0xFF1E3A8A);
  const slateDark = PdfColor.fromInt(0xFF0F172A);
  const slateMuted = PdfColor.fromInt(0xFF475569);
  const slateLight = PdfColor.fromInt(0xFFF8FAFC);
  const borderSlate = PdfColor.fromInt(0xFFCBD5E1);

  String money(int paise) => formatPaise(paise).replaceAll('₹', 'Rs.');

  // Pre-load images safely if present
  pw.MemoryImage? logoImage;
  if (business.logoPath != null && business.logoPath!.isNotEmpty) {
    try {
      final file = File(business.logoPath!);
      if (file.existsSync()) {
        logoImage = pw.MemoryImage(file.readAsBytesSync());
      }
    } catch (_) {}
  }

  pw.MemoryImage? signatureImage;
  if (business.signaturePath != null && business.signaturePath!.isNotEmpty) {
    try {
      final file = File(business.signaturePath!);
      if (file.existsSync()) {
        signatureImage = pw.MemoryImage(file.readAsBytesSync());
      }
    } catch (_) {}
  }

  // Resolve Customer contact details
  final resolvedPartyName = partyName != null && partyName.trim().isNotEmpty
      ? partyName.trim()
      : (customer?.name.trim().isNotEmpty == true ? customer!.name.trim() : 'Cash / Walk-in Customer');
  final resolvedPartyPhone = partyPhone ?? customer?.phone ?? '';
  final resolvedPartyAddress = partyAddress ??
      [
        customer?.billingAddress,
        if (customer != null && customer.city != null && customer.city!.isNotEmpty) customer.city,
        if (customer != null && customer.pin != null && customer.pin!.isNotEmpty) 'PIN: ${customer.pin}',
      ].where((e) => e != null && e.isNotEmpty).join(', ');
  final resolvedPartyGstin = partyGstin ?? customer?.gstin ?? '';
  final resolvedPartyState = partyState ?? customer?.state ?? '';

  // Resolve Terms & Conditions
  String? rawTerms = termsText;
  if (rawTerms == null || rawTerms.trim().isEmpty) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('estimate') || lowerTitle.contains('quotation')) {
      rawTerms = business.termsQuotation;
    } else if (lowerTitle.contains('purchase')) {
      rawTerms = business.termsPurchase;
    } else if (lowerTitle.contains('challan')) {
      rawTerms = business.termsChallan;
    } else {
      rawTerms = business.termsSales;
    }
  }

  final termsList = rawTerms != null
      ? rawTerms
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
      : <String>[];

  // UPI payment QR data
  final upiUri = generateUpiPaymentUri(
    business: business,
    invoiceNumber: number,
    amountPaise: outstandingPaise > 0 ? outstandingPaise : total,
  );
  final upiVpa = getBusinessUpiId(business);

  // Group items for GST Tax Breakup Table
  final gstMap = <String, _GstBreakupItem>{};
  for (final l in lines) {
    final key = '${l.hsn ?? "General"}_${l.gstRate}';
    final item = gstMap.putIfAbsent(
      key,
      () => _GstBreakupItem(hsn: l.hsn ?? 'General', gstRate: l.gstRate),
    );
    item.taxable += l.taxable;
    item.tax += l.tax;
  }

  final isInterState = igst > 0;
  final hasGst = lines.any((l) => l.gstRate > 0) || cgst > 0 || sgst > 0 || igst > 0;

  // Header Component
  pw.Widget headerWidget() => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 52,
                    height: 52,
                    margin: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(business.name,
                          style: pw.TextStyle(font: bold, fontSize: 16, color: navy)),
                      if (business.address != null && business.address!.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          [
                            business.address,
                            if (business.city != null && business.city!.isNotEmpty) business.city,
                            if (business.state != null && business.state!.isNotEmpty) business.state,
                            if (business.pinCode != null && business.pinCode!.isNotEmpty) 'PIN: ${business.pinCode}',
                          ].where((e) => e != null && e.isNotEmpty).join(', '),
                          style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted),
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Row(children: [
                        if (business.displayInvoicePhone.isNotEmpty) ...[
                          pw.Text('Phone: ', style: pw.TextStyle(font: bold, fontSize: 8, color: slateDark)),
                          pw.Text(business.displayInvoicePhone, style: pw.TextStyle(font: mono, fontSize: 8, color: slateDark)),
                          pw.SizedBox(width: 8),
                        ],
                        if (business.displayInvoiceEmail.isNotEmpty) ...[
                          pw.Text('Email: ', style: pw.TextStyle(font: bold, fontSize: 8, color: slateDark)),
                          pw.Text(business.displayInvoiceEmail, style: pw.TextStyle(font: mono, fontSize: 8, color: slateDark)),
                        ],
                      ]),
                      if (business.gstin != null && business.gstin!.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.Text('GSTIN: ', style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark)),
                          pw.Text(business.gstin!, style: pw.TextStyle(font: bold, fontSize: 8.5, color: navy)),
                          if (business.pan != null && business.pan!.isNotEmpty) ...[
                            pw.SizedBox(width: 8),
                            pw.Text('PAN: ', style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark)),
                            pw.Text(business.pan!, style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateDark)),
                          ],
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Container(
            width: 175,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: navy,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    title.toUpperCase(),
                    style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.white),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Table(
                  columnWidths: const {
                    0: pw.IntrinsicColumnWidth(),
                    1: pw.FixedColumnWidth(6),
                    2: pw.FlexColumnWidth(),
                  },
                  children: [
                    pw.TableRow(children: [
                      pw.Text('Doc No', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                      pw.Text(':', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                      pw.Text(number, style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark), textAlign: pw.TextAlign.right),
                    ]),
                    pw.TableRow(children: [
                      pw.Text('Date', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                      pw.Text(':', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                      pw.Text(displayDate(date), style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateDark), textAlign: pw.TextAlign.right),
                    ]),
                    if (dueDate != null && dueDate.isNotEmpty)
                      pw.TableRow(children: [
                        pw.Text('Due Date', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                        pw.Text(':', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                        pw.Text(displayDate(dueDate), style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateDark), textAlign: pw.TextAlign.right),
                      ]),
                    if (business.state != null && business.state!.isNotEmpty)
                      pw.TableRow(children: [
                        pw.Text('Place of Supply', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                        pw.Text(':', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                        pw.Text(business.state!, style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateDark), textAlign: pw.TextAlign.right),
                      ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  // Customer Billed To Section
  pw.Widget partySection() => pw.Container(
        decoration: pw.BoxDecoration(
          color: slateLight,
          border: pw.Border.all(color: borderSlate, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BILLED TO', style: pw.TextStyle(font: bold, fontSize: 8, color: navy)),
                  pw.SizedBox(height: 2),
                  pw.Text(resolvedPartyName, style: pw.TextStyle(font: bold, fontSize: 10, color: slateDark)),
                  if (resolvedPartyAddress.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(resolvedPartyAddress, style: pw.TextStyle(font: mono, fontSize: 8, color: slateMuted)),
                  ],
                  if (resolvedPartyPhone.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text('Phone: $resolvedPartyPhone', style: pw.TextStyle(font: mono, fontSize: 8, color: slateMuted)),
                  ],
                  if (resolvedPartyGstin.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Row(children: [
                      pw.Text('GSTIN: ', style: pw.TextStyle(font: bold, fontSize: 8, color: slateDark)),
                      pw.Text(resolvedPartyGstin, style: pw.TextStyle(font: bold, fontSize: 8, color: navy)),
                    ]),
                  ],
                  if (resolvedPartyState.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text('State: $resolvedPartyState', style: pw.TextStyle(font: mono, fontSize: 8, color: slateMuted)),
                  ],
                ],
              ),
            ),
            pw.Container(width: 0.6, height: 60, color: borderSlate, margin: const pw.EdgeInsets.symmetric(horizontal: 10)),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (customer != null && customer.shippingAddress != null && customer.shippingAddress!.trim().isNotEmpty) ...[
                    pw.Text('SHIPPED TO', style: pw.TextStyle(font: bold, fontSize: 8, color: navy)),
                    pw.SizedBox(height: 2),
                    pw.Text(resolvedPartyName, style: pw.TextStyle(font: bold, fontSize: 9.5, color: slateDark)),
                    pw.SizedBox(height: 1),
                    pw.Text(customer.shippingAddress!, style: pw.TextStyle(font: mono, fontSize: 8, color: slateMuted)),
                  ] else ...[
                    pw.Text('PAYMENT & STATUS', style: pw.TextStyle(font: bold, fontSize: 8, color: navy)),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('Status: ', style: pw.TextStyle(font: mono, fontSize: 8.5, color: slateMuted)),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: pw.BoxDecoration(
                          color: outstandingPaise <= 0 ? const PdfColor.fromInt(0xFFDEF7EC) : const PdfColor.fromInt(0xFFFEF3C7),
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                        child: pw.Text(
                          outstandingPaise <= 0 ? 'PAID' : (outstandingPaise < total ? 'PARTIALLY PAID' : 'UNPAID'),
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 7.5,
                            color: outstandingPaise <= 0 ? const PdfColor.fromInt(0xFF03543F) : const PdfColor.fromInt(0xFF92400E),
                          ),
                        ),
                      ),
                    ]),
                    pw.SizedBox(height: 2),
                    pw.Text('Total Amount: ${money(total)}', style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark)),
                    if (outstandingPaise > 0)
                      pw.Text('Balance Due: ${money(outstandingPaise)}', style: pw.TextStyle(font: bold, fontSize: 8.5, color: const PdfColor.fromInt(0xFFDC2626))),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  // Items Table
  pw.Widget itemsTable() {
    final headers = ['#', 'Items & Description', 'HSN/SAC', 'Qty', 'Rate', 'Disc.', 'Taxable', 'GST %', 'Amount'];
    final data = <List<String>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final itemTotal = l.taxable + l.tax;
      data.add([
        '${i + 1}',
        l.name,
        l.hsn ?? '-',
        '${_qty(l.quantity)} ${l.unit ?? ""}'.trim(),
        money(l.price),
        _qty(l.discountPercent) == '0' ? '-' : '${_qty(l.discountPercent)}%',
        money(l.taxable),
        l.gstRate > 0 ? '${l.gstRate}%' : '0%',
        money(itemTotal),
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: navy),
      cellStyle: pw.TextStyle(font: mono, fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9FAFB)),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      border: pw.TableBorder.all(color: borderSlate, width: 0.5),
    );
  }

  // GST Tax Breakup Table
  pw.Widget gstTaxBreakupTable() {
    if (!hasGst) return pw.SizedBox.shrink();

    final headers = isInterState
        ? ['HSN/SAC', 'Taxable Val', 'IGST %', 'IGST Amt', 'Total Tax']
        : ['HSN/SAC', 'Taxable Val', 'CGST %', 'CGST Amt', 'SGST %', 'SGST Amt', 'Total Tax'];

    final rows = <List<String>>[];
    var totalTaxable = 0;
    var totalCgst = 0;
    var totalSgst = 0;
    var totalIgst = 0;
    var grandTax = 0;

    for (final item in gstMap.values) {
      totalTaxable += item.taxable;
      grandTax += item.tax;

      if (isInterState) {
        totalIgst += item.tax;
        rows.add([
          item.hsn,
          money(item.taxable),
          '${item.gstRate}%',
          money(item.tax),
          money(item.tax),
        ]);
      } else {
        final halfRate = (item.gstRate / 2).toStringAsFixed(1).replaceAll('.0', '');
        final halfTax = item.tax ~/ 2;
        final remainderTax = item.tax - halfTax;
        totalCgst += halfTax;
        totalSgst += remainderTax;
        rows.add([
          item.hsn,
          money(item.taxable),
          '$halfRate%',
          money(halfTax),
          '$halfRate%',
          money(remainderTax),
          money(item.tax),
        ]);
      }
    }

    // Totals row
    if (isInterState) {
      rows.add(['Total', money(totalTaxable), '', money(totalIgst), money(grandTax)]);
    } else {
      rows.add(['Total', money(totalTaxable), '', money(totalCgst), '', money(totalSgst), money(grandTax)]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 10),
        pw.Text('Tax Breakup Summary (HSN/SAC):', style: pw.TextStyle(font: bold, fontSize: 8, color: navy)),
        pw.SizedBox(height: 3),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(font: bold, fontSize: 7.5, color: slateDark),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
          cellStyle: pw.TextStyle(font: mono, fontSize: 7.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
          border: pw.TableBorder.all(color: borderSlate, width: 0.5),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
        ),
      ],
    );
  }

  // Summary and Calculations Row
  pw.Widget summarySection() {
    pw.Widget calcRow(String label, String value, {bool isBold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(font: isBold ? bold : mono, fontSize: 8.5, color: slateMuted)),
              pw.Text(value, style: pw.TextStyle(font: isBold ? bold : mono, fontSize: 8.5, color: color ?? slateDark)),
            ],
          ),
        );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Amount in Words + Notes
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: slateLight,
                  border: pw.Border.all(color: borderSlate, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Amount in Words:', style: pw.TextStyle(font: bold, fontSize: 7.5, color: slateMuted)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _amountInWords(total),
                      style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark),
                    ),
                  ],
                ),
              ),
              if (notes != null && notes.trim().isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text('Notes: $notes', style: pw.TextStyle(font: mono, fontSize: 8, color: slateMuted)),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        // Right: Calculation card
        pw.Container(
          width: 215,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: borderSlate, width: 0.6),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: [
              pw.SizedBox(height: 4),
              calcRow('Taxable Amount', money(taxable)),
              if (discount > 0) calcRow('Total Discount', '-${money(discount)}'),
              if (cgst > 0) calcRow('CGST', '+${money(cgst)}'),
              if (sgst > 0) calcRow('SGST', '+${money(sgst)}'),
              if (igst > 0) calcRow('IGST', '+${money(igst)}'),
              if (roundOff != 0)
                calcRow('Round Off', '${roundOff > 0 ? "+" : "-"}${money(roundOff.abs())}'),
              pw.Divider(thickness: 0.6, color: borderSlate),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: const PdfColor.fromInt(0xFFEEF2FF),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Amount', style: pw.TextStyle(font: bold, fontSize: 10, color: navy)),
                    pw.Text(money(total), style: pw.TextStyle(font: bold, fontSize: 11, color: navy)),
                  ],
                ),
              ),
              if (outstandingPaise > 0 && outstandingPaise != total) ...[
                pw.Divider(thickness: 0.6, color: borderSlate),
                calcRow('Balance Due', money(outstandingPaise), isBold: true, color: const PdfColor.fromInt(0xFFDC2626)),
              ],
              pw.SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  // Bottom Bank & Signatory section
  pw.Widget bankAndSignatorySection() => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Left: Bank details & UPI QR
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (bankAccount != null) ...[
                  pw.Container(
                    width: 140,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderSlate, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: const PdfColor.fromInt(0xFFFAFAFA),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BANK DETAILS', style: pw.TextStyle(font: bold, fontSize: 7.5, color: navy)),
                        pw.SizedBox(height: 3),
                        pw.Text('Bank: ${bankAccount.bankName}', style: pw.TextStyle(font: mono, fontSize: 7, color: slateDark)),
                        if (bankAccount.accountNumber != null)
                          pw.Text('A/C No: ${bankAccount.accountNumber}', style: pw.TextStyle(font: bold, fontSize: 7, color: slateDark)),
                        if (bankAccount.ifsc != null)
                          pw.Text('IFSC: ${bankAccount.ifsc}', style: pw.TextStyle(font: mono, fontSize: 7, color: slateDark)),
                        if (bankAccount.accountName != null)
                          pw.Text('Name: ${bankAccount.accountName}', style: pw.TextStyle(font: mono, fontSize: 6.5, color: slateMuted)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                ],
                if (business.showPaymentQr && total > 0) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderSlate, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColors.white,
                    ),
                    child: pw.Column(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: upiUri,
                          width: 50,
                          height: 50,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('Scan & Pay UPI', style: pw.TextStyle(font: bold, fontSize: 6.5, color: navy)),
                        pw.Text(upiVpa, style: pw.TextStyle(font: mono, fontSize: 5.5, color: slateMuted)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          // Right: Terms & Signature
          pw.Container(
            width: 215,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (termsList.isNotEmpty) ...[
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Terms & Conditions:', style: pw.TextStyle(font: bold, fontSize: 7.5, color: slateDark)),
                        pw.SizedBox(height: 2),
                        ...termsList.map((t) => pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 1.5),
                              child: pw.Text('• $t', style: pw.TextStyle(font: mono, fontSize: 6.5, color: slateMuted)),
                            )),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('For ${business.name}', style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark)),
                    pw.SizedBox(height: 4),
                    if (signatureImage != null)
                      pw.Container(
                        height: 38,
                        child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                      )
                    else if (business.showEmptySignatureBox)
                      pw.Container(
                        width: 105,
                        height: 36,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderSlate, width: 0.6),
                          borderRadius: pw.BorderRadius.circular(3),
                          color: const PdfColor.fromInt(0xFFFAFAFA),
                        ),
                        alignment: pw.Alignment.center,
                        child: pw.Text('Stamp / Signature', style: pw.TextStyle(font: mono, fontSize: 6.5, color: PdfColors.grey500)),
                      )
                    else
                      pw.SizedBox(height: 22),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      business.signatureText.trim().isNotEmpty
                          ? business.signatureText.trim()
                          : 'Authorised Signatory',
                      style: pw.TextStyle(font: bold, fontSize: 7.5, color: slateDark),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  // Add MultiPage Document
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        margin: pageFormat == PdfPageFormat.a5
            ? const pw.EdgeInsets.all(16)
            : const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: borderSlate, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('This is a computer-generated invoice | Powered by Billket',
                style: pw.TextStyle(font: mono, fontSize: 7, color: slateMuted)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(font: mono, fontSize: 7, color: slateMuted)),
          ],
        ),
      ),
      build: (context) => [
        headerWidget(),
        pw.SizedBox(height: 12),
        partySection(),
        pw.SizedBox(height: 12),
        itemsTable(),
        gstTaxBreakupTable(),
        pw.SizedBox(height: 12),
        summarySection(),
        pw.SizedBox(height: 16),
        bankAndSignatorySection(),
      ],
    ),
  );

  return doc.save();
}

Future<Uint8List> buildThermalReceiptPdf({
  required Business business,
  required String title,
  required String number,
  required String date,
  String? dueDate,
  required String? partyName,
  required List<InvoiceLine> lines,
  required int subtotal,
  required int discount,
  required int taxable,
  required int igst,
  required int cgst,
  required int sgst,
  required int roundOff,
  required int total,
  required int outstandingPaise,
  String? notes,
  required InvoicePaperSize paperSize,
}) async {
  final doc = pw.Document();
  final mono = pw.Font.courier();
  final bold = pw.Font.courierBold();
  final is58mm = paperSize == InvoicePaperSize.roll58mm;
  final fontSize = is58mm ? 7.5 : 8.5;
  final smallFontSize = is58mm ? 6.5 : 7.5;
  final titleFontSize = is58mm ? 11.0 : 13.0;

  String money(int paise) => formatPaise(paise).replaceAll('₹', 'Rs.');

  final upiUri = generateUpiPaymentUri(
    business: business,
    invoiceNumber: number,
    amountPaise: outstandingPaise > 0 ? outstandingPaise : total,
  );
  final upiVpa = getBusinessUpiId(business);

  pw.Widget dashedDivider([String char = '-']) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(
          List.filled(is58mm ? 32 : 44, char).join(),
          maxLines: 1,
          style: pw.TextStyle(font: mono, fontSize: smallFontSize, color: PdfColors.grey700),
        ),
      );

  pw.Widget thermalRow(String label, String value, {bool isBold = false, double? customSize}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: isBold ? bold : mono, fontSize: customSize ?? fontSize)),
            pw.Text(value, style: pw.TextStyle(font: isBold ? bold : mono, fontSize: customSize ?? fontSize)),
          ],
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: paperSize.format,
      margin: pw.EdgeInsets.all(is58mm ? 3 * PdfPageFormat.mm : 4 * PdfPageFormat.mm),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Center(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  business.name.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: bold, fontSize: titleFontSize),
                ),
                if (business.address != null && business.address!.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(business.address!, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: smallFontSize)),
                ],
                if (business.displayInvoicePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text('Ph: ${business.displayInvoicePhone}', style: pw.TextStyle(font: mono, fontSize: smallFontSize)),
                ],
                if (business.gstin != null && business.gstin!.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text('GSTIN: ${business.gstin!}', style: pw.TextStyle(font: bold, fontSize: smallFontSize)),
                ],
              ],
            ),
          ),

          dashedDivider('='),

          // Doc details
          thermalRow('DOC:', title.toUpperCase()),
          thermalRow('NO:', number, isBold: true),
          thermalRow('DATE:', displayDate(date)),
          if (partyName != null && partyName.isNotEmpty)
            thermalRow('CLIENT:', partyName),

          dashedDivider('-'),

          // Items
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ITEM', style: pw.TextStyle(font: bold, fontSize: fontSize)),
              pw.Text('AMT', style: pw.TextStyle(font: bold, fontSize: fontSize)),
            ],
          ),
          pw.SizedBox(height: 2),

          ...lines.map((l) {
            final itemTotal = l.taxable + l.tax;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(l.name, style: pw.TextStyle(font: bold, fontSize: fontSize)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '  ${_qty(l.quantity)} x ${money(l.price)}${l.gstRate > 0 ? " (GST ${l.gstRate}%)" : ""}',
                        style: pw.TextStyle(font: mono, fontSize: smallFontSize, color: PdfColors.grey800),
                      ),
                      pw.Text(money(itemTotal), style: pw.TextStyle(font: mono, fontSize: fontSize)),
                    ],
                  ),
                ],
              ),
            );
          }),

          dashedDivider('-'),

          // Totals
          thermalRow('Subtotal:', money(subtotal)),
          if (discount > 0)
            thermalRow('Discount:', '-${money(discount)}'),
          if (cgst > 0)
            thermalRow('CGST:', money(cgst)),
          if (sgst > 0)
            thermalRow('SGST:', money(sgst)),
          if (igst > 0)
            thermalRow('IGST:', money(igst)),
          if (roundOff != 0)
            thermalRow('Round Off:', '${roundOff > 0 ? "+" : "-"}${money(roundOff.abs())}'),

          dashedDivider('='),

          thermalRow('NET TOTAL:', money(total), isBold: true, customSize: titleFontSize),

          if (outstandingPaise > 0 && outstandingPaise != total)
            thermalRow('DUE BALANCE:', money(outstandingPaise), isBold: true),

          dashedDivider('-'),

          // UPI Payment QR
          if (business.showPaymentQr && total > 0) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('SCAN & PAY VIA UPI', style: pw.TextStyle(font: bold, fontSize: fontSize)),
                  pw.SizedBox(height: 3),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: PdfColors.black, width: 0.5),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: upiUri,
                      width: is58mm ? 65 : 85,
                      height: is58mm ? 65 : 85,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('UPI ID: $upiVpa', style: pw.TextStyle(font: mono, fontSize: smallFontSize)),
                  pw.Text('GPay | PhonePe | Paytm | BHIM', style: pw.TextStyle(font: mono, fontSize: smallFontSize, color: PdfColors.grey700)),
                ],
              ),
            ),
            dashedDivider('-'),
          ],

          // Footer
          pw.Center(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (notes != null && notes.isNotEmpty) ...[
                  pw.Text(notes, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: smallFontSize)),
                  pw.SizedBox(height: 2),
                ],
                pw.Text('Thank you! Visit again.', style: pw.TextStyle(font: bold, fontSize: smallFontSize)),
                pw.SizedBox(height: 1),
                pw.Text('Powered by Billket', style: pw.TextStyle(font: mono, fontSize: smallFontSize - 1, color: PdfColors.grey600)),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
        ],
      ),
    ),
  );

  return doc.save();
}

Future<Uint8List> buildInvoicePdf({
  required Business business,
  required Invoice invoice,
  Customer? customer,
  BankAccount? bankAccount,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  customer ??= (invoice.customerId != null && business.id != null)
      ? await Repository.instance.customer(business.id!, invoice.customerId!)
      : null;

  bankAccount ??= (business.bankAccountId != null)
      ? await Repository.instance.getBankAccount(business.bankAccountId!)
      : (business.id != null
          ? (await Repository.instance.bankAccounts(business.id!)).where((b) => !b.inactive).firstOrNull
          : null);

  if (paperSize == InvoicePaperSize.roll58mm || paperSize == InvoicePaperSize.roll80mm) {
    return buildThermalReceiptPdf(
      business: business,
      title: 'Tax Invoice',
      number: invoice.number,
      date: invoice.date,
      dueDate: invoice.dueDate,
      partyName: invoice.customerName,
      lines: invoice.lines,
      subtotal: invoice.subtotal,
      discount: invoice.discount,
      taxable: invoice.taxable,
      igst: invoice.igst,
      cgst: invoice.cgst,
      sgst: invoice.sgst,
      roundOff: invoice.roundOff,
      total: invoice.total,
      outstandingPaise: invoice.outstanding.paise,
      notes: invoice.notes,
      paperSize: paperSize,
    );
  }

  return buildDocumentPdf(
    business: business,
    title: 'Tax Invoice',
    number: invoice.number,
    date: invoice.date,
    dueDate: invoice.dueDate,
    customer: customer,
    partyName: invoice.customerName,
    lines: invoice.lines,
    subtotal: invoice.subtotal,
    discount: invoice.discount,
    taxable: invoice.taxable,
    igst: invoice.igst,
    cgst: invoice.cgst,
    sgst: invoice.sgst,
    roundOff: invoice.roundOff,
    total: invoice.total,
    outstandingPaise: invoice.outstanding.paise,
    notes: invoice.notes,
    termsText: business.termsSales,
    bankAccount: bankAccount,
    pageFormat: paperSize.format,
  );
}

Future<Uint8List> buildQuotationPdf({
  required Business business,
  required Quotation quotation,
  Customer? customer,
  BankAccount? bankAccount,
}) async {
  customer ??= (quotation.customerId != null && business.id != null)
      ? await Repository.instance.customer(business.id!, quotation.customerId!)
      : null;

  bankAccount ??= (business.bankAccountId != null)
      ? await Repository.instance.getBankAccount(business.bankAccountId!)
      : (business.id != null
          ? (await Repository.instance.bankAccounts(business.id!)).where((b) => !b.inactive).firstOrNull
          : null);

  return buildDocumentPdf(
    business: business,
    title: quotation.isProforma ? 'Proforma Invoice' : 'Estimate',
    number: quotation.number,
    date: quotation.date,
    dueDate: quotation.expiryDate,
    customer: customer,
    partyName: quotation.customerName,
    lines: quotation.lines,
    subtotal: quotation.subtotal,
    discount: quotation.discount,
    taxable: quotation.taxable,
    igst: quotation.igst,
    cgst: quotation.cgst,
    sgst: quotation.sgst,
    roundOff: 0,
    total: quotation.total,
    outstandingPaise: quotation.total,
    notes: quotation.notes,
    termsText: business.termsQuotation,
    bankAccount: bankAccount,
  );
}

Future<Uint8List> buildReturnPdf({
  required Business business,
  required TransactionReturn ret,
  Customer? customer,
  BankAccount? bankAccount,
}) => buildDocumentPdf(
  business: business,
  title: ret.partyType == 'customer' ? 'Credit Note' : 'Debit Note',
  number: ret.number,
  date: ret.date,
  customer: customer,
  partyName: ret.partyName,
  lines: ret.lines,
  subtotal: ret.subtotal,
  discount: 0,
  taxable: ret.taxable,
  igst: 0,
  cgst: 0,
  sgst: 0,
  roundOff: 0,
  total: ret.total,
  outstandingPaise: 0,
  notes: ret.reason,
  bankAccount: bankAccount,
);

Future<void> printInvoice({
  required Business business,
  required Invoice invoice,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  final bytes = await buildInvoicePdf(business: business, invoice: invoice, paperSize: paperSize);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${invoice.number}.pdf',
    format: paperSize.format,
  );
}

Future<void> shareInvoice({
  required Business business,
  required Invoice invoice,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  final bytes = await buildInvoicePdf(business: business, invoice: invoice, paperSize: paperSize);
  await Printing.sharePdf(bytes: bytes, filename: '${invoice.number}.pdf');
}

Future<void> printQuotation({
  required Business business,
  required Quotation quotation,
}) async {
  final bytes = await buildQuotationPdf(business: business, quotation: quotation);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${quotation.number}.pdf',
  );
}

Future<void> shareQuotation({
  required Business business,
  required Quotation quotation,
}) async {
  final bytes = await buildQuotationPdf(business: business, quotation: quotation);
  await Printing.sharePdf(bytes: bytes, filename: '${quotation.number}.pdf');
}

String _qty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(3);

String _amountInWords(int paise) {
  final negative = paise < 0;
  final absPaise = paise.abs();
  final rupees = absPaise ~/ 100;
  final remPaise = absPaise % 100;

  if (rupees == 0 && remPaise == 0) return 'Zero Rupees only';

  const ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen'
  ];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  String two(int n) {
    if (n < 20) return ones[n];
    return '${tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${ones[n % 10]}'}';
  }

  String three(int n) {
    final h = n ~/ 100;
    final rest = n % 100;
    if (h == 0) return two(rest);
    return '${ones[h]} Hundred${rest > 0 ? ' ${two(rest)}' : ''}';
  }

  final words = <String>[];
  final crore = rupees ~/ 10000000;
  final lakh = (rupees % 10000000) ~/ 100000;
  final thousand = (rupees % 100000) ~/ 1000;
  final hundred = rupees % 1000;
  if (crore > 0) words.add('${two(crore)} Crore');
  if (lakh > 0) words.add('${two(lakh)} Lakh');
  if (thousand > 0) words.add('${two(thousand)} Thousand');
  if (hundred > 0) words.add(three(hundred));

  var result = words.isNotEmpty ? '${words.join(' ')} Rupees' : '';
  if (remPaise > 0) {
    final paiseStr = '${two(remPaise)} Paise';
    if (result.isNotEmpty) {
      result += ' and $paiseStr';
    } else {
      result = paiseStr;
    }
  }
  result = '$result only';
  return negative ? 'Minus $result' : result;
}