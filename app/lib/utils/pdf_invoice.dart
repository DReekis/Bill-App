import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../core/money.dart';

Future<Uint8List> buildDocumentPdf({
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
}) async {
  final doc = pw.Document();
  final mono = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();
  const navy = PdfColor.fromInt(0xFF2E3192);

  String money(int paise) => formatPaise(paise).replaceAll('₹', 'Rs.');

  pw.Widget header() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(business.name,
                  style: pw.TextStyle(font: bold, fontSize: 18, color: navy)),
              pw.SizedBox(height: 3),
              if (business.gstin != null && business.gstin!.isNotEmpty)
                pw.Text('GSTIN: ${business.gstin!}',
                    style: pw.TextStyle(font: mono, fontSize: 9)),
              if (business.state != null && business.state!.isNotEmpty)
                pw.Text(business.state!,
                    style: pw.TextStyle(font: mono, fontSize: 9)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(title.toUpperCase(),
                  style: pw.TextStyle(font: bold, fontSize: 20, color: navy)),
              pw.SizedBox(height: 2),
              pw.Text(number, style: pw.TextStyle(font: mono, fontSize: 11)),
            ],
          ),
        ],
      );

  pw.Widget partySection() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Billed to',
                  style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(partyName ?? 'Walk-in customer',
                  style: pw.TextStyle(font: bold, fontSize: 11)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Date: ${displayDate(date)}',
                  style: pw.TextStyle(font: mono, fontSize: 9)),
              if (dueDate != null)
                pw.Text('Due date: ${displayDate(dueDate)}',
                    style: pw.TextStyle(font: mono, fontSize: 9)),
            ],
          ),
        ],
      );

  pw.Widget itemsTable() {
    final headers = ['#', 'Item', 'HSN', 'Qty', 'Price', 'Disc.', 'Taxable', 'GST', 'Tax'];
    final data = <List<String>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      data.add([
        '${i + 1}',
        l.name,
        l.hsn ?? '',
        _qty(l.quantity),
        money(l.price),
        _qty(l.discountPercent) == '0' ? '-' : '${_qty(l.discountPercent)}%',
        money(l.taxable),
        '${l.gstRate}%',
        money(l.tax),
      ]);
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: navy),
      cellStyle: pw.TextStyle(font: mono, fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  pw.Widget totals() {
    pw.Widget row(String label, String value, {bool boldRow = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(label,
                style: pw.TextStyle(font: boldRow ? bold : mono, fontSize: boldRow ? 11 : 9)),
            pw.Text(value,
                style: pw.TextStyle(
                    font: boldRow ? bold : mono,
                    fontSize: boldRow ? 11 : 9,
                    color: boldRow ? navy : null)),
          ]),
        );
    final rows = <pw.Widget>[
      row('Subtotal', money(subtotal)),
      if (discount > 0) row('Discount', '-${money(discount)}'),
      row('Taxable value', money(taxable)),
      if (igst > 0)
        row('IGST', money(igst))
      else ...[
        if (cgst > 0) row('CGST', money(cgst)),
        if (sgst > 0) row('SGST', money(sgst)),
      ],
      if (roundOff != 0)
        row('Round off', '${roundOff > 0 ? '+' : '-'}${money(roundOff.abs())}'),
      pw.Divider(thickness: 0.7),
      row('TOTAL', money(total), boldRow: true),
    ];
    return pw.Container(
      width: 230,
      margin: const pw.EdgeInsets.only(top: 12, left: 20),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows),
    );
  }

  doc.addPage(pw.MultiPage(
    pageTheme: const pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(32),
    ),
    header: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      header(),
      pw.SizedBox(height: 18),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF5F6FF),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: partySection(),
      ),
      pw.SizedBox(height: 14),
    ]),
    footer: (context) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Raised using PricePilot Bill', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey600)),
      pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (context) => [
      itemsTable(),
      totals(),
      pw.SizedBox(height: 20),
      if (notes != null && notes!.isNotEmpty)
        pw.Text('Note: $notes',
            style: pw.TextStyle(font: mono, fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 24),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Authorised Signatory\n\n\n\n${business.ownerName ?? business.name}',
            style: pw.TextStyle(font: mono, fontSize: 9)),
        pw.Padding(
          padding: const pw.EdgeInsets.only(right: 40),
          child: pw.Column(children: [
            pw.Text('Amount due: ${money(outstandingPaise)}',
                style: pw.TextStyle(font: bold, fontSize: 11, color: navy)),
            pw.SizedBox(height: 2),
            pw.Text('in words: ${_amountInWords(outstandingPaise)}',
                style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey600)),
          ]),
        ),
      ]),
    ],
  ));

  return doc.save();
}

Future<Uint8List> buildInvoicePdf({
  required Business business,
  required Invoice invoice,
}) => buildDocumentPdf(
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
);

Future<Uint8List> buildQuotationPdf({
  required Business business,
  required Quotation quotation,
}) => buildDocumentPdf(
  business: business,
  title: 'Estimate',
  number: quotation.number,
  date: quotation.date,
  expiryDate: quotation.expiryDate, // Map dueDate to expiryDate in buildDocumentPdf
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
);

Future<Uint8List> buildReturnPdf({
  required Business business,
  required TransactionReturn ret,
}) => buildDocumentPdf(
  business: business,
  title: ret.partyType == 'customer' ? 'Credit Note' : 'Debit Note',
  number: ret.number,
  date: ret.date,
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
);

Future<void> printInvoice({
  required Business business,
  required Invoice invoice,
}) async {
  final bytes = await buildInvoicePdf(business: business, invoice: invoice);
  await Printing.layoutPdf(onLayout: (_) async => bytes,
      name: '${invoice.number}.pdf');
}

Future<void> shareInvoice({
  required Business business,
  required Invoice invoice,
}) async {
  final bytes = await buildInvoicePdf(business: business, invoice: invoice);
  await Printing.sharePdf(bytes: bytes, filename: '${invoice.number}.pdf');
}

String _qty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(3);

String _amountInWords(int paise) {
  final negative = paise < 0;
  final rupees = paise.abs() ~/ 100;
  if (rupees == 0) return 'Zero Rupees';
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
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
  final text = words.join(' ');
  final body = text.endsWith(' ') ? '${text.trim()} Rupees only' : '$text Rupees only';
  return negative ? 'Minus $body' : body;
}