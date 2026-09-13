import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class QuotationBuilderScreen extends StatefulWidget {
  const QuotationBuilderScreen({super.key});

  @override
  State<QuotationBuilderScreen> createState() => _QuotationBuilderScreenState();
}

class _LineEdit {
  _LineEdit({required this.product, required this.qty, required this.price, required this.discountPercent, required this.gstRate});
  final Product product;
  double qty;
  int price;
  double discountPercent;
  int gstRate;
}

class _QuotationBuilderScreenState extends State<QuotationBuilderScreen> {
  List<_LineEdit> lines = [];
  Business? business;
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  bool saving = false;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final biz = await repo.getBusiness(businessId);
    final custs = await repo.customers(businessId);
    final prods = await repo.products(businessId);
    if (!mounted) return;
    setState(() {
      business = biz;
      customers = custs;
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
      lines.add(_LineEdit(
        product: p,
        qty: 1,
        price: p.salePrice,
        discountPercent: 0,
        gstRate: p.gstRate,
      ));
    });
  }

  Future<void> _save() async {
    if (customerId == null) {
      showAppMessage(context, 'Please select a customer', error: true);
      return;
    }
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = context.read<Session>().businessId!;
      final quote = Quotation(
        businessId: bizId,
        number: 'EST-${DateTime.now().millisecondsSinceEpoch}',
        customerId: customerId,
        customerName: customerName,
        date: todayIso(),
        total: _total(),
        status: 'Open',
        lines: lines.map((l) => InvoiceLine(
          productId: l.product.id,
          name: l.product.name,
          quantity: l.qty,
          price: l.price,
          gstRate: l.gstRate,
          taxable: (l.price * l.qty).round(),
        )).toList(),
      );
      await Repository.instance.finalizeQuotation(quote);
      if (mounted) {
        showAppMessage(context, 'Quotation saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  int _total() {
    double t = 0;
    for (final l in lines) {
      t += l.price * l.qty;
    }
    return t.round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Estimate')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Select Customer'),
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
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => lines.removeAt(index)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Total: ${formatPaise(_total())}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton(onPressed: () => _showProductPicker(), child: const Text('Add Item')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: AsyncButton(label: 'Save Estimate', loading: saving, onPressed: _save),
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
          subtitle: Text(formatPaise(p.salePrice)),
          onTap: () {
            _add(p);
            Navigator.pop(context);
          },
        )).toList() ?? [],
      ),
    );
  }
}
