import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/gst_service.dart';
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

  bool fetchingGst = false;
  String? gstStatusMessage;

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

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _gstin.dispose();
    _state.dispose();
    _city.dispose();
    _prefix.dispose();
    _upiId.dispose();
    super.dispose();
  }

  Future<void> _fetchGstDetails([String? specificGstin]) async {
    final target = (specificGstin ?? _gstin.text).trim().toUpperCase();
    if (target.isEmpty) return;
    if (target.length != 15) {
      showAppMessage(context, 'GSTIN must be 15 characters', error: true);
      return;
    }

    setState(() {
      fetchingGst = true;
      gstStatusMessage = null;
    });

    try {
      final session = context.read<Session>();
      final client = session.token != null ? (ApiClient()..setToken(session.token!)) : null;
      final info = await GstService.instance.lookup(target, apiClient: client);
      if (!mounted) return;

      setState(() {
        // State is always reliably derived from the GSTIN prefix
        if (info.state != null && info.state!.isNotEmpty) {
          _state.text = info.state!;
        }
        taxRegistered = true;

        // Only fill name, owner, city from real online-fetched data
        if (info.isOnlineFetched) {
          if (info.effectiveName.isNotEmpty) {
            _name.text = info.effectiveName;
          }
          if (info.effectiveOwner.isNotEmpty) {
            _owner.text = info.effectiveOwner;
          }
          if (info.city != null && info.city!.isNotEmpty) {
            _city.text = info.city!;
          }
          gstStatusMessage = '✓ Verified GSTIN (${info.status} • ${info.state ?? "India"})';
        } else {
          gstStatusMessage = '✓ Format valid (${info.constitution ?? "GST Registered"} • ${info.state ?? "India"}) — enter name & address manually';
        }
      });

      if (info.isOnlineFetched && info.effectiveName.isNotEmpty) {
        showAppMessage(
          context,
          'Business details loaded for ${info.effectiveName}',
        );
      } else {
        showAppMessage(
          context,
          'State auto-filled from GSTIN. Please enter business name and address.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => gstStatusMessage = 'Could not auto-fill: $e');
      }
    } finally {
      if (mounted) setState(() => fetchingGst = false);
    }
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
                if (widget.isNew) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StitchColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: StitchColors.primary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Enter your GST number below to auto-fill business name, owner & state!',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: StitchColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                AppTextField(
                  controller: _gstin,
                  label: 'GSTIN (15 characters)',
                  hint: 'e.g. 29AAAAA0000A1Z5',
                  onChanged: (v) {
                    final clean = v.trim().toUpperCase();
                    if (clean.length == 15) {
                      _fetchGstDetails(clean);
                    } else if (gstStatusMessage != null) {
                      setState(() => gstStatusMessage = null);
                    }
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return GstService.isValidGstinFormat(v.trim()) ? null : 'Invalid GSTIN format';
                  },
                ),
                if (gstStatusMessage != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      gstStatusMessage!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.success),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AppTextField(controller: _name, label: 'Business name *'),
                const SizedBox(height: 12),
                AppTextField(controller: _owner, label: 'Owner name'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: AppTextField(controller: _state, label: 'State')),
                  const SizedBox(width: 12),
                  Expanded(child: AppTextField(controller: _city, label: 'City')),
                ]),
                const SizedBox(height: 12),
                AppTextField(controller: _prefix, label: 'Invoice prefix', hint: 'INV'),
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