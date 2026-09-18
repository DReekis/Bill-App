import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class ExpenseFormSheet extends StatefulWidget {
  const ExpenseFormSheet({super.key, required this.onSaved, required this.businessId});
  final Future<void> Function() onSaved;
  final int businessId;
  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _vendor = TextEditingController();
  String? category;
  String? mode;
  String date = todayIso();
  bool saving = false;

  Future<void> _save() async {
    final amount = _toPaise(_amount.text);
    if (amount <= 0) {
      showAppMessage(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Repository.instance.recordExpense(
        businessId: widget.businessId,
        category: category ?? 'Other',
        amount: amount,
        mode: mode ?? 'Cash',
        date: date,
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
      await widget.onSaved();
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Record expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 8),
            AppAmountField(controller: _amount, label: 'Amount (₹) *'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: 'Other',
              decoration: inputDecoration('Category *'),
              items: expenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => category = v,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: 'Cash',
                  decoration: inputDecoration('Paid via'),
                  items: paymentModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => mode = v,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDateField(
                  date: date,
                  label: 'Date',
                  onDateSelected: (d) => setState(() => date = d),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            AppTextField(controller: _description, label: 'Description'),
            const SizedBox(height: 12),
            AppTextField(controller: _vendor, label: 'Vendor / party (optional)'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AsyncButton(loading: saving, label: 'Save expense', onPressed: _save),
            ),
          ]),
        ),
      ),
    );
  }
}