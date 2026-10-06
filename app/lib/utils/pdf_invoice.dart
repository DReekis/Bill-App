import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

PdfColor _parseHexColor(String hexString, {PdfColor defaultColor = const PdfColor.fromInt(0xFF1E3A8A)}) {
  try {
    final hex = hexString.replaceAll('#', '').trim();
    if (hex.length == 6) {
      return PdfColor.fromInt(int.parse('FF$hex', radix: 16));
    } else if (hex.length == 8) {
      return PdfColor.fromInt(int.parse(hex, radix: 16));
    }
  } catch (_) {}
  return defaultColor;
}

class _GstBreakupItem {
  final String hsn;
  final int gstRate;
  int taxable = 0;
  int cgst = 0;
  int sgst = 0;
  int igst = 0;

  _GstBreakupItem({
    required this.hsn,
    required this.gstRate,
  });

  int get totalTax => cgst + sgst + igst;
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
  InvoiceCustomizationSettings? settings,
  String? shipToName,
  String? shipToAddress,
  String? shipToState,
  String? shipToPincode,
  String? placeOfSupply,
  String? poNumber,
  String? poDate,
  String? vehicleNumber,
  String? ewayBillNumber,
  String? lrRrNumber,
  bool reverseCharge = false,
  String? customFieldsJson,
}) async {
  final doc = pw.Document();
  final regular = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();
  final italic = pw.Font.helveticaOblique();

  final customSettings = settings ?? InvoiceCustomizationSettings();
  final primaryColor = _parseHexColor(customSettings.primaryColorHex);
  const slateDark = PdfColor.fromInt(0xFF0F172A);
  const slateMuted = PdfColor.fromInt(0xFF475569);
  const borderGrey = PdfColor.fromInt(0xFF94A3B8);
  const lightGrey = PdfColor.fromInt(0xFFF1F5F9);

  String money(int paise) => formatPaisePdf(paise, prefixRs: true);

  // Pre-load images safely if present
  pw.MemoryImage? logoImage;
  final effectiveLogoPath = business.logoPath;
  if (effectiveLogoPath != null && effectiveLogoPath.isNotEmpty) {
    try {
      final file = File(effectiveLogoPath);
      if (file.existsSync()) {
        logoImage = pw.MemoryImage(file.readAsBytesSync());
      }
    } catch (_) {}
  }

  pw.MemoryImage? signatureImage;
  final effectiveSigPath = customSettings.signatureImagePath ?? business.signaturePath;
  if (effectiveSigPath != null && effectiveSigPath.isNotEmpty) {
    try {
      final file = File(effectiveSigPath);
      if (file.existsSync()) {
        signatureImage = pw.MemoryImage(file.readAsBytesSync());
      }
    } catch (_) {}
  }

  final isInterState = igst > 0;
  final hasShipTo = customSettings.showShipTo &&
      ((shipToName != null && shipToName.trim().isNotEmpty) ||
          (shipToAddress != null && shipToAddress.trim().isNotEmpty));

  final effectiveTitle = customSettings.customTitleOverride != null &&
          customSettings.customTitleOverride!.trim().isNotEmpty
      ? customSettings.customTitleOverride!.trim().toUpperCase()
      : (title.toLowerCase().contains('tax') || business.taxRegistered
          ? 'TAX INVOICE'
          : title.toUpperCase());

  // Aggregate HSN breakdown
  final hsnMap = <String, _GstBreakupItem>{};
  for (final l in lines) {
    final hsnCode = (l.hsn != null && l.hsn!.trim().isNotEmpty) ? l.hsn!.trim() : 'OTHER';
    final key = '${hsnCode}_${l.gstRate}';
    final item = hsnMap.putIfAbsent(key, () => _GstBreakupItem(hsn: hsnCode, gstRate: l.gstRate));
    item.taxable += l.taxable;
    if (isInterState) {
      item.igst += l.tax;
    } else {
      final halfTax = l.tax ~/ 2;
      item.cgst += halfTax;
      item.sgst += (l.tax - halfTax);
    }
  }
  final hsnBreakupList = hsnMap.values.toList();

  final upiUri = generateUpiPaymentUri(
    business: business,
    invoiceNumber: number,
    amountPaise: total,
  );

  // Compute robust table column widths and alignments based on active columns
  int colIdx = 0;
  final Map<int, pw.TableColumnWidth> tableColWidths = {};
  final Map<int, pw.Alignment> tableCellAlignments = {};

  tableColWidths[colIdx] = const pw.FixedColumnWidth(24);
  tableCellAlignments[colIdx] = pw.Alignment.center;
  colIdx++;

  tableColWidths[colIdx] = const pw.FlexColumnWidth(4.5);
  tableCellAlignments[colIdx] = pw.Alignment.centerLeft;
  colIdx++;

  if (customSettings.showHsnColumn) {
    tableColWidths[colIdx] = const pw.FixedColumnWidth(45);
    tableCellAlignments[colIdx] = pw.Alignment.center;
    colIdx++;
  }

  if (customSettings.showUnitColumn) {
    tableColWidths[colIdx] = const pw.FixedColumnWidth(45);
    tableCellAlignments[colIdx] = pw.Alignment.centerRight;
    colIdx++;
  }

  tableColWidths[colIdx] = const pw.FixedColumnWidth(48);
  tableCellAlignments[colIdx] = pw.Alignment.centerRight;
  colIdx++;

  if (customSettings.showDiscountColumn) {
    tableColWidths[colIdx] = const pw.FixedColumnWidth(38);
    tableCellAlignments[colIdx] = pw.Alignment.centerRight;
    colIdx++;
  }

  if (customSettings.showTaxColumn) {
    tableColWidths[colIdx] = const pw.FixedColumnWidth(35);
    tableCellAlignments[colIdx] = pw.Alignment.center;
    colIdx++;
  }

  tableColWidths[colIdx] = const pw.FixedColumnWidth(55);
  tableCellAlignments[colIdx] = pw.Alignment.centerRight;
  colIdx++;

  // Setup multi-page with outer bounding border per page
  final effectiveFormat = pageFormat == PdfPageFormat.a4
      ? PdfPageFormat.a4.copyWith(
          marginLeft: 18,
          marginRight: 18,
          marginTop: 18,
          marginBottom: 18,
        )
      : pageFormat;

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: effectiveFormat,
        margin: const pw.EdgeInsets.all(18),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(
            margin: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGrey, width: 0.8),
            ),
          ),
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated via Billket Enterprise System',
              style: pw.TextStyle(font: regular, fontSize: 7, color: slateMuted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(font: regular, fontSize: 7, color: slateMuted),
            ),
          ],
        ),
      ),
      build: (context) => [
        // ==========================================
        // 1. TOP HEADER & BRANDING (CLASSIC GRID)
        // ==========================================
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: borderGrey, width: 0.8),
            ),
          ),
          padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company details
              if (logoImage != null && customSettings.logoPlacement == 'left') ...[
                pw.Container(
                  width: 55,
                  height: 55,
                  margin: const pw.EdgeInsets.only(right: 10),
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ],
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      business.name.toUpperCase(),
                      style: pw.TextStyle(font: bold, fontSize: 13, color: primaryColor),
                    ),
                    if (customSettings.showAddress) ...[
                      if (business.address != null && business.address!.isNotEmpty)
                        pw.Text(
                          business.address!,
                          style: pw.TextStyle(font: regular, fontSize: 8, color: slateDark),
                        ),
                      if (business.city != null || business.state != null || business.pinCode != null)
                        pw.Text(
                          [business.city, business.state, business.pinCode].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                          style: pw.TextStyle(font: regular, fontSize: 8, color: slateDark),
                        ),
                    ],
                    if (customSettings.showGstin && business.gstin != null && business.gstin!.isNotEmpty)
                      pw.RichText(
                        text: pw.TextSpan(children: [
                          pw.TextSpan(text: 'GSTIN: ', style: pw.TextStyle(font: bold, fontSize: 8, color: slateDark)),
                          pw.TextSpan(text: business.gstin!, style: pw.TextStyle(font: bold, fontSize: 8, color: primaryColor)),
                        ]),
                      ),
                    if (customSettings.showPan && business.pan != null && business.pan!.isNotEmpty)
                      pw.Text('PAN: ${business.pan}', style: pw.TextStyle(font: regular, fontSize: 8, color: slateDark)),
                    if (customSettings.showPhone && business.displayInvoicePhone.isNotEmpty)
                      pw.Text('Phone: ${business.displayInvoicePhone}', style: pw.TextStyle(font: regular, fontSize: 8, color: slateDark)),
                    if (customSettings.showEmail && business.displayInvoiceEmail.isNotEmpty)
                      pw.Text('Email: ${business.displayInvoiceEmail}', style: pw.TextStyle(font: regular, fontSize: 8, color: slateDark)),
                  ],
                ),
              ),
              if (logoImage != null && customSettings.logoPlacement == 'center') ...[
                pw.Container(
                  width: 50,
                  height: 50,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ],
              if (logoImage != null && customSettings.logoPlacement == 'right') ...[
                pw.Container(
                  width: 50,
                  height: 50,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ],
              // Banner & Document Meta
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: lightGrey,
                        border: pw.Border.all(color: borderGrey, width: 0.6),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(
                        effectiveTitle,
                        style: pw.TextStyle(font: bold, fontSize: 10, color: primaryColor),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('Invoice No: ', style: pw.TextStyle(font: bold, fontSize: 8.5)),
                        pw.Text(number, style: pw.TextStyle(font: bold, fontSize: 8.5, color: slateDark)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('Date: ', style: pw.TextStyle(font: bold, fontSize: 8)),
                        pw.Text(displayDate(date), style: pw.TextStyle(font: regular, fontSize: 8)),
                      ],
                    ),
                    if (dueDate != null && dueDate.isNotEmpty)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text('Due Date: ', style: pw.TextStyle(font: bold, fontSize: 8)),
                          pw.Text(displayDate(dueDate), style: pw.TextStyle(font: regular, fontSize: 8)),
                        ],
                      ),
                    if (placeOfSupply != null && placeOfSupply.isNotEmpty)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text('Place of Supply: ', style: pw.TextStyle(font: bold, fontSize: 8)),
                          pw.Text(placeOfSupply, style: pw.TextStyle(font: regular, fontSize: 8)),
                        ],
                      ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('Reverse Charge: ', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                        pw.Text(reverseCharge ? 'YES' : 'NO', style: pw.TextStyle(font: bold, fontSize: 7.5, color: reverseCharge ? PdfColors.red800 : slateDark)),
                      ],
                    ),
                  ],
                ),
              ),
              if (logoImage != null && customSettings.logoPlacement == 'right') ...[
                pw.Container(
                  width: 55,
                  height: 55,
                  margin: const pw.EdgeInsets.only(left: 10),
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ],
            ],
          ),
        ),

        // ==========================================
        // 2. PARTIES GRID (BILL TO & SHIP TO)
        // ==========================================
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: borderGrey, width: 0.8),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // BILL TO
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: hasShipTo
                        ? const pw.Border(right: pw.BorderSide(color: borderGrey, width: 0.8))
                        : null,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BILL TO:',
                        style: pw.TextStyle(font: bold, fontSize: 8, color: primaryColor),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        (partyName != null && partyName.trim().isNotEmpty) ? partyName.trim() : 'Cash / Walk-in Customer',
                        style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark),
                      ),
                      if (partyAddress != null && partyAddress.trim().isNotEmpty)
                        pw.Text(partyAddress.trim(), style: pw.TextStyle(font: regular, fontSize: 8)),
                      if (partyState != null && partyState.trim().isNotEmpty)
                        pw.Text('State: $partyState', style: pw.TextStyle(font: regular, fontSize: 8)),
                      if (partyGstin != null && partyGstin.trim().isNotEmpty)
                        pw.RichText(
                          text: pw.TextSpan(children: [
                            pw.TextSpan(text: 'GSTIN: ', style: pw.TextStyle(font: bold, fontSize: 8)),
                            pw.TextSpan(text: partyGstin.trim(), style: pw.TextStyle(font: bold, fontSize: 8, color: primaryColor)),
                          ]),
                        ),
                      if (customSettings.showPan && customer?.pan != null && customer!.pan!.isNotEmpty)
                        pw.Text('PAN: ${customer.pan}', style: pw.TextStyle(font: regular, fontSize: 8)),
                      if (customSettings.showPhone && partyPhone != null && partyPhone.trim().isNotEmpty)
                        pw.Text('Contact: ${partyPhone.trim()}', style: pw.TextStyle(font: regular, fontSize: 8)),
                    ],
                  ),
                ),
              ),
              // SHIP TO
              if (hasShipTo) ...[
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SHIP TO:',
                          style: pw.TextStyle(font: bold, fontSize: 8, color: primaryColor),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          (shipToName != null && shipToName.trim().isNotEmpty) ? shipToName.trim() : (partyName ?? ''),
                          style: pw.TextStyle(font: bold, fontSize: 9, color: slateDark),
                        ),
                        if (shipToAddress != null && shipToAddress.trim().isNotEmpty)
                          pw.Text(shipToAddress.trim(), style: pw.TextStyle(font: regular, fontSize: 8)),
                        if (shipToState != null || shipToPincode != null)
                          pw.Text(
                            [
                              if (shipToState != null && shipToState.trim().isNotEmpty) 'State: ${shipToState.trim()}',
                              if (shipToPincode != null && shipToPincode.trim().isNotEmpty) 'PIN: ${shipToPincode.trim()}',
                            ].join(' | '),
                            style: pw.TextStyle(font: regular, fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ==========================================
        // 3. TRANSPORT & STATUTORY STRIP (CONDITIONAL)
        // ==========================================
        if ((vehicleNumber != null && vehicleNumber.trim().isNotEmpty) ||
            (ewayBillNumber != null && ewayBillNumber.trim().isNotEmpty) ||
            (poNumber != null && poNumber.trim().isNotEmpty) ||
            (lrRrNumber != null && lrRrNumber.trim().isNotEmpty)) ...[
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: lightGrey,
              border: pw.Border(
                bottom: pw.BorderSide(color: borderGrey, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (vehicleNumber != null && vehicleNumber.trim().isNotEmpty)
                  pw.Text('Vehicle No: ${vehicleNumber.trim().toUpperCase()}', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                if (ewayBillNumber != null && ewayBillNumber.trim().isNotEmpty)
                  pw.Text('E-Way Bill: ${ewayBillNumber.trim()}', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                if (lrRrNumber != null && lrRrNumber.trim().isNotEmpty)
                  pw.Text('LR/Transport No: ${lrRrNumber.trim()}', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                if (poNumber != null && poNumber.trim().isNotEmpty)
                  pw.Text('PO No: ${poNumber.trim()}${poDate != null && poDate.isNotEmpty ? " (${displayDate(poDate)})" : ""}', style: pw.TextStyle(font: regular, fontSize: 7.5)),
              ],
            ),
          ),
        ],

        // ==========================================
        // 4. LINE ITEMS TABLE (MULTI-PAGE CAPABLE)
        // ==========================================
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: borderGrey, width: 0.5),
          headerDecoration: const pw.BoxDecoration(color: lightGrey),
          headerHeight: 22,
          headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: slateDark),
          cellStyle: pw.TextStyle(font: regular, fontSize: 8, color: slateDark),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          headers: [
            'S.N.',
            'Items & Description',
            if (customSettings.showHsnColumn) 'HSN/SAC',
            if (customSettings.showUnitColumn) 'Qty',
            'Rate',
            if (customSettings.showDiscountColumn) 'Disc',
            if (customSettings.showTaxColumn) 'Tax %',
            'Amount',
          ],
          columnWidths: tableColWidths,
          cellAlignments: tableCellAlignments,
          data: List<List<String>>.generate(lines.length, (i) {
            final line = lines[i];
            final qtyStr = _qty(line.quantity);
            final unitSuffix = (line.unit != null && line.unit!.trim().isNotEmpty) ? ' ${line.unit!.trim()}' : '';
            return [
              '${i + 1}',
              line.name +
                  (line.batchNumber != null && line.batchNumber!.isNotEmpty ? ' (B: ${line.batchNumber})' : '') +
                  (line.serialNumber != null && line.serialNumber!.isNotEmpty ? ' (S: ${line.serialNumber})' : ''),
              if (customSettings.showHsnColumn) line.hsn ?? '-',
              if (customSettings.showUnitColumn) '$qtyStr$unitSuffix',
              money(line.price),
              if (customSettings.showDiscountColumn)
                line.discountPercent > 0
                    ? '${_qty(line.discountPercent)}%'
                    : (line.discount > 0 ? money(line.discount) : '-'),
              if (customSettings.showTaxColumn) '${line.gstRate}%',
              money(line.taxable + line.tax),
            ];
          }),
        ),

        // ==========================================
        // 5. BOTTOM SUMMARY & SETTLEMENT SPLIT
        // ==========================================
        () {
          pw.Widget buildBankAndQrWidget() {
            final hasBank = customSettings.showBankDetails && bankAccount != null;
            final hasQr = customSettings.showUpiQr;
            if (!hasBank && !hasQr) return pw.SizedBox();

            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (hasBank)
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BANK DETAILS:', style: pw.TextStyle(font: bold, fontSize: 7.5, color: primaryColor)),
                        pw.SizedBox(height: 2),
                        pw.Text('Bank: ${bankAccount.bankName}', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                        pw.Text('A/C Name: ${bankAccount.accountName ?? business.name}', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                        pw.Text('A/C No: ${bankAccount.accountNumber}', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                        if (bankAccount.ifsc != null && bankAccount.ifsc!.isNotEmpty)
                          pw.Text('IFSC: ${bankAccount.ifsc}', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                      ],
                    ),
                  ),
                if (hasQr)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(left: 6),
                    child: pw.Column(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: upiUri,
                          width: 58,
                          height: 58,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('Scan & Pay via UPI', style: pw.TextStyle(font: bold, fontSize: 6.5, color: primaryColor)),
                      ],
                    ),
                  ),
              ],
            );
          }

          pw.Widget buildTermsWidget() {
            final showT = customSettings.showTerms && termsText != null && termsText.trim().isNotEmpty;
            final showD = customSettings.showDeclaration && customSettings.declarationText.trim().isNotEmpty;
            if (!showT && !showD) return pw.SizedBox();

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (showT) ...[
                  pw.Text('Terms & Conditions:', style: pw.TextStyle(font: bold, fontSize: 7, color: slateMuted)),
                  pw.Text(termsText.trim(), style: pw.TextStyle(font: regular, fontSize: 6.5, color: slateMuted)),
                  if (showD) pw.SizedBox(height: 4),
                ],
                if (showD) ...[
                  pw.Text('Declaration:', style: pw.TextStyle(font: bold, fontSize: 7, color: slateMuted)),
                  pw.Text(customSettings.declarationText.trim(), style: pw.TextStyle(font: regular, fontSize: 6.5, color: slateMuted)),
                ],
              ],
            );
          }

          final calcColumn = pw.Column(
            children: [
              _calcRow('Sub Total / Taxable', money(taxable), regular, slateDark),
              if (discount > 0)
                _calcRow('Total Discount', '- ${money(discount)}', regular, PdfColors.green800),
              if (!isInterState) ...[
                _calcRow('CGST', money(cgst), regular, slateDark),
                _calcRow('SGST', money(sgst), regular, slateDark),
              ] else ...[
                _calcRow('IGST', money(igst), regular, slateDark),
              ],
              if (roundOff != 0)
                _calcRow('Round Off', (roundOff > 0 ? '+ ' : '') + money(roundOff), regular, slateMuted),
              pw.Divider(color: borderGrey, thickness: 0.5),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: const pw.BoxDecoration(
                  color: lightGrey,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Amount', style: pw.TextStyle(font: bold, fontSize: 10, color: primaryColor)),
                    pw.Text(money(total), style: pw.TextStyle(font: bold, fontSize: 10, color: primaryColor)),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              _calcRow('Received Amount', money(total - outstandingPaise), regular, PdfColors.green800),
              if (outstandingPaise > 0)
                _calcRow('Balance Due', money(outstandingPaise), bold, PdfColors.red800),
            ],
          );

          final amountInWordsWidget = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Total Amount in Words:',
                style: pw.TextStyle(font: bold, fontSize: 7.5, color: slateDark),
              ),
              pw.Text(
                _amountInWords(total),
                style: pw.TextStyle(font: italic, fontSize: 8, color: primaryColor),
              ),
            ],
          );

          return pw.Column(
            children: [
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: borderGrey, width: 0.8),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // LEFT CONTAINER
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            right: pw.BorderSide(color: borderGrey, width: 0.8),
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (customSettings.bankQrPlacement == 'left') ...[
                              buildBankAndQrWidget(),
                              pw.SizedBox(height: 6),
                            ],
                            amountInWordsWidget,
                            pw.SizedBox(height: 6),
                            buildTermsWidget(),
                          ],
                        ),
                      ),
                    ),

                    // RIGHT CONTAINER
                    pw.Expanded(
                      flex: 2,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          children: [
                            calcColumn,
                            if (customSettings.bankQrPlacement == 'right') ...[
                              pw.Divider(color: borderGrey, thickness: 0.5),
                              buildBankAndQrWidget(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (customSettings.bankQrPlacement == 'bottom' && (customSettings.showBankDetails || customSettings.showUpiQr)) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: borderGrey, width: 0.8),
                    ),
                  ),
                  child: buildBankAndQrWidget(),
                ),
              ],
            ],
          );
        }(),

        // ==========================================
        // 6. HSN/SAC TAX BREAKDOWN TABLE (STATUTORY)
        // ==========================================
        if (customSettings.showHsnSummaryTable && hsnBreakupList.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text('HSN/SAC TAX SUMMARY MATRIX', style: pw.TextStyle(font: bold, fontSize: 7.5, color: slateMuted)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: borderGrey, width: 0.5),
            headerDecoration: const pw.BoxDecoration(color: lightGrey),
            headerHeight: 18,
            headerStyle: pw.TextStyle(font: bold, fontSize: 7, color: slateDark),
            cellStyle: pw.TextStyle(font: regular, fontSize: 7),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            headers: [
              'HSN/SAC',
              'Taxable Value',
              if (!isInterState) 'CGST Rate',
              if (!isInterState) 'CGST Amt',
              if (!isInterState) 'SGST Rate',
              if (!isInterState) 'SGST Amt',
              if (isInterState) 'IGST Rate',
              if (isInterState) 'IGST Amt',
              'Total Tax',
            ],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              if (!isInterState) 2: pw.Alignment.center,
              if (!isInterState) 3: pw.Alignment.centerRight,
              if (!isInterState) 4: pw.Alignment.center,
              if (!isInterState) 5: pw.Alignment.centerRight,
              if (isInterState) 2: pw.Alignment.center,
              if (isInterState) 3: pw.Alignment.centerRight,
              if (!isInterState) 6: pw.Alignment.centerRight,
              if (isInterState) 4: pw.Alignment.centerRight,
            },
            data: hsnBreakupList.map((h) => [
              h.hsn,
              money(h.taxable),
              if (!isInterState) '${(h.gstRate / 2).toStringAsFixed(1)}%',
              if (!isInterState) money(h.cgst),
              if (!isInterState) '${(h.gstRate / 2).toStringAsFixed(1)}%',
              if (!isInterState) money(h.sgst),
              if (isInterState) '${h.gstRate}%',
              if (isInterState) money(h.igst),
              money(h.totalTax),
            ]).toList(),
          ),
        ],

        // ==========================================
        // 7. AUTHORISED SIGNATORY BLOCK
        // ==========================================
        if (customSettings.showSignatureBox) ...[
          pw.SizedBox(height: 8),
          () {
            final sigBox = pw.Container(
              width: 170,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('For ${business.name.toUpperCase()}', style: pw.TextStyle(font: bold, fontSize: 8)),
                  pw.SizedBox(height: 6),
                  if (signatureImage != null)
                    pw.Container(
                      height: 38,
                      child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.Container(
                      height: 30,
                      margin: const pw.EdgeInsets.symmetric(vertical: 4),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: borderGrey, width: 0.8)),
                      ),
                    ),
                  pw.Text(business.signatureText, style: pw.TextStyle(font: regular, fontSize: 7.5)),
                ],
              ),
            );

            final hasNotes = notes != null && notes.trim().isNotEmpty;
            final notesBox = hasNotes
                ? pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Special Notes:', style: pw.TextStyle(font: bold, fontSize: 7)),
                        pw.Text(notes.trim(), style: pw.TextStyle(font: regular, fontSize: 7, color: slateMuted)),
                      ],
                    ),
                  )
                : null;

            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: customSettings.signaturePlacement == 'left'
                  ? [
                      sigBox,
                      notesBox ?? pw.Spacer(),
                    ]
                  : [
                      notesBox ?? pw.Spacer(),
                      sigBox,
                    ],
            );
          }(),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _calcRow(String label, String value, pw.Font font, PdfColor color) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7.5, color: color)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: 7.5, color: color)),
      ],
    ),
  );
}

/// Builds thermal receipt format for portable POS printers.
Future<Uint8List> buildThermalReceiptPdf({
  required Business business,
  required String title,
  required String number,
  required String date,
  String? dueDate,
  String? partyName,
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
  InvoicePaperSize paperSize = InvoicePaperSize.roll80mm,
}) async {
  final doc = pw.Document();
  final mono = pw.Font.courier();
  final monoBold = pw.Font.courierBold();
  final is58 = paperSize == InvoicePaperSize.roll58mm;
  final fontSize = is58 ? 7.5 : 8.5;
  final titleSize = is58 ? 10.5 : 12.0;

  String money(int paise) => formatPaisePdf(paise, prefixRs: true);

  doc.addPage(
    pw.Page(
      pageFormat: paperSize.format,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              business.name.toUpperCase(),
              style: pw.TextStyle(font: monoBold, fontSize: titleSize),
              textAlign: pw.TextAlign.center,
            ),
          ),
          if (business.address != null && business.address!.isNotEmpty)
            pw.Center(
              child: pw.Text(
                business.address!,
                style: pw.TextStyle(font: mono, fontSize: fontSize - 1),
                textAlign: pw.TextAlign.center,
              ),
            ),
          if (business.gstin != null && business.gstin!.isNotEmpty)
            pw.Center(
              child: pw.Text(
                'GSTIN: ${business.gstin!}',
                style: pw.TextStyle(font: mono, fontSize: fontSize - 0.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
          pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Bill: $number', style: pw.TextStyle(font: monoBold, fontSize: fontSize)),
              pw.Text(displayDate(date), style: pw.TextStyle(font: mono, fontSize: fontSize)),
            ],
          ),
          if (partyName != null && partyName.isNotEmpty)
            pw.Text('Party: $partyName', style: pw.TextStyle(font: mono, fontSize: fontSize)),
          pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
          ...lines.map(
            (l) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(l.name, style: pw.TextStyle(font: monoBold, fontSize: fontSize)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${_qty(l.quantity)} × ${money(l.price)}',
                        style: pw.TextStyle(font: mono, fontSize: fontSize - 0.5),
                      ),
                      pw.Text(money(l.taxable + l.tax), style: pw.TextStyle(font: monoBold, fontSize: fontSize)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Taxable', style: pw.TextStyle(font: mono, fontSize: fontSize)),
              pw.Text(money(taxable), style: pw.TextStyle(font: mono, fontSize: fontSize)),
            ],
          ),
          if (cgst > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('CGST', style: pw.TextStyle(font: mono, fontSize: fontSize)),
                pw.Text(money(cgst), style: pw.TextStyle(font: mono, fontSize: fontSize)),
              ],
            ),
          if (sgst > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('SGST', style: pw.TextStyle(font: mono, fontSize: fontSize)),
                pw.Text(money(sgst), style: pw.TextStyle(font: mono, fontSize: fontSize)),
              ],
            ),
          if (igst > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('IGST', style: pw.TextStyle(font: mono, fontSize: fontSize)),
                pw.Text(money(igst), style: pw.TextStyle(font: mono, fontSize: fontSize)),
              ],
            ),
          pw.Divider(thickness: 1),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL', style: pw.TextStyle(font: monoBold, fontSize: fontSize + 2)),
              pw.Text(money(total), style: pw.TextStyle(font: monoBold, fontSize: fontSize + 2)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'Thank You! Visit Again.',
              style: pw.TextStyle(font: mono, fontSize: fontSize),
            ),
          ),
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
  InvoiceCustomizationSettings? settings,
}) async {
  customer ??= (invoice.customerId != null && business.id != null)
      ? await Repository.instance.customer(business.id!, invoice.customerId!)
      : null;

  bankAccount ??= (business.bankAccountId != null)
      ? await Repository.instance.getBankAccount(business.bankAccountId!)
      : (business.id != null
          ? (await Repository.instance.bankAccounts(business.id!)).where((b) => !b.inactive).firstOrNull
          : null);

  settings ??= business.id != null
      ? await Repository.instance.getInvoiceCustomizationSettings(business.id!)
      : null;

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
    termsText: (invoice.notes != null && invoice.notes!.trim().isNotEmpty)
        ? invoice.notes
        : (business.termsSales != null && business.termsSales!.trim().isNotEmpty
            ? business.termsSales
            : null),
    bankAccount: bankAccount,
    pageFormat: paperSize.format,
    settings: settings,
    shipToName: invoice.shipToName,
    shipToAddress: invoice.shipToAddress,
    shipToState: invoice.shipToState,
    shipToPincode: invoice.shipToPincode,
    placeOfSupply: invoice.placeOfSupply,
    poNumber: invoice.poNumber,
    poDate: invoice.poDate,
    vehicleNumber: invoice.vehicleNumber,
    ewayBillNumber: invoice.ewayBillNumber,
    lrRrNumber: invoice.lrRrNumber,
    reverseCharge: invoice.reverseCharge,
    customFieldsJson: invoice.customFieldsJson,
  );
}

Future<void> printInvoice({
  required Business business,
  required Invoice invoice,
  Customer? customer,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  final bytes = await buildInvoicePdf(
    business: business,
    invoice: invoice,
    customer: customer,
    paperSize: paperSize,
  );
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${invoice.number}.pdf',
  );
}

Future<void> shareInvoice({
  required Business business,
  required Invoice invoice,
  Customer? customer,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  final bytes = await buildInvoicePdf(
    business: business,
    invoice: invoice,
    customer: customer,
    paperSize: paperSize,
  );
  await Printing.sharePdf(bytes: bytes, filename: '${invoice.number}.pdf');
}

/// Generates the canonical commercial sample invoice PDF used for live previews across settings and customization.
Future<Uint8List> generateCommercialSamplePdf({
  required Business business,
  InvoiceCustomizationSettings? settings,
  BankAccount? bankAccount,
}) async {
  final currentSettings = settings ??
      (business.id != null
          ? await Repository.instance.getInvoiceCustomizationSettings(business.id!)
          : InvoiceCustomizationSettings());

  bankAccount ??= (business.bankAccountId != null)
      ? await Repository.instance.getBankAccount(business.bankAccountId!)
      : (business.id != null
          ? (await Repository.instance.bankAccounts(business.id!)).where((b) => !b.inactive).firstOrNull
          : null);

  final sampleLines = [
    InvoiceLine(
      name: 'Premium Ceramic Floor Tiles 600x600',
      hsn: '6907',
      gstRate: 18,
      quantity: 120,
      price: 45000,
      taxable: 4576300,
      tax: 823700,
      unit: 'BOX',
      discount: 250000,
      discountPercent: 5.0,
    ),
    InvoiceLine(
      name: 'Epoxy Grout Adhesive (5 KG)',
      hsn: '3214',
      gstRate: 18,
      quantity: 15,
      price: 65000,
      taxable: 826200,
      tax: 148800,
      unit: 'PAC',
    ),
    InvoiceLine(
      name: 'Waterproof Acrylic Sealer (10 LTR)',
      hsn: '3824',
      gstRate: 18,
      quantity: 5,
      price: 180000,
      taxable: 762700,
      tax: 137300,
      unit: 'CAN',
    ),
  ];

  final effectiveTitle = (currentSettings.customTitleOverride != null && currentSettings.customTitleOverride!.trim().isNotEmpty)
      ? currentSettings.customTitleOverride!.trim()
      : 'TAX INVOICE';

  final effectiveTerms = (business.termsSales != null && business.termsSales!.trim().isNotEmpty)
      ? business.termsSales
      : currentSettings.declarationText;

  return buildDocumentPdf(
    business: business,
    title: effectiveTitle,
    number: '${business.invoicePrefix.isNotEmpty ? business.invoicePrefix : "INV"}-2026-0042',
    date: DateTime.now().toIso8601String().substring(0, 10),
    dueDate: DateTime.now().add(const Duration(days: 15)).toIso8601String().substring(0, 10),
    partyName: 'Balaji Enterprises Pvt Ltd',
    partyAddress: 'Plot 45, Industrial Growth Centre, Phase II',
    partyGstin: '16GPZPD6335F1ZH',
    partyState: 'Tripura',
    partyPhone: '+91 98765 43210',
    lines: sampleLines,
    subtotal: 7300000,
    discount: 250000,
    taxable: 6165200,
    igst: 0,
    cgst: 554900,
    sgst: 554900,
    roundOff: 0,
    total: 7275000,
    outstandingPaise: 2275000,
    notes: 'Payment due within 15 days of invoice date.',
    termsText: effectiveTerms,
    bankAccount: bankAccount,
    settings: currentSettings,
    shipToName: currentSettings.showShipTo ? 'Balaji Logistics Hub - Warehouse 3' : null,
    shipToAddress: currentSettings.showShipTo ? 'NH-44 Bypass Road, Bodhjungnagar' : null,
    shipToState: currentSettings.showShipTo ? 'Tripura' : null,
    shipToPincode: currentSettings.showShipTo ? '799008' : null,
    placeOfSupply: 'Tripura',
    vehicleNumber: currentSettings.showVehicleDetails ? 'TR 01 AA 2026' : null,
    ewayBillNumber: currentSettings.showVehicleDetails ? '241829038472' : null,
    poNumber: currentSettings.showPoDetails ? 'PO-98421' : null,
    poDate: currentSettings.showPoDetails ? DateTime.now().toIso8601String().substring(0, 10) : null,
  );
}

/// Interactive dialog for previewing invoices across screens
Future<void> showInvoicePreviewModal(
  BuildContext context, {
  required Business business,
  InvoiceCustomizationSettings? settings,
  BankAccount? bankAccount,
  Future<Uint8List> Function()? pdfBuilder,
  String title = 'Invoice Preview',
}) {
  final Future<Uint8List> Function() effectiveBuilder = pdfBuilder ??
      () => generateCommercialSamplePdf(
            business: business,
            settings: settings,
            bankAccount: bankAccount,
          );

  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(ctx),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print',
              onPressed: () async {
                final bytes = await effectiveBuilder();
                await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$title.pdf');
              },
            ),
          ],
        ),
        body: PdfPreview(
          build: (format) => effectiveBuilder(),
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          previewPageMargin: const EdgeInsets.all(8),
        ),
      ),
    ),
  );
}

Future<Uint8List> buildQuotationPdf({
  required Business business,
  required Quotation quotation,
  Customer? customer,
  BankAccount? bankAccount,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  customer ??= (quotation.customerId != null && business.id != null)
      ? await Repository.instance.customer(business.id!, quotation.customerId!)
      : null;

  return buildDocumentPdf(
    business: business,
    title: quotation.isProforma ? 'Proforma Invoice' : 'Quotation',
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
    pageFormat: paperSize.format,
  );
}

Future<void> printQuotation({
  required Business business,
  required Quotation quotation,
  Customer? customer,
}) async {
  final bytes = await buildQuotationPdf(business: business, quotation: quotation, customer: customer);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${quotation.number}.pdf',
  );
}

Future<void> shareQuotation({
  required Business business,
  required Quotation quotation,
  Customer? customer,
}) async {
  final bytes = await buildQuotationPdf(business: business, quotation: quotation, customer: customer);
  await Printing.sharePdf(bytes: bytes, filename: '${quotation.number}.pdf');
}

Future<Uint8List> buildReturnPdf({
  required Business business,
  required TransactionReturn returnInvoice,
  Customer? customer,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  customer ??= (returnInvoice.partyId != null && business.id != null && returnInvoice.partyType == 'customer')
      ? await Repository.instance.customer(business.id!, returnInvoice.partyId!)
      : null;

  return buildDocumentPdf(
    business: business,
    title: 'Credit Note / Sales Return',
    number: returnInvoice.number,
    date: returnInvoice.date,
    customer: customer,
    partyName: returnInvoice.partyName,
    lines: returnInvoice.lines,
    subtotal: returnInvoice.subtotal,
    discount: 0,
    taxable: returnInvoice.taxable,
    igst: 0,
    cgst: returnInvoice.tax ~/ 2,
    sgst: returnInvoice.tax - (returnInvoice.tax ~/ 2),
    roundOff: 0,
    total: returnInvoice.total,
    outstandingPaise: returnInvoice.total,
    notes: returnInvoice.reason,
    pageFormat: paperSize.format,
  );
}

Future<void> printReturn({
  required Business business,
  required TransactionReturn returnInvoice,
}) async {
  final bytes = await buildReturnPdf(business: business, returnInvoice: returnInvoice);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${returnInvoice.number}.pdf',
  );
}

Future<void> shareReturn({
  required Business business,
  required TransactionReturn returnInvoice,
}) async {
  final bytes = await buildReturnPdf(business: business, returnInvoice: returnInvoice);
  await Printing.sharePdf(bytes: bytes, filename: '${returnInvoice.number}.pdf');
}

Future<Uint8List> buildSalesOrderPdf({
  required Business business,
  required SalesOrder order,
  Customer? customer,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  customer ??= (order.customerId != null && business.id != null)
      ? await Repository.instance.customer(business.id!, order.customerId!)
      : null;

  int subtotal = 0;
  int taxable = 0;
  int tax = 0;
  for (final l in order.lines) {
    subtotal += l.price * l.quantity.round();
    taxable += l.taxable;
    tax += l.tax;
  }

  return buildDocumentPdf(
    business: business,
    title: 'Sales Order',
    number: order.number,
    date: order.date,
    dueDate: order.dueDate,
    customer: customer,
    partyName: order.customerName,
    lines: order.lines,
    subtotal: subtotal,
    discount: 0,
    taxable: taxable,
    igst: 0,
    cgst: tax ~/ 2,
    sgst: tax - (tax ~/ 2),
    roundOff: 0,
    total: order.total,
    outstandingPaise: order.total,
    notes: order.notes,
    pageFormat: paperSize.format,
  );
}

Future<void> printSalesOrder({
  required Business business,
  required SalesOrder order,
}) async {
  final bytes = await buildSalesOrderPdf(business: business, order: order);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${order.number}.pdf',
  );
}

Future<void> shareSalesOrder({
  required Business business,
  required SalesOrder order,
}) async {
  final bytes = await buildSalesOrderPdf(business: business, order: order);
  await Printing.sharePdf(bytes: bytes, filename: '${order.number}.pdf');
}

Future<Uint8List> buildPurchaseOrderPdf({
  required Business business,
  required PurchaseOrder order,
  InvoicePaperSize paperSize = InvoicePaperSize.a4,
}) async {
  int subtotal = 0;
  int taxable = 0;
  int tax = 0;
  for (final l in order.lines) {
    subtotal += l.price * l.quantity.round();
    taxable += l.taxable;
    tax += l.tax;
  }

  return buildDocumentPdf(
    business: business,
    title: 'Purchase Order',
    number: order.number,
    date: order.date,
    dueDate: order.expectedDate,
    partyName: order.supplierName,
    lines: order.lines,
    subtotal: subtotal,
    discount: 0,
    taxable: taxable,
    igst: 0,
    cgst: tax ~/ 2,
    sgst: tax - (tax ~/ 2),
    roundOff: 0,
    total: order.total,
    outstandingPaise: order.total,
    notes: order.notes,
    termsText: business.termsPurchase,
    pageFormat: paperSize.format,
  );
}

Future<void> printPurchaseOrder({
  required Business business,
  required PurchaseOrder order,
}) async {
  final bytes = await buildPurchaseOrderPdf(business: business, order: order);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${order.number}.pdf',
  );
}

Future<void> sharePurchaseOrder({
  required Business business,
  required PurchaseOrder order,
}) async {
  final bytes = await buildPurchaseOrderPdf(business: business, order: order);
  await Printing.sharePdf(bytes: bytes, filename: '${order.number}.pdf');
}

String _qty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

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