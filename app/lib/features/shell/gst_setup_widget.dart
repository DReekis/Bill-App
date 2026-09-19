import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/gst_service.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class GSTSetupCard extends StatefulWidget {
  const GSTSetupCard({super.key, this.business});
  final Business? business;

  @override
  State<GSTSetupCard> createState() => _GSTSetupCardState();
}

class _GSTSetupCardState extends State<GSTSetupCard> {
  late TextEditingController _gstin;
  bool _saving = false;
  bool _lookingUp = false;
  GstBusinessInfo? _info;

  @override
  void initState() {
    super.initState();
    _gstin = TextEditingController(text: widget.business?.gstin ?? '');
  }

  @override
  void dispose() {
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _checkGst(String val) async {
    final clean = val.trim().toUpperCase();
    if (clean.length == 15) {
      setState(() => _lookingUp = true);
      try {
        final res = await GstService.instance.lookup(clean);
        if (mounted) setState(() => _info = res);
      } finally {
        if (mounted) setState(() => _lookingUp = false);
      }
    } else if (_info != null) {
      setState(() => _info = null);
    }
  }

  Future<void> _saveGST() async {
    final gst = _gstin.text.trim().toUpperCase();
    if (gst.isEmpty) {
      showAppMessage(context, 'Please enter GSTIN', error: true);
      return;
    }
    if (gst.length != 15) {
      showAppMessage(context, 'GSTIN must be 15 characters', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final b = widget.business;
      if (b == null) return;

      final info = _info ?? await GstService.instance.lookup(gst);

      final updated = Business(
        id: b.id,
        name: (b.name.isEmpty || b.name == 'My Business') && info.effectiveName.isNotEmpty ? info.effectiveName : b.name,
        ownerName: b.ownerName ?? (info.effectiveOwner.isNotEmpty ? info.effectiveOwner : null),
        gstin: gst,
        state: info.state ?? b.state,
        city: info.city ?? b.city,
        industry: info.industry ?? b.industry,
        invoicePrefix: b.invoicePrefix,
        taxRegistered: true,
        allowNegativeStock: b.allowNegativeStock,
        invoiceSequence: b.invoiceSequence,
        fyStart: b.fyStart,
        currency: b.currency,
      );

      await Repository.instance.updateBusiness(updated, businessIdOverride: b.id);
      if (mounted) {
        showAppMessage(context, 'GST number saved and tax enabled');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return showGSTPrompt
        ? Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StitchColors.primaryContainer.withValues(alpha: 0.5),
              border: Border.all(color: StitchColors.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: StitchColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Your GST Number',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Enable tax calculation on invoices',
                            style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gstin,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: '18AABCU9603R1Z0',
                    labelText: 'GSTIN (15 characters)',
                    prefixIcon: const Icon(Icons.verified_outlined),
                    suffixIcon: _lookingUp
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    helperText: 'Format: 2-digit state + 10-digit ID + Z',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLength: 15,
                  onChanged: (v) {
                    setState(() {});
                    _checkGst(v);
                  },
                ),
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: StitchColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: StitchColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: StitchColors.success),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _info!.effectiveName.isNotEmpty
                                ? '${_info!.effectiveName} • ${_info!.state ?? ""}'
                                : 'Identified: ${_info!.constitution ?? ""} (${_info!.state ?? ""})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.success),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving || _gstin.text.trim().isEmpty ? null : _saveGST,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Save & Enable Tax'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StitchColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        : const SizedBox.shrink();
  }

  bool get showGSTPrompt => widget.business?.gstin == null || widget.business!.gstin!.isEmpty;
}

/// Dialog for quick GST setup
class QuickGSTSetupDialog extends StatefulWidget {
  const QuickGSTSetupDialog({super.key});

  @override
  State<QuickGSTSetupDialog> createState() => _QuickGSTSetupDialogState();
}

class _QuickGSTSetupDialogState extends State<QuickGSTSetupDialog> {
  late TextEditingController _gstin;
  bool _saving = false;
  bool _lookingUp = false;
  GstBusinessInfo? _info;

  @override
  void initState() {
    super.initState();
    _gstin = TextEditingController();
  }

  @override
  void dispose() {
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _checkGst(String val) async {
    final clean = val.trim().toUpperCase();
    if (clean.length == 15) {
      setState(() => _lookingUp = true);
      try {
        final res = await GstService.instance.lookup(clean);
        if (mounted) setState(() => _info = res);
      } finally {
        if (mounted) setState(() => _lookingUp = false);
      }
    } else if (_info != null) {
      setState(() => _info = null);
    }
  }

  Future<void> _save() async {
    final gst = _gstin.text.trim().toUpperCase();
    if (gst.isEmpty) {
      showAppMessage(context, 'Please enter GSTIN', error: true);
      return;
    }
    if (gst.length != 15) {
      showAppMessage(context, 'GSTIN must be 15 characters', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final session = context.read<Session>();
      final businessId = session.businessId;
      if (businessId == null) return;

      final b = await Repository.instance.getBusiness(businessId);
      if (b == null) return;

      final info = _info ?? await GstService.instance.lookup(gst);

      final updated = Business(
        id: b.id,
        name: (b.name.isEmpty || b.name == 'My Business') && info.effectiveName.isNotEmpty ? info.effectiveName : b.name,
        ownerName: b.ownerName ?? (info.effectiveOwner.isNotEmpty ? info.effectiveOwner : null),
        gstin: gst,
        state: info.state ?? b.state,
        city: info.city ?? b.city,
        industry: info.industry ?? b.industry,
        invoicePrefix: b.invoicePrefix,
        taxRegistered: true,
        allowNegativeStock: b.allowNegativeStock,
        invoiceSequence: b.invoiceSequence,
        fyStart: b.fyStart,
        currency: b.currency,
      );

      await Repository.instance.updateBusiness(updated, businessIdOverride: b.id);
      if (mounted) {
        Navigator.pop(context, true);
        showAppMessage(context, 'GST number saved! Tax is now enabled.');
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add GST Number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enable tax calculation on your invoices by adding your GST number.',
            style: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _gstin,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: '18AABCU9603R1Z0',
              labelText: 'GSTIN',
              prefixIcon: const Icon(Icons.verified_outlined),
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              helperText: '15-character GSTIN',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLength: 15,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) {
              setState(() {});
              _checkGst(v);
            },
          ),
          if (_info != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: StitchColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StitchColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: StitchColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _info!.effectiveName.isNotEmpty
                          ? '${_info!.effectiveName} • ${_info!.state ?? ""}'
                          : 'Identified: ${_info!.constitution ?? ""} (${_info!.state ?? ""})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving || _gstin.text.trim().isEmpty ? null : _save,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StitchColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
