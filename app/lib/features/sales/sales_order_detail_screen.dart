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

class SalesOrderDetailScreen extends StatefulWidget {
  const SalesOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<SalesOrderDetailScreen> createState() => _SalesOrderDetailScreenState();
}

class _SalesOrderDetailScreenState extends State<SalesOrderDetailScreen> {
  SalesOrder? order;
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
    final o = await repo.salesOrder(bizId, widget.orderId);
    final b = await repo.getBusiness(bizId);
    if (!mounted) return;
    setState(() {
      order = o;
      business = b;
    });
  }

  Future<void> _convert() async {
    final o = order;
    if (o == null || o.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Convert to Sale Invoice?'),
        content: Text(
          'This will generate an official sales invoice from Sell Order ${o.number} for ${formatPaise(o.total)}.',
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
      final invoiceId = await repo.convertSalesOrderToInvoice(o.id!);
      if (!mounted) return;
      showAppMessage(context, 'Sell Order converted to Invoice successfully ✓');
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
    final o = order;
    final b = business;
    if (o == null || b == null) return;
    setState(() => _busy = true);
    try {
      await shareSalesOrder(business: b, order: o);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final o = order;
    final b = business;
    if (o == null || b == null) return;
    setState(() => _busy = true);
    try {
      await printSalesOrder(business: b, order: o);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final o = order;
    if (o == null || o.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Sell Order?'),
        content: Text('Are you sure you want to delete Sell Order ${o.number}? This cannot be undone.'),
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
      await Repository.instance.deleteSalesOrder(bizId, o.id!);
      if (!mounted) return;
      showAppMessage(context, 'Sell Order deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          o != null ? o.number : 'Sell Order Details',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (o != null) ...[
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
      body: o == null
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
                                color: const Color(0xFFEDE7F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.assignment_outlined,
                                size: 24,
                                color: Color(0xFF5E35B1),
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
                                        o.number,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: o.status.toLowerCase() == 'converted'
                                              ? StitchColors.successSoft
                                              : const Color(0xFFEDE7F6),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          o.status,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: o.status.toLowerCase() == 'converted'
                                                ? StitchColors.success
                                                : const Color(0xFF5E35B1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Date: ${displayDate(o.date)}${o.dueDate != null ? ' • Due: ${displayDate(o.dueDate!)}' : ''}',
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
                              'CUSTOMER',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              o.customerName ?? 'Walk-in Customer',
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
                              'ITEMS (${o.lines.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: StitchColors.textSecondary,
                              ),
                            ),
                            const Divider(height: 16),
                            ...o.lines.map((l) {
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
                                  formatPaise(o.total),
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

                      if (o.notes != null && o.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(o.notes!, style: const TextStyle(fontSize: 13)),
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
                      if (o.status.toLowerCase() != 'converted') ...[
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
