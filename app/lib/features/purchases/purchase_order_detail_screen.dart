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

class PurchaseOrderDetailScreen extends StatefulWidget {
  const PurchaseOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  PurchaseOrder? order;
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
    final po = await repo.purchaseOrder(bizId, widget.orderId);
    final b = await repo.getBusiness(bizId);
    if (!mounted) return;
    setState(() {
      order = po;
      business = b;
    });
  }

  Future<void> _convert() async {
    final po = order;
    if (po == null || po.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Convert to Purchase?'),
        content: Text(
          'This will record a Purchase and add inventory stock from Purchase Order ${po.number} for ${formatPaise(po.total)}.',
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
      await repo.convertPurchaseOrderToPurchase(po.id!);
      if (!mounted) return;
      showAppMessage(context, 'Purchase Order converted to Purchase successfully ✓ (Inventory updated)');
      await _load();
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final po = order;
    final b = business;
    if (po == null || b == null) return;
    setState(() => _busy = true);
    try {
      await sharePurchaseOrder(business: b, order: po);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final po = order;
    final b = business;
    if (po == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printPurchaseOrder(business: b, order: po);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final po = order;
    if (po == null || po.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Purchase Order?'),
        content: Text('Are you sure you want to delete Purchase Order ${po.number}? This cannot be undone.'),
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
      await Repository.instance.deletePurchaseOrder(bizId, po.id!);
      if (!mounted) return;
      showAppMessage(context, 'Purchase Order deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final po = order;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          po != null ? po.number : 'Purchase Order Details',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (po != null) ...[
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
      body: po == null
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
                                color: const Color(0xFFE0F7FA),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                size: 24,
                                color: Color(0xFF00838F),
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
                                        po.number,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: po.status.toLowerCase() == 'converted'
                                              ? StitchColors.successSoft
                                              : const Color(0xFFE0F7FA),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          po.status,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: po.status.toLowerCase() == 'converted'
                                                ? StitchColors.success
                                                : const Color(0xFF00838F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Date: ${displayDate(po.date)}${po.expectedDate != null ? ' • Expected: ${displayDate(po.expectedDate!)}' : ''}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Supplier Card
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SUPPLIER / VENDOR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              po.supplierName ?? 'Direct Vendor',
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
                            Text(
                              'ITEMS (${po.lines.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const Divider(height: 16),
                            ...po.lines.map((l) {
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
                                            '${l.quantity == l.quantity.roundToDouble() ? l.quantity.round() : l.quantity} ${l.unit ?? 'pc'} × ${formatPaise(l.price)}',
                                            style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      formatPaise(subtotal),
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Order Amount',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  formatPaise(po.total),
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

                      if (po.notes != null && po.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(po.notes!, style: const TextStyle(fontSize: 13)),
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
                      if (po.status.toLowerCase() != 'converted') ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _convert,
                            icon: const Icon(Icons.transform_rounded, size: 18),
                            label: const Text('Convert to Purchase'),
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
