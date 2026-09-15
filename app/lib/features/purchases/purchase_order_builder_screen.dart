import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class PurchaseOrderBuilderScreen extends StatefulWidget {
  const PurchaseOrderBuilderScreen({super.key});

  @override
  State<PurchaseOrderBuilderScreen> createState() => _PurchaseOrderBuilderScreenState();
}

class _LineEdit {
  _LineEdit({required this.product, required this.qty, required this.price});
  final Product product;
  double qty;
  int price;
}

class _PurchaseOrderBuilderScreenState extends State<PurchaseOrderBuilderScreen> {
  List<_LineEdit> lines = [];
  List<Supplier>? suppliers;
  List<Product>? products;
  int? supplierId;
  String? supplierName;
  bool saving = false;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final sups = await repo.suppliers(businessId);
    final prods = await repo.products(businessId);
    if (!mounted) return;
    setState(() {
      suppliers = sups;
      products = prods;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _add(Product p) {
    setState(() {
      lines.add(_LineEdit(product: p, qty: 1, price: p.purchasePrice));
    });
  }

  Future<void> _save() async {
    if (supplierId == null) {
      showAppMessage(context, 'Select a supplier', error: true);
      return;
    }
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = context.read<Session>().businessId!;
      final order = PurchaseOrder(
        businessId: bizId,
        number: 'PO-${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supplierId,
        supplierName: supplierName,
        date: todayIso(),
        status: 'Draft',
        total: lines.fold(0, (sum, l) => sum + (l.price * l.qty).round()),
        lines: lines.map((l) => InvoiceLine(
          productId: l.product.id,
          name: l.product.name,
          quantity: l.qty,
          price: l.price,
        )).toList(),
      );
      await Repository.instance.finalizePurchaseOrder(order);
      if (mounted) {
        showAppMessage(context, 'Purchase Order saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase Order')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Supplier'),
              items: suppliers?.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (v) {
                setState(() {
                  supplierId = v;
                  supplierName = suppliers?.firstWhere((s) => s.id == v).name;
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final l = lines[index];
                return ListTile(
                  title: Text(l.product.name),
                  subtitle: Text('x${l.qty} @ ${formatPaise(l.price)}'),
                  trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => lines.removeAt(index))),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Spacer(),
                ElevatedButton(onPressed: _showProductPicker, child: const Text('Add Item')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: AsyncButton(label: 'Save PO', loading: saving, onPressed: _save),
            ),
          ),
        ],
      ),
    );
  }

  void _showProductPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        children: products?.map((p) => ListTile(
          title: Text(p.name),
          subtitle: Text(formatPaise(p.purchasePrice)),
          onTap: () {
            _add(p);
            Navigator.pop(context);
          },
        )).toList() ?? [],
      ),
    );
  }
}
