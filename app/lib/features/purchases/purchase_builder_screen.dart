import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../suppliers/supplier_form.dart';

class _PurchaseLine {
  _PurchaseLine({required this.product, required this.qty, required this.price, required this.tax});
  final Product? product;
  double qty;
  int price;
  int tax;
  String get label => product?.name ?? 'Item';
}

class PurchaseBuilderScreen extends StatefulWidget {
  const PurchaseBuilderScreen({super.key, this.initialSupplierId});
  final int? initialSupplierId;
  @override
  State<PurchaseBuilderScreen> createState() => _PurchaseBuilderScreenState();
}

class _PurchaseBuilderScreenState extends State<PurchaseBuilderScreen> {
  List<_PurchaseLine> lines = [];
  List<Product>? products;
  List<Supplier>? suppliers;
  int? supplierId;
  String? supplierName;
  bool directVendor = false;
  double total = 0;
  bool saving = false;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final prods = await repo.products(businessId);
    final supps = await repo.suppliers(businessId);
    if (!mounted) return;
    setState(() {
      products = prods;
      suppliers = supps;
      if (supplierId == null && widget.initialSupplierId != null) {
        for (final s in supps) {
          if (s.id == widget.initialSupplierId) {
            supplierId = s.id;
            supplierName = s.name;
            break;
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _pickSupplier() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final all = suppliers ?? const <Supplier>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select supplier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Direct / cash vendor', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() {
                  supplierId = null;
                  supplierName = 'Direct / cash vendor';
                  directVendor = true;
                });
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ...all.map((s) => ListTile(
                  leading: InitialsAvatar(s.name, size: 36),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.phone ?? ''),
                  onTap: () {
                    setState(() {
                      supplierId = s.id;
                      supplierName = s.name;
                      directVendor = false;
                    });
                    Navigator.pop(context);
                  },
                )),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => SupplierFormSheet(
                    onSaved: _load,
                    businessId: context.read<Session>().businessId!,
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add new supplier'),
            ),
          ]),
        );
      },
    );
  }

  void _addLine() {
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'Add products first from the Stock tab', error: true);
      return;
    }
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          children: all
              .map((p) => ListTile(
                    leading: InitialsAvatar(p.name, size: 36),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${_qty(p.stock)} in stock'),
                    onTap: () => Navigator.pop(context, p.id),
                  ))
              .toList(),
        ),
      ),
    ).then((productId) {
      if (productId == null) return;
      for (final p in all) {
        if (p.id != productId) continue;
        final newLine = _PurchaseLine(
          product: p,
          qty: 1,
          price: p.purchasePrice == 0 ? 100 : p.purchasePrice,
          tax: p.gstRate,
        );
        setState(() => lines.add(newLine));
        return;
      }
    });
  }

  void _editLine(int index) {
    final line = lines[index];
    final qty = TextEditingController(text: _qty(line.qty));
    final price = TextEditingController(text: (line.price / 100).toStringAsFixed(2));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: inputDecoration('Quantity'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: inputDecoration('Unit cost'))),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final q = double.tryParse(qty.text.trim());
                    final p = double.tryParse(price.text.trim());
                    if (q == null || q <= 0 || p == null || p <= 0) return;
                    setState(() {
                      line.qty = q;
                      line.price = (p * 100).round();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _checkout() async {
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item', error: true);
      return;
    }
    final businessId = context.read<Session>().businessId;
    if (businessId == null) {
      showAppMessage(context, 'No active business', error: true);
      return;
    }
    if (supplierId == null && !directVendor) {
      showAppMessage(context, 'Select a supplier first', error: true);
      return;
    }
    final paid = TextEditingController(text: (total / 100).toStringAsFixed(2));
    String date = todayIso();
    String? mode = 'Cash';
    final notes = TextEditingController();
    final commit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Purchase — ${formatPaise(total.toInt())}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                AppAmountField(controller: paid, label: 'Paid now'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: inputDecoration('Payment mode'),
                  items: paymentModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setSheetState(() => mode = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final dt = dateTimeFor(date);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dt,
                      firstDate: DateTime(dt.year - 2),
                      lastDate: DateTime(dt.year + 2),
                    );
                    if (picked != null) setSheetState(() => date = isoDate(picked));
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(date),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(controller: notes, label: 'Notes (optional)'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: AsyncButton(
                    label: 'Save purchase',
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (commit != true) return;
    setState(() => saving = true);
    try {
      final items = lines
          .map((l) => (
                l.product?.id,
                l.label,
                l.qty,
                l.price,
                l.tax,
              ))
          .toList();
      final paidAmount = _toPaise(paid.text);
      await Repository.instance.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: supplierName ?? 'Direct vendor',
        date: date,
        items: items,
        amountPaid: paidAmount,
        paymentMode: paidAmount > 0 ? (mode ?? 'Cash') : null,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      if (mounted) {
        showAppMessage(context, 'Purchase saved · stock updated');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _recomputeTotal() {
    total = lines.fold<double>(0, (sum, l) =>
        sum + (l.price * l.qty).round() + ((l.price * l.qty * l.tax / 100).round()));
  }

  @override
  Widget build(BuildContext context) {
    _recomputeTotal();
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        AppCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            onTap: _pickSupplier,
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              if (supplierName != null)
                InitialsAvatar(supplierName!, size: 38)
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: StitchColors.surfaceVariant, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.storefront_outlined, color: StitchColors.primary, size: 20),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(supplierName ?? 'Select supplier',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: supplierName == null ? StitchColors.textSecondary : StitchColors.textPrimary)),
                  const Text('Direct vendor if none', style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: StitchColors.textTertiary),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add item')),
        ]),
        if (lines.isEmpty)
          AppEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'No items yet',
            subtitle: 'Add products to record the purchase',
            action: OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Item'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF335C8D),
                side: BorderSide(color: const Color(0xFF335C8D).withValues(alpha: 0.4)),
              ),
            ),
          )
        else
          ...lines.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _editLine(e.key),
                  borderRadius: BorderRadius.circular(12),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.value.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('${_qty(e.value.qty)} × ${formatPaise(e.value.price)} ${e.value.tax > 0 ? "· GST ${e.value.tax}%" : ""}',
                              style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                        ]),
                      ),
                      Text(formatPaise((e.value.price * e.value.qty * (1 + e.value.tax / 100)).round()),
                          style: moneyStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => lines.removeAt(e.key)),
                        icon: const Icon(Icons.close_rounded, size: 17),
                        color: StitchColors.textTertiary,
                      ),
                    ]),
                  ),
                ),
              )),
        if (lines.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total cost', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(formatPaise(total.round()), style: moneyStyle(fontSize: 15)),
            ]),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AsyncButton(
            loading: saving,
            icon: lines.isEmpty ? Icons.add_rounded : Icons.local_shipping_rounded,
            label: lines.isEmpty ? 'Add items' : 'Save purchase ${formatPaise(total.round())}',
            backgroundColor: lines.isEmpty ? const Color(0xFF4A6DA7) : StitchColors.primary,
            onPressed: lines.isEmpty ? _addLine : _checkout,
          ),
        ),
      ),
    );
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}