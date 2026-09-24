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
import 'invoice_detail_screen.dart';

class QuotationDetailScreen extends StatefulWidget {
  const QuotationDetailScreen({super.key, required this.quotationId});

  final int quotationId;

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  Quotation? quotation;
  Business? business;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    final bizId = session.businessId;
    if (bizId == null) return;
    final repo = Repository.instance;
    final q = await repo.quotation(bizId, widget.quotationId);
    final b = await repo.getBusiness(bizId);
    if (!mounted) return;
    setState(() {
      quotation = q;
      business = b;
    });
  }

  Future<void> _convert() async {
    final q = quotation;
    if (q == null || q.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Convert to Sale Invoice?'),
        content: Text(
          'This will generate an official sales invoice from Estimate ${q.number} for ₹${(q.total / 100).toStringAsFixed(2)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = Repository.instance;
      final invoiceId = await repo.convertQuotationToInvoice(q.id!);
      if (!mounted) return;
      showAppMessage(context, 'Estimate converted to Invoice successfully ✓');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId),
        ),
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final q = quotation;
    final b = business;
    if (q == null || b == null) return;
    setState(() => _busy = true);
    try {
      await shareQuotation(business: b, quotation: q);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final q = quotation;
    final b = business;
    if (q == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printQuotation(business: b, quotation: q);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final q = quotation;
    if (q == null || q.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Estimate?'),
        content: Text('Are you sure you want to delete Estimate ${q.number}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StitchColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final bizId = context.read<Session>().businessId!;
      await Repository.instance.deleteQuotation(bizId, q.id!);
      if (!mounted) return;
      showAppMessage(context, 'Estimate deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = quotation;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          q != null ? q.number : 'Estimate Details',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (q != null) ...[
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print',
              onPressed: _busy ? null : _print,
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _busy ? null : _share,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: StitchColors.error),
              tooltip: 'Delete',
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
      body: q == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Status & Meta Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.request_quote_rounded,
                                size: 24,
                                color: Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        q.number,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: q.status.toLowerCase() == 'converted'
                                              ? StitchColors.successSoft
                                              : const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          q.status.toLowerCase() == 'converted' ? 'Converted' : 'Estimate',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: q.status.toLowerCase() == 'converted'
                                                ? StitchColors.success
                                                : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Date: ${displayDate(q.date)}${q.expiryDate != null ? ' • Valid till: ${displayDate(q.expiryDate!)}' : ''}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Customer Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CLIENT / CUSTOMER',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              q.customerName ?? 'Walk-in Client',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Items Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'ITEMS (${q.lines.length})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: StitchColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            ...q.lines.map((l) {
                              final subtotal = (l.price * l.quantity).round();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l.name,
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${l.quantity == l.quantity.roundToDouble() ? l.quantity.round() : l.quantity} ${l.unit ?? 'pc'} × ${formatPaise(l.price)}${l.gstRate > 0 ? ' • GST ${l.gstRate}%' : ''}',
                                            style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      formatPaise(subtotal),
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Summary Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                                Text(formatPaise(q.subtotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            if (q.cgst > 0 || q.sgst > 0 || q.igst > 0) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('GST Tax', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                                  Text(formatPaise(q.cgst + q.sgst + q.igst), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                            const Divider(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Estimate',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  formatPaise(q.total),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: StitchColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (q.notes != null && q.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(q.notes!, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Sticky Bottom Action Bar (BillBook Style)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _share,
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Share PDF'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (q.status.toLowerCase() != 'converted') ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _convert,
                            icon: const Icon(Icons.transform_rounded, size: 18),
                            label: const Text('Convert to Sale Invoice'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
