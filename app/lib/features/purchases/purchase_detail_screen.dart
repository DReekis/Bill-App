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
import 'purchase_builder_screen.dart';

class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseBill? purchase;
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
    final p = await repo.purchase(bizId, widget.purchaseId);
    final b = await repo.getBusiness(bizId);
    if (!mounted) return;
    setState(() {
      purchase = p;
      business = b;
    });
  }

  Future<void> _share() async {
    final p = purchase;
    final b = business;
    if (p == null || b == null) return;
    setState(() => _busy = true);
    try {
      await sharePurchaseBill(business: b, purchase: p);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final p = purchase;
    final b = business;
    if (p == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printPurchaseBill(business: b, purchase: p);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewPdf() async {
    final p = purchase;
    final b = business;
    if (p == null || b == null) return;
    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      final repo = Repository.instance;
      final settings = await repo.getInvoiceCustomizationSettings(session.businessId ?? b.id ?? 1);

      if (!mounted) return;
      await showInvoicePreviewModal(
        context,
        business: b,
        settings: settings,
        title: '${p.number} - Preview',
        pdfBuilder: () => buildPurchaseBillPdf(
          business: b,
          purchase: p,
          settings: settings,
        ),
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Preview failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editPurchase() {
    final p = purchase;
    if (p == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseBuilderScreen(existingPurchaseId: p.id),
      ),
    ).then((_) => _load());
  }

  Future<void> _delete() async {
    final p = purchase;
    if (p == null || p.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Purchase Bill?'),
        content: Text(
          'Are you sure you want to delete Purchase ${p.number}? Inventory stock and ledger entries will be reversed.',
        ),
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
      await Repository.instance.deletePurchase(bizId, p.id!);
      if (!mounted) return;
      showAppMessage(context, 'Purchase Bill deleted ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = purchase;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          p != null ? p.number : 'Purchase Bill',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (p != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Purchase',
              onPressed: _busy ? null : _editPurchase,
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Preview PDF',
              onPressed: _busy ? null : _previewPdf,
            ),
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
      body: p == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Header & Status Card
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 26,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.number,
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      _buildStatusBadge(p),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    displayDate(p.date),
                                    style: const TextStyle(
                                      color: StitchColors.textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (p.supplierName != null && p.supplierName!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.storefront_outlined, size: 15, color: StitchColors.textSecondary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            p.supplierName!,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (p.supplierGstin != null && p.supplierGstin!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'GSTIN: ${p.supplierGstin}',
                                        style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                    if (p.supplierPhone != null && p.supplierPhone!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Phone: ${p.supplierPhone}',
                                        style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Items Card
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'PURCHASED ITEMS',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: StitchColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '${p.lines.length} items',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            if (p.lines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No item details recorded', style: TextStyle(color: StitchColors.textSecondary, fontSize: 13)),
                              )
                            else
                              ...p.lines.map((l) {
                                final lineTotal = (l.price * l.quantity).round();
                                final taxAmount = (lineTotal * (l.gstRate / 100)).round();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(l.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_qty(l.quantity)} ${l.unit ?? 'pc'} @ ${formatPaise(l.price)}${l.gstRate > 0 ? ' + ${l.gstRate}% GST' : ''}',
                                              style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        formatPaise(lineTotal + taxAmount),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Totals & Financial Breakdown Card
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FINANCIAL SUMMARY',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: StitchColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Divider(height: 20),
                            _buildRow('Bill Total', formatPaise(p.total), isBold: true),
                            const SizedBox(height: 8),
                            _buildRow('Amount Paid (${p.paymentMode})', formatPaise(p.amountPaid), color: StitchColors.success),
                            if (p.outstanding > 0) ...[
                              const SizedBox(height: 8),
                              _buildRow('Balance Payable', formatPaise(p.outstanding), color: const Color(0xFFD97706), isBold: true),
                            ],
                          ],
                        ),
                      ),

                      if (p.notes != null && p.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(p.notes!, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Standardized Sticky Bottom Action Bar
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: StitchColors.primary.withValues(alpha: 0.12),
                            foregroundColor: StitchColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _busy ? null : _editPurchase,
                          icon: const Icon(Icons.edit_note_rounded, size: 20),
                          label: const Text('Edit Purchase', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _previewPdf,
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              label: const Text('Preview'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _print,
                              icon: const Icon(Icons.print_outlined, size: 18),
                              label: const Text('Print'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _share,
                              icon: const Icon(Icons.share_rounded, size: 18),
                              label: const Text('Share'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
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

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: color ?? StitchColors.textSecondary, fontWeight: isBold ? FontWeight.w700 : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600, color: color ?? StitchColors.textPrimary)),
      ],
    );
  }

  Widget _buildStatusBadge(PurchaseBill p) {
    final isPaid = p.outstanding == 0 && p.total > 0;
    final isPartial = p.amountPaid > 0 && p.outstanding > 0;
    final (bg, fg, label) = isPaid
        ? (const Color(0xFFE8F5E9), const Color(0xFF2E7D32), 'Paid')
        : isPartial
            ? (const Color(0xFFFEF3C7), const Color(0xFFB45309), 'Partial')
            : (const Color(0xFFFEE2E2), const Color(0xFFDC2626), 'Unpaid');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
