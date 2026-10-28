import 'package:flutter/material.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/restock_notification_service.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class RestockPriceUpdateSheet extends StatefulWidget {
  const RestockPriceUpdateSheet({
    super.key,
    required this.businessId,
    required this.items,
    this.sourceRef,
  });

  final int businessId;
  final List<RestockReviewItem> items;
  final String? sourceRef;

  /// Shows the sheet immediately after a purchase or purchase order creation.
  static Future<void> show(
    BuildContext context, {
    required int businessId,
    required List<RestockReviewItem> items,
    String? sourceRef,
  }) async {
    if (items.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RestockPriceUpdateSheet(
        businessId: businessId,
        items: items,
        sourceRef: sourceRef,
      ),
    );
  }

  /// Shows the sheet loaded from pending restock reviews in Notifications.
  static Future<void> showPending(
    BuildContext context, {
    required int businessId,
  }) async {
    final pending =
        await RestockNotificationService.instance.getPendingReviews(businessId);
    if (pending.isEmpty) {
      if (context.mounted) {
        showAppMessage(context, 'No restocked items pending price review');
      }
      return;
    }
    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => RestockPriceUpdateSheet(
          businessId: businessId,
          items: pending,
        ),
      );
    }
  }

  @override
  State<RestockPriceUpdateSheet> createState() => _RestockPriceUpdateSheetState();
}

class _RestockPriceUpdateSheetState extends State<RestockPriceUpdateSheet> {
  late List<RestockReviewItem> _items;
  final Map<int, TextEditingController> _salePriceControllers = {};
  final Map<int, TextEditingController> _batchControllers = {};
  final Map<int, String?> _expiryDates = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    for (final item in _items) {
      final saleRupees = item.currentSalePrice / 100.0;
      _salePriceControllers[item.productId] = TextEditingController(
        text: saleRupees == saleRupees.roundToDouble()
            ? saleRupees.round().toString()
            : saleRupees.toStringAsFixed(2),
      );
      _batchControllers[item.productId] = TextEditingController();
      _expiryDates[item.productId] = item.currentExpiryDate;
    }
  }

  @override
  void dispose() {
    for (final c in _salePriceControllers.values) {
      c.dispose();
    }
    for (final c in _batchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _parseRupeesToPaise(String text) {
    final clean = text.trim().replaceAll(',', '');
    final val = double.tryParse(clean) ?? 0.0;
    return (val * 100).round();
  }

  Future<void> _pickExpiryDate(int productId) async {
    final curStr = _expiryDates[productId];
    final init = curStr != null ? (DateTime.tryParse(curStr) ?? DateTime.now()) : DateTime.now().add(const Duration(days: 180));
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _expiryDates[productId] = isoDate(picked);
      });
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      final updates = <int, ({int salePrice, String? expiryDate, String? batchNumber})>{};
      for (final item in _items) {
        final ctrl = _salePriceControllers[item.productId];
        final salePrice = ctrl != null ? _parseRupeesToPaise(ctrl.text) : item.currentSalePrice;
        final batchCtrl = _batchControllers[item.productId];
        final batch = batchCtrl?.text.trim().isNotEmpty == true ? batchCtrl!.text.trim() : null;
        updates[item.productId] = (
          salePrice: salePrice > 0 ? salePrice : item.currentSalePrice,
          expiryDate: _expiryDates[item.productId],
          batchNumber: batch,
        );
      }

      await RestockNotificationService.instance.applyUpdates(
        businessId: widget.businessId,
        updates: updates,
      );

      if (mounted) {
        Navigator.pop(context);
        showAppMessage(context, 'Selling prices and expiry dates updated successfully ✓');
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to save prices: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _dismissItem(int productId) async {
    await RestockNotificationService.instance.dismissItem(widget.businessId, productId);
    setState(() {
      _items.removeWhere((i) => i.productId == productId);
    });
    if (_items.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, media.viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.price_change_rounded, color: Color(0xFF6366F1), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New Stock: Set Selling Price & Expiry',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.sourceRef != null
                          ? 'Restocked from ${widget.sourceRef} · Update prices for new inventory'
                          : 'Update selling prices & expiry for newly restocked items',
                      style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20),
          Flexible(
            child: _items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('All restocked items reviewed!')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      final saleCtrl = _salePriceControllers[item.productId]!;
                      final curExpiry = _expiryDates[item.productId];
                      final purchaseRupees = item.newPurchasePrice / 100.0;
                      final currentSaleRupees = _parseRupeesToPaise(saleCtrl.text) / 100.0;
                      final hasMarginWarning = currentSaleRupees > 0 && currentSaleRupees <= purchaseRupees;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasMarginWarning
                                ? StitchColors.warning.withValues(alpha: 0.6)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      const SizedBox(height: 3),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0E7FF),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '+${item.restockedQty.toStringAsFixed(item.restockedQty.truncateToDouble() == item.restockedQty ? 0 : 2)} ${item.unit}',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF3730A3),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Cost: ₹${formatPaise(item.newPurchasePrice)}',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF166534),
                                              ),
                                            ),
                                          ),
                                          if (item.oldPurchasePrice > 0 && item.oldPurchasePrice != item.newPurchasePrice)
                                            Text(
                                              'Prev Cost: ₹${formatPaise(item.oldPurchasePrice)}',
                                              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                                  tooltip: 'Dismiss alert for this item',
                                  onPressed: () => _dismissItem(item.productId),
                                ),
                              ],
                            ),
                            if (hasMarginWarning) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: StitchColors.warning.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 14, color: StitchColors.warning),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'New purchase cost is equal or higher than selling price! Increase selling price to protect profit margin.',
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: saleCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'New Selling Price (₹)',
                                      labelStyle: const TextStyle(fontSize: 12),
                                      prefixText: '₹ ',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      side: BorderSide(
                                        color: curExpiry != null ? const Color(0xFF6366F1) : Colors.grey.shade300,
                                      ),
                                    ),
                                    onPressed: () => _pickExpiryDate(item.productId),
                                    icon: Icon(
                                      Icons.calendar_today_rounded,
                                      size: 14,
                                      color: curExpiry != null ? const Color(0xFF6366F1) : Colors.grey.shade600,
                                    ),
                                    label: Text(
                                      curExpiry != null ? 'Exp: $curExpiry' : (item.hasBatch ? 'Set Expiry *' : '+ Expiry Date'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: curExpiry != null ? const Color(0xFF6366F1) : Colors.grey.shade700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Review Later in Alerts', style: TextStyle(color: StitchColors.textSecondary, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _saveAll,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save Prices & Expiry', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
