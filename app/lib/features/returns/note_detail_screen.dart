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

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({
    super.key,
    required this.noteId,
    this.autoPreview = false,
  });

  final int noteId;
  final bool autoPreview;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  TransactionReturn? note;
  Business? business;
  Customer? customer;
  Supplier? supplier;
  bool _busy = false;
  bool _hasAutoPreviewed = false;

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
    final n = await repo.returnDetails(bizId, widget.noteId);
    final b = await repo.getBusiness(bizId);
    Customer? c;
    Supplier? s;
    if (n != null && n.partyId != null) {
      if (n.partyType == 'customer') {
        c = await repo.customer(bizId, n.partyId!);
      } else {
        s = await repo.supplier(bizId, n.partyId!);
      }
    }

    if (!mounted) return;
    setState(() {
      note = n;
      business = b;
      customer = c;
      supplier = s;
    });

    if (widget.autoPreview && !_hasAutoPreviewed && n != null && b != null) {
      _hasAutoPreviewed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _previewPdf();
      });
    }
  }

  Future<void> _previewPdf() async {
    final n = note;
    final b = business;
    if (n == null || b == null) return;
    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      final repo = Repository.instance;
      final settings = await repo.getInvoiceCustomizationSettings(session.businessId ?? b.id ?? 1);
      final isCredit = n.partyType == 'customer';
      final title = isCredit ? 'Credit Note Preview' : 'Debit Note Preview';

      if (!mounted) return;
      await showInvoicePreviewModal(
        context,
        business: b,
        settings: settings,
        title: '${n.number} - $title',
        pdfBuilder: () => buildReturnPdf(
          business: b,
          returnInvoice: n,
          customer: customer,
          settings: settings,
        ),
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Preview failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final n = note;
    final b = business;
    if (n == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printReturn(business: b, returnInvoice: n);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final n = note;
    final b = business;
    if (n == null || b == null) return;
    setState(() => _busy = true);
    try {
      await shareReturn(business: b, returnInvoice: n);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = note;
    final isCredit = n?.partyType == 'customer';
    final noteTypeLabel = isCredit ? 'Credit Note' : 'Debit Note';

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          n != null ? '${n.number} ($noteTypeLabel)' : noteTypeLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (n != null) ...[
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
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
          ],
        ],
      ),
      body: n == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Header Card
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: (isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1))
                                        .withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isCredit ? Icons.assignment_return_outlined : Icons.assignment_returned_outlined,
                                    color: isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        noteTypeLabel.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                          color: isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1),
                                        ),
                                      ),
                                      Text(
                                        n.number,
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: StitchColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    n.status,
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.success),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: _infoCol(
                                    'DATE',
                                    displayDate(n.date),
                                    icon: Icons.calendar_today_outlined,
                                  ),
                                ),
                                Expanded(
                                  child: _infoCol(
                                    isCredit ? 'CUSTOMER' : 'SUPPLIER',
                                    n.partyName ?? (isCredit ? 'Cash Customer' : 'Direct Vendor'),
                                    icon: Icons.person_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                            if (n.reason != null && n.reason!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _infoCol('REASON', n.reason!, icon: Icons.help_outline_rounded),
                            ],
                            if (customer?.gstin != null || supplier?.gstin != null) ...[
                              const SizedBox(height: 12),
                              _infoCol('GSTIN', (customer?.gstin ?? supplier?.gstin)!, icon: Icons.badge_outlined),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Returned Items
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'RETURNED ITEMS',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: StitchColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '${n.lines.length} items',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            if (n.lines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No item details recorded', style: TextStyle(color: StitchColors.textSecondary, fontSize: 13)),
                              )
                            else
                              ...n.lines.map((l) {
                                final lineTotal = (l.price * l.quantity).round();
                                final taxAmount = l.tax > 0 ? l.tax : (lineTotal * (l.gstRate / 100)).round();
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
                                              '${_qty(l.quantity)} ${l.unit ?? "pc"} @ ${formatPaise(l.price)}${l.gstRate > 0 ? " • ${l.gstRate}% GST" : ""}',
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
                      const SizedBox(height: 14),

                      // Accounting / Tax Summary
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SUMMARY & TAX',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: StitchColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Divider(height: 20),
                            _summaryRow('Subtotal', formatPaise(n.subtotal > 0 ? n.subtotal : n.taxable)),
                            _summaryRow('Taxable Amount', formatPaise(n.taxable)),
                            if (n.tax > 0) ...[
                              _summaryRow('Total Tax (GST)', formatPaise(n.tax), color: StitchColors.primary),
                            ],
                            const Divider(height: 20),
                            _summaryRow('Total Note Value', formatPaise(n.total), bold: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                          onPressed: _busy ? null : _previewPdf,
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('Preview PDF'),
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
                          icon: const Icon(Icons.print_outlined, size: 16),
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
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Share'),
                          style: FilledButton.styleFrom(
                            backgroundColor: isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoCol(String label, String value, {required IconData icon}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: StitchColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );

  Widget _summaryRow(String label, String value, {Color color = StitchColors.textPrimary, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            Text(value, style: TextStyle(fontSize: bold ? 15 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ],
        ),
      );

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}
