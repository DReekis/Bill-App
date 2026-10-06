import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../../utils/widgets.dart';
import 'invoice_detail_screen.dart';

class DeliveryChallanDetailScreen extends StatefulWidget {
  const DeliveryChallanDetailScreen({super.key, required this.challanId});

  final int challanId;

  @override
  State<DeliveryChallanDetailScreen> createState() => _DeliveryChallanDetailScreenState();
}

class _DeliveryChallanDetailScreenState extends State<DeliveryChallanDetailScreen> {
  DeliveryChallan? challan;
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
    final dc = await repo.deliveryChallan(bizId, widget.challanId);
    final b = await repo.getBusiness(bizId);
    if (!mounted) return;
    setState(() {
      challan = dc;
      business = b;
    });
  }

  Future<void> _share() async {
    final dc = challan;
    final b = business;
    if (dc == null || b == null) return;
    setState(() => _busy = true);
    try {
      await shareDeliveryChallan(business: b, challan: dc);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final dc = challan;
    final b = business;
    if (dc == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printDeliveryChallan(business: b, challan: dc);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewPdf() async {
    final dc = challan;
    final b = business;
    if (dc == null || b == null) return;
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
        title: '${dc.number} - Preview',
        pdfBuilder: () => buildDeliveryChallanPdf(
          business: b,
          challan: dc,
          settings: settings,
        ),
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Preview failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert() async {
    final dc = challan;
    if (dc == null || dc.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Convert to Sale Invoice?'),
        content: Text(
          'This will generate an official sales invoice from Delivery Challan ${dc.number}.',
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
      final invoiceId = await repo.convertDeliveryChallanToInvoice(dc.id!);
      if (!mounted) return;
      showAppMessage(context, 'Delivery Challan converted to Invoice successfully ✓');
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

  Future<void> _delete() async {
    final dc = challan;
    if (dc == null || dc.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Delivery Challan?'),
        content: Text('Are you sure you want to delete Delivery Challan ${dc.number}? This cannot be undone.'),
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
      await Repository.instance.deleteDeliveryChallan(bizId, dc.id!);
      if (!mounted) return;
      showAppMessage(context, 'Delivery Challan deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dc = challan;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          dc != null ? dc.number : 'Delivery Challan',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (dc != null) ...[
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
      body: dc == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Header & Status Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                size: 26,
                                color: Color(0xFF0284C7),
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
                                        dc.number,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: dc.status.toLowerCase() == 'delivered'
                                              ? StitchColors.successSoft
                                              : (dc.status.toLowerCase() == 'converted'
                                                  ? const Color(0xFFEDE9FE)
                                                  : const Color(0xFFFEF3C7)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          dc.status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: dc.status.toLowerCase() == 'delivered'
                                                ? StitchColors.success
                                                : (dc.status.toLowerCase() == 'converted'
                                                    ? const Color(0xFF6D28D9)
                                                    : const Color(0xFFB45309)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Date: ${displayDate(dc.date)}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Vehicle & Dispatch Details (Prominent BillBook Style)
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.commute_rounded, size: 18, color: StitchColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'TRANSPORT & VEHICLE DETAILS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: StitchColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (dc.vehicleNo != null && dc.vehicleNo!.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: StitchColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.directions_car_filled_rounded, size: 18, color: StitchColors.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      dc.vehicleNo!,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                        color: StitchColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ] else ...[
                              const Text('Vehicle No.: Not specified',
                                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                              const SizedBox(height: 8),
                            ],
                            if (dc.transportDetails != null && dc.transportDetails!.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Transport / LR: ',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                                  Expanded(
                                    child: Text(dc.transportDetails!,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (dc.address != null && dc.address!.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Delivery To: ',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                                  Expanded(
                                    child: Text(dc.address!,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Linked Invoice Reference (if created from an invoice)
                      if (dc.invoiceId != null || (dc.invoiceNumber != null && dc.invoiceNumber!.isNotEmpty)) ...[
                        AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: StitchColors.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.link_rounded, size: 18, color: StitchColors.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('LINKED SALES INVOICE',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      dc.invoiceNumber ?? 'Invoice #${dc.invoiceId}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              if (dc.invoiceId != null)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => InvoiceDetailScreen(invoiceId: dc.invoiceId!),
                                      ),
                                    );
                                  },
                                  child: const Text('View Bill', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Customer Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CONSIGNEE / CLIENT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dc.customerName ?? 'Direct Client',
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'DISPATCHED ITEMS (${dc.lines.length})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: StitchColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  'Total Qty: ${dc.lines.fold<double>(0, (sum, l) => sum + l.quantity).toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.primary),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            ...dc.lines.map((l) {
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
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Text(
                                        '${l.quantity == l.quantity.roundToDouble() ? l.quantity.round() : l.quantity} ${l.unit ?? 'pc'}',
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      if (dc.notes != null && dc.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NOTES & DISPATCH TERMS',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(dc.notes!, style: const TextStyle(fontSize: 13, height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Bottom Action Bar
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
                      if (dc.invoiceId == null && dc.status.toLowerCase() != 'converted') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _convert,
                            icon: const Icon(Icons.transform_rounded, size: 18),
                            label: const Text('Convert to Sale'),
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
