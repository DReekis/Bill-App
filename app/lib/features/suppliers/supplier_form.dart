import 'package:flutter/material.dart';

import '../../core/gst_service.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class SupplierFormSheet extends StatefulWidget {
  const SupplierFormSheet({super.key, required this.onSaved, required this.businessId, this.supplier});
  final Future<void> Function() onSaved;
  final int businessId;
  final Supplier? supplier;
  @override
  State<SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<SupplierFormSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _state = TextEditingController();
  final _address = TextEditingController();
  final _opening = TextEditingController();
  int creditPeriod = 0;
  bool saving = false;

  Future<void> _checkGst(String val) async {
    final clean = val.trim().toUpperCase();
    if (clean.length == 15 && GstService.isValidGstinFormat(clean)) {
      final info = await GstService.instance.lookup(clean);
      if (!mounted) return;
      setState(() {
        if (_state.text.trim().isEmpty && info.state != null) {
          _state.text = info.state!;
        }
        if (_name.text.trim().isEmpty && info.effectiveName.isNotEmpty) {
          _name.text = info.effectiveName;
        }
        if (_address.text.trim().isEmpty && info.address != null && info.address!.isNotEmpty) {
          _address.text = info.address!;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    creditPeriod = widget.supplier?.creditPeriodDays ?? 0;
    final s = widget.supplier;
    if (s != null) {
      _name.text = s.name;
      _phone.text = s.phone ?? '';
      _email.text = s.email ?? '';
      _gstin.text = s.gstin ?? '';
      _state.text = s.state ?? '';
      _address.text = s.address ?? '';
      _opening.text = s.openingBalance == 0 ? '' : (s.openingBalance / 100).toStringAsFixed(2);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppMessage(context, 'Supplier name is required', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await Repository.instance.upsertSupplier(Supplier(
        id: widget.supplier?.id,
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase(),
        state: _state.text.trim().isEmpty ? null : _state.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        openingBalance: _toPaise(_opening.text),
        creditPeriodDays: creditPeriod,
      ), businessIdOverride: widget.businessId);
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
    final supplier = widget.supplier;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(supplier == null ? 'Add supplier' : 'Edit supplier',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 8),
            AppTextField(controller: _name, label: 'Supplier name *'),
            const SizedBox(height: 12),
            AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            AppTextField(controller: _email, label: 'Email', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AppTextField(
                  controller: _gstin,
                  label: 'GSTIN',
                  onChanged: _checkGst,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(controller: _state, label: 'State')),
            ]),
            const SizedBox(height: 12),
            AppTextField(controller: _address, label: 'Address', maxLines: 2),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppAmountField(controller: _opening, label: 'Opening balance')),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: creditPeriod,
                  decoration: inputDecoration('Credit period'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('None')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 15, child: Text('15 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (v) => creditPeriod = v ?? 0,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AsyncButton(
                loading: saving,
                label: supplier == null ? 'Add supplier' : 'Save changes',
                onPressed: _save,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}