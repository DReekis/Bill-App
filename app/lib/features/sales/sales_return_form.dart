import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class SalesReturnForm extends StatefulWidget {
  const SalesReturnForm({super.key, required this.invoice});
  final Invoice invoice;

  @override
  State<SalesReturnForm> createState() => _SalesReturnFormState();
}

class _SalesReturnFormState extends State<SalesReturnForm> {
  late List<InvoiceLine> itemsToReturn;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    itemsToReturn = widget.invoice.lines.map((l) => l.copyWith(quantity: 0)).toList();
  }

  int _total() {
    double t = 0;
    for (final l in itemsToReturn) {
      t += l.price * l.quantity;
    }
    return t.round();
  }

  Future<void> _save() async {
    final t = _total();
    if (t <= 0) {
      showAppMessage(context, 'Please select items to return', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = context.read<Session>().businessId!;
      final ret = TransactionReturn(
        businessId: bizId,
        number: 'RET-${DateTime.now().millisecondsSinceEpoch}',
        invoiceId: widget.invoice.id,
        partyId: widget.invoice.customerId,
        partyName: widget.invoice.customerName,
        partyType: 'customer',
        date: todayIso(),
        total: t,
        taxable: t, // Simplified
        lines: itemsToReturn.where((l) => l.quantity > 0).toList(),
      );
      await Repository.instance.finalizeReturn(ret);
      if (mounted) {
        showAppMessage(context, 'Sales Return recorded');
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
      appBar: AppBar(title: const Text('Sales Return')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: itemsToReturn.length,
              itemBuilder: (context, index) {
                final line = itemsToReturn[index];
                final maxQty = widget.invoice.lines[index].quantity;
                return ListTile(
                  title: Text(line.name),
                  subtitle: Text('Original Qty: $maxQty'),
                  trailing: SizedBox(
                    width: 120,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            if (line.quantity > 0) setState(() => line.quantity -= 1);
                          },
                        ),
                        Text('${line.quantity.round()}'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (line.quantity < maxQty) setState(() => line.quantity += 1);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Return Total: ${formatPaise(_total())}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: AsyncButton(label: 'Record Return', loading: saving, onPressed: _save),
            ),
          ),
        ],
      ),
    );
  }
}
