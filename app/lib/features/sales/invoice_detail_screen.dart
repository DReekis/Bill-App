import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../../utils/widgets.dart';
import '../payments/payment_form.dart';
import 'sales_return_form.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final int invoiceId;
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Invoice? invoice;
  Business? business;
  bool busy = false;

  Future<void> _load() async {
    final session = context.read<Session>();
    final repo = Repository.instance;
    if (session.businessId == null) return;
    final inv = await repo.invoice(session.businessId!, widget.invoiceId);
    final biz = await repo.getBusiness(session.businessId!);
    if (!mounted) return;
    setState(() {
      invoice = inv;
      business = biz;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _share() async {
    final inv = invoice;
    final biz = business;
    if (inv == null || biz == null) return;
    setState(() => busy = true);
    try {
      await shareInvoice(business: biz, invoice: inv);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _print() async {
    final inv = invoice;
    final biz = business;
    if (inv == null || biz == null) return;
    setState(() => busy = true);
    try {
      await printInvoice(business: biz, invoice: inv);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _receivePayment() {
    final inv = invoice;
    if (inv == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PaymentFormScreen(partyType: 'customer', partyId: inv.customerId),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final biz = business;
    final outstanding = inv?.outstanding.paise ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv?.number ?? 'Invoice'),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _share,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: inv == null || biz == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(biz.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        if (biz.gstin?.isNotEmpty == true)
                          Text('GSTIN ${biz.gstin}', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      ]),
                    ),
                    StitchStatusChip(inv.status),
                  ]),
                  const Divider(height: 22),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Bill to', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                        const SizedBox(height: 3),
                        Text(inv.customerName ?? 'Walk-in customer', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Date: ${displayDate(inv.date)}', style: const TextStyle(fontSize: 12)),
                      if (inv.dueDate != null)
                        Text('Due: ${displayDate(inv.dueDate)}', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                    ]),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              if (inv.lines.isNotEmpty) ...[
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ...inv.lines.map(
                    (l) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(l.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('${_qty(l.quantity)} × ${formatPaise(l.price)}  ${l.gstRate > 0 ? '· GST ${l.gstRate}%' : ''}',
                                        style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  MoneyText(l.taxable + l.tax, fontSize: 12.5),
                                  if (l.discountPercent > 0)
                                    Text('${_qty(l.discountPercent)}% off', style: const TextStyle(fontSize: 10.5, color: StitchColors.success)),
                                ]),
                              ]),
                            )),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: _totalsList(inv),
                    ),
                  ]),
                ),
              ] else
                const AppEmptyState(icon: Icons.receipt_outlined, title: 'No line items'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _print,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Share PDF'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: StitchColors.error),
                  onPressed: () {
                    final inv = invoice;
                    if (inv == null) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SalesReturnForm(invoice: inv))).then((_) => _load());
                  },
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Record Sales Return'),
                ),
              ),
              if (outstanding > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: StitchColors.success, foregroundColor: Colors.white),
                    onPressed: _receivePayment,
                    icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                    label: Text('Receive ${formatPaise(outstanding)}'),
                  ),
                ),
              ],
            ]),
    );
  }

  Widget _totalsList(Invoice inv) {
    const style = TextStyle(fontSize: 12.5);
    final rows = <Widget>[
      _row('Subtotal', formatPaise(inv.subtotal), style),
    ];
    if (inv.discount > 0) {
      rows.add(_row('Discount', '-${formatPaise(inv.discount)}', style, valueColor: StitchColors.success));
    }
    rows.add(_row('Taxable', formatPaise(inv.taxable), style));
    if (inv.igst > 0) rows.add(_row('IGST', formatPaise(inv.igst), style));
    if (inv.cgst > 0) rows.add(_row('CGST', formatPaise(inv.cgst), style));
    if (inv.sgst > 0) rows.add(_row('SGST', formatPaise(inv.sgst), style));
    if (inv.roundOff != 0) {
      rows.add(_row('Round off', '${inv.roundOff > 0 ? '+' : '-'}${formatPaise(inv.roundOff.abs())}', style));
    }
    rows.add(const Divider(height: 12));
    rows.add(_row('Total', formatPaise(inv.total), const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));
    if (inv.amountPaid > 0) {
      rows.add(_row('Paid', '-${formatPaise(inv.amountPaid)}', style, valueColor: StitchColors.success));
      rows.add(_row('Balance due', formatPaise(inv.outstanding.paise), const TextStyle(fontSize: 13, fontWeight: FontWeight.w800), valueColor: StitchColors.warning));
    }
    return Column(children: rows);
  }

  Widget _row(String label, String value, TextStyle style, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: style),
          Text(value, style: valueColor == null ? style : style.copyWith(color: valueColor)),
        ]),
      );

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}