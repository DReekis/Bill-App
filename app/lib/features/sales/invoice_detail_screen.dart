import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _showPrintPicker() async {
    final inv = invoice;
    final biz = business;
    if (inv == null || biz == null) return;

    final selected = await showModalBottomSheet<InvoicePaperSize>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Select Print Format',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose layout based on your connected printer hardware',
                style: TextStyle(fontSize: 12.5, color: StitchColors.textSecondary),
              ),
              const SizedBox(height: 14),
              ...InvoicePaperSize.values.map(
                (size) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StitchColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(size.icon, color: StitchColors.primary, size: 22),
                  ),
                  title: Text(size.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(size.description, style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: StitchColors.textTertiary),
                  onTap: () => Navigator.pop(ctx, size),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => busy = true);
      try {
        await printInvoice(business: biz, invoice: inv, paperSize: selected);
      } catch (e) {
        if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  void _showUpiModal() {
    final inv = invoice;
    final biz = business;
    if (inv == null || biz == null) return;

    final outstanding = inv.outstanding.paise;
    final amountPaise = outstanding > 0 ? outstanding : inv.total;
    final upiUri = generateUpiPaymentUri(
      business: biz,
      invoiceNumber: inv.number,
      amountPaise: amountPaise,
    );
    final upiVpa = getBusinessUpiId(biz);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: StitchColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: StitchColors.primary, size: 22),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Instant UPI Payment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Scan with any UPI App to pay',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: QrImageView(
                  data: upiUri,
                  version: QrVersions.auto,
                  size: 190.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E293B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                formatPaise(amountPaise),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: StitchColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pay to: ${biz.name}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),

              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: upiVpa));
                  showAppMessage(context, 'UPI ID copied: $upiVpa');
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: StitchColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        upiVpa,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 13, color: StitchColors.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(upiUri);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          if (ctx.mounted) {
                            showAppMessage(ctx, 'No UPI apps found on this device', error: true);
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open UPI App'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: StitchColors.success),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _receivePayment();
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text('Mark Paid'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _receivePayment() {
    final inv = invoice;
    if (inv == null) return;
    final isWalkIn = inv.customerId == null || inv.customerId == 0;
    final name = (isWalkIn || inv.customerName == null || inv.customerName!.isEmpty)
        ? 'Walk-in customer'
        : inv.customerName;
    final outstanding = inv.outstanding.paise > 0 ? inv.outstanding.paise : inv.total;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PaymentFormScreen(
            partyType: 'customer',
            partyId: inv.customerId,
            partyName: name,
            initialAmount: outstanding,
            initialInvoiceId: inv.id,
          ),
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
          if (inv != null && inv.total > 0)
            IconButton(
              tooltip: 'UPI Payment QR',
              onPressed: _showUpiModal,
              icon: const Icon(Icons.qr_code_rounded),
            ),
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
              if (inv.total > 0) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: StitchColors.primary, width: 1.3),
                      foregroundColor: StitchColors.primary,
                    ),
                    onPressed: _showUpiModal,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: Text(
                      outstanding > 0
                          ? 'Collect via UPI QR (${formatPaise(outstanding)})'
                          : 'Show UPI QR Code',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showPrintPicker,
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