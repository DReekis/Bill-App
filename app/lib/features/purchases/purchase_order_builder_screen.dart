import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';
import '../inventory/multi_product_picker_sheet.dart';
import '../inventory/product_form.dart';

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
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'No products found. Add products first', error: true);
      return;
    }

    final initialMap = <int, double>{};
    for (final l in lines) {
      if (l.product.id != null) {
        initialMap[l.product.id!] = l.qty;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MultiProductPickerSheet(
        products: all,
        isPurchase: true,
        title: 'Select PO Items',
        actionLabel: 'Add to PO',
        initialQuantities: initialMap,
        onItemsSelected: (selectedItems) {
          setState(() {
            for (final item in selectedItems) {
              final existingIndex = lines.indexWhere((l) => l.product.id == item.product.id);
              if (existingIndex >= 0) {
                lines[existingIndex].qty = item.quantity;
                lines[existingIndex].price = item.unitPrice;
              } else {
                lines.add(_LineEdit(
                  product: item.product,
                  qty: item.quantity,
                  price: item.unitPrice,
                ));
              }
            }
          });
          showAppMessage(
            context,
            selectedItems.length == 1
                ? 'Added ${selectedItems.first.product.name} to PO'
                : 'Added ${selectedItems.length} items to PO',
          );
        },
        onAddNew: () async {
          Navigator.pop(context);
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _load,
              onSavedProduct: (p) {
                setState(() {
                  lines.add(_LineEdit(
                    product: p,
                    qty: 1,
                    price: p.purchasePrice == 0 ? 100 : p.purchasePrice,
                  ));
                });
              },
              businessId: context.read<Session>().businessId!,
            ),
          );
        },
      ),
    );
  }
}
