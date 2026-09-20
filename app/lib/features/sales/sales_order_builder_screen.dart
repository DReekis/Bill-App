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

class SalesOrderBuilderScreen extends StatefulWidget {
  const SalesOrderBuilderScreen({super.key});

  @override
  State<SalesOrderBuilderScreen> createState() => _SalesOrderBuilderScreenState();
}

class _LineEdit {
  _LineEdit({required this.product, required this.qty, required this.price});
  final Product product;
  double qty;
  int price;
}

class _SalesOrderBuilderScreenState extends State<SalesOrderBuilderScreen> {
  List<_LineEdit> lines = [];
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  bool saving = false;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final custs = await repo.customers(businessId);
    final prods = await repo.products(businessId);
    if (!mounted) return;
    setState(() {
      customers = custs;
      products = prods;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _save() async {
    if (customerId == null) {
      showAppMessage(context, 'Select a customer', error: true);
      return;
    }
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = context.read<Session>().businessId!;
      final order = SalesOrder(
        businessId: bizId,
        number: 'SO-${DateTime.now().millisecondsSinceEpoch}',
        customerId: customerId,
        customerName: customerName,
        date: todayIso(),
        status: 'Pending',
        total: lines.fold(0, (sum, l) => sum + (l.price * l.qty).round()),
        lines: lines.map((l) => InvoiceLine(
          productId: l.product.id,
          name: l.product.name,
          quantity: l.qty,
          price: l.price,
        )).toList(),
      );
      await Repository.instance.finalizeSalesOrder(order);
      if (mounted) {
        showAppMessage(context, 'Sales Order saved');
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
      appBar: AppBar(title: const Text('New Sales Order')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Customer'),
              items: customers?.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) {
                setState(() {
                  customerId = v;
                  customerName = customers?.firstWhere((c) => c.id == v).name;
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
              child: AsyncButton(label: 'Save Order', loading: saving, onPressed: _save),
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
        title: 'Select Order Items',
        actionLabel: 'Add to Order',
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
                ? 'Added ${selectedItems.first.product.name} to order'
                : 'Added ${selectedItems.length} items to order',
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
                    price: p.salePrice,
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
