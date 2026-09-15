import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class BankTransferForm extends StatefulWidget {
  const BankTransferForm({super.key});

  @override
  State<BankTransferForm> createState() => _BankTransferFormState();
}

class _BankTransferFormState extends State<BankTransferForm> {
  List<BankAccount>? accounts;
  int? fromId;
  int? toId;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId!;
    final list = await Repository.instance.bankAccounts(bizId);
    setState(() => accounts = list);
  }

  Future<void> _save() async {
    if (fromId == null || toId == null || fromId == toId) {
      showAppMessage(context, 'Select different accounts', error: true);
      return;
    }
    final amt = _toPaise(_amount.text);
    if (amt <= 0) {
      showAppMessage(context, 'Invalid amount', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      await Repository.instance.recordBankTransfer(
        fromAccountId: fromId!,
        toAccountId: toId!,
        amount: amt,
        date: todayIso(),
        note: _note.text.trim(),
      );
      if (mounted) {
        showAppMessage(context, 'Transfer recorded');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error: $e', error: true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Inter-bank Transfer')),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'From Account'),
                  items: accounts?.map((a) => DropdownMenuItem(value: a.id, child: Text(a.bankName))).toList(),
                  onChanged: (v) => setState(() => fromId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'To Account'),
                  items: accounts?.map((a) => DropdownMenuItem(value: a.id, child: Text(a.bankName))).toList(),
                  onChanged: (v) => setState(() => toId = v),
                ),
                const SizedBox(height: 16),
                AppAmountField(controller: _amount, label: 'Amount'),
                const SizedBox(height: 16),
                AppTextField(controller: _note, label: 'Note'),
                const Spacer(),
                SizedBox(width: double.infinity, child: AsyncButton(label: 'Record Transfer', loading: saving, onPressed: _save)),
              ]),
            ),
    );
  }
}
