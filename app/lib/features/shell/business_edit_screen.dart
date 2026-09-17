import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class BusinessEditScreen extends StatefulWidget {
  const BusinessEditScreen({super.key, this.businessId, this.isNew = false});
  final int? businessId;
  final bool isNew;

  @override
  State<BusinessEditScreen> createState() => _BusinessEditScreenState();
}

class _BusinessEditScreenState extends State<BusinessEditScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _gstin = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _prefix = TextEditingController(text: 'INV');
  final _upiId = TextEditingController();
  Business? business;
  bool saving = false;
  bool taxRegistered = true;

  Future<void> _load() async {
    if (widget.isNew) {
      // New business default template
      setState(() {
        business = Business(
          name: '',
          invoicePrefix: 'INV',
          taxRegistered: true,
        );
      });
      return;
    }

    final targetId = widget.businessId ?? context.read<Session>().businessId;
    if (targetId == null) return;
    final b = await Repository.instance.getBusiness(targetId);
    if (!mounted) return;
    setState(() {
      business = b;
      if (b != null) {
        _name.text = b.name;
        _owner.text = b.ownerName ?? '';
        _gstin.text = b.gstin ?? '';
        _state.text = b.state ?? '';
        _city.text = b.city ?? '';
        _prefix.text = b.invoicePrefix;
        _upiId.text = b.upiId ?? '';
        taxRegistered = b.taxRegistered;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppMessage(context, 'Business name is required', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      if (widget.isNew) {
        final newBiz = Business(
          name: _name.text.trim(),
          ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
          gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase(),
          state: _state.text.trim().isEmpty ? null : _state.text.trim(),
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          industry: 'Retail',
          upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
          invoicePrefix: _prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim(),
          taxRegistered: taxRegistered,
          allowNegativeStock: true,
          invoiceSequence: 1,
          fyStart: '04-01',
          currency: 'INR',
        );
        final newId = await Repository.instance.createBusiness(newBiz);
        if (!mounted) return;
        await context.read<Session>().switchBusiness(newId);
        if (!mounted) return;
        showAppMessage(context, 'Business created successfully');
        Navigator.of(context).pop(true);
      } else {
        final b = business;
        if (b == null) return;
        final updated = Business(
          id: b.id,
          name: _name.text.trim(),
          ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
          gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase(),
          state: _state.text.trim().isEmpty ? null : _state.text.trim(),
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          industry: b.industry,
          upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
          invoicePrefix: _prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim(),
          taxRegistered: taxRegistered,
          allowNegativeStock: b.allowNegativeStock,
          invoiceSequence: b.invoiceSequence,
          fyStart: b.fyStart,
          currency: b.currency,
        );
        await Repository.instance.updateBusiness(updated, businessIdOverride: b.id);
        if (mounted) {
          showAppMessage(context, 'Business updated');
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'Create business' : 'Business profile'),
        ),
        body: business == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : ListView(padding: const EdgeInsets.all(16), children: [
                AppTextField(controller: _name, label: 'Business name *'),
                const SizedBox(height: 12),
                AppTextField(controller: _owner, label: 'Owner name'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: AppTextField(controller: _gstin, label: 'GSTIN')),
                  const SizedBox(width: 12),
                  Expanded(child: AppTextField(controller: _prefix, label: 'Invoice prefix')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: AppTextField(controller: _state, label: 'State')),
                  const SizedBox(width: 12),
                  Expanded(child: AppTextField(controller: _city, label: 'City')),
                ]),
                const SizedBox(height: 12),
                AppTextField(controller: _upiId, label: 'UPI VPA (for QR payment, e.g. store@upi)'),
                const SizedBox(height: 8),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: SwitchListTile(
                    value: taxRegistered,
                    onChanged: (v) => setState(() => taxRegistered = v),
                    title: const Text('GST registered', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Shows GSTIN and charges tax on invoices', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AsyncButton(
                    loading: saving,
                    label: widget.isNew ? 'Create business' : 'Save changes',
                    onPressed: _save,
                  ),
                ),
                if (!widget.isNew) ...[
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () => context.read<Session>().logout(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out & switch business'),
                    style: TextButton.styleFrom(foregroundColor: StitchColors.error),
                  ),
                ],
              ]),
      );
}