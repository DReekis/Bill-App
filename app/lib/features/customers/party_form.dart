import 'package:flutter/material.dart';

import '../../core/gst_service.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../sync/sync_engine.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class PartyFormSheet extends StatefulWidget {
  const PartyFormSheet({
    super.key,
    required this.onSaved,
    required this.businessId,
    this.customer,
    this.supplier,
    this.initialPartyType = 'customer',
    this.onSavedParty,
  });

  final Future<void> Function() onSaved;
  final int businessId;
  final Customer? customer;
  final Supplier? supplier;
  final String initialPartyType;
  final ValueChanged<dynamic>? onSavedParty;

  @override
  State<PartyFormSheet> createState() => _PartyFormSheetState();
}

class _PartyFormSheetState extends State<PartyFormSheet> {
  late String _partyType; // 'customer' or 'supplier'
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _billingAddress = TextEditingController();
  final _shippingAddress = TextEditingController();
  final _opening = TextEditingController();
  final _creditLimit = TextEditingController();

  bool _sameAsBilling = true;
  late int _paymentTerms;
  late int _creditPeriod;
  bool _isGstLoading = false;
  GstBusinessInfo? _gstInfo;
  bool _saving = false;

  bool get _isEdit => widget.customer != null || widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _partyType = widget.customer != null
        ? 'customer'
        : widget.supplier != null
            ? 'supplier'
            : widget.initialPartyType;

    _paymentTerms = widget.customer?.paymentTermsDays ?? 0;
    _creditPeriod = widget.supplier?.creditPeriodDays ?? 0;

    final c = widget.customer;
    final s = widget.supplier;

    if (c != null) {
      _name.text = c.name;
      _phone.text = c.phone ?? '';
      _email.text = c.email ?? '';
      _gstin.text = c.gstin ?? '';
      _pan.text = c.pan ?? '';
      _state.text = c.state ?? '';
      _city.text = c.city ?? '';
      _billingAddress.text = c.billingAddress ?? '';
      _shippingAddress.text = c.shippingAddress ?? c.billingAddress ?? '';
      _sameAsBilling = (c.shippingAddress == null ||
          c.shippingAddress!.isEmpty ||
          c.shippingAddress == c.billingAddress);
      _opening.text = c.openingBalance == 0
          ? ''
          : (c.openingBalance / 100).toStringAsFixed(2);
      _creditLimit.text =
          c.creditLimit == 0 ? '' : (c.creditLimit / 100).toStringAsFixed(2);
    } else if (s != null) {
      _name.text = s.name;
      _phone.text = s.phone ?? '';
      _email.text = s.email ?? '';
      _gstin.text = s.gstin ?? '';
      _pan.text = s.pan ?? '';
      _state.text = s.state ?? '';
      _billingAddress.text = s.address ?? '';
      _shippingAddress.text = s.address ?? '';
      _sameAsBilling = true;
      _opening.text = s.openingBalance == 0
          ? ''
          : (s.openingBalance / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _pan.dispose();
    _state.dispose();
    _city.dispose();
    _billingAddress.dispose();
    _shippingAddress.dispose();
    _opening.dispose();
    _creditLimit.dispose();
    super.dispose();
  }

  Future<void> _handleGstInput(String val, {bool force = false}) async {
    final clean = val.trim().toUpperCase();
    if (clean.length == 15 && GstService.isValidGstinFormat(clean)) {
      // Deterministically set PAN immediately from chars 2-11
      final extractedPan = clean.substring(2, 12);
      if (_pan.text.trim().isEmpty || force) {
        _pan.text = extractedPan;
      }

      setState(() => _isGstLoading = true);
      try {
        final info = await GstService.instance.lookup(clean);
        if (!mounted) return;
        setState(() {
          _gstInfo = info;
          if ((_state.text.trim().isEmpty || force) && info.state != null) {
            _state.text = info.state!;
          }
          if ((_name.text.trim().isEmpty || force) &&
              info.effectiveName.isNotEmpty) {
            _name.text = info.effectiveName;
          }
          if ((_pan.text.trim().isEmpty || force) && info.pan != null) {
            _pan.text = info.pan!;
          }
          if ((_city.text.trim().isEmpty || force) && info.city != null) {
            _city.text = info.city!;
          }
          if (info.address != null && info.address!.isNotEmpty) {
            if (_billingAddress.text.trim().isEmpty || force) {
              _billingAddress.text = info.address!;
            }
            if (_sameAsBilling &&
                (_shippingAddress.text.trim().isEmpty || force)) {
              _shippingAddress.text = info.address!;
            }
          }
        });
      } finally {
        if (mounted) setState(() => _isGstLoading = false);
      }
    } else if (clean.length < 15 && _gstInfo != null) {
      setState(() => _gstInfo = null);
    }
  }

  Future<void> _save() async {
    final partyName = _name.text.trim();
    if (partyName.isEmpty) {
      showAppMessage(context, 'Business / Party name is required', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final gstinVal =
          _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase();
      final panVal =
          _pan.text.trim().isEmpty ? null : _pan.text.trim().toUpperCase();
      final stateVal = _state.text.trim().isEmpty ? null : _state.text.trim();
      final cityVal = _city.text.trim().isEmpty ? null : _city.text.trim();
      final phoneVal = _phone.text.trim().isEmpty ? null : _phone.text.trim();
      final emailVal = _email.text.trim().isEmpty ? null : _email.text.trim();
      final billingVal = _billingAddress.text.trim().isEmpty
          ? null
          : _billingAddress.text.trim();
      final shippingVal = _sameAsBilling
          ? billingVal
          : (_shippingAddress.text.trim().isEmpty
              ? null
              : _shippingAddress.text.trim());

      if (_partyType == 'customer') {
        final customer = Customer(
          id: widget.customer?.id,
          name: partyName,
          phone: phoneVal,
          email: emailVal,
          gstin: gstinVal,
          pan: panVal,
          state: stateVal,
          city: cityVal,
          billingAddress: billingVal,
          shippingAddress: shippingVal,
          openingBalance: _toPaise(_opening.text),
          creditLimit: _toPaise(_creditLimit.text),
          paymentTermsDays: _paymentTerms,
        );
        final id = await Repository.instance.upsertCustomer(
          customer,
          businessIdOverride: widget.businessId,
        );
        final savedCustomer = Customer(
          id: widget.customer?.id ?? id,
          name: customer.name,
          phone: customer.phone,
          email: customer.email,
          gstin: customer.gstin,
          pan: customer.pan,
          state: customer.state,
          city: customer.city,
          billingAddress: customer.billingAddress,
          shippingAddress: customer.shippingAddress,
          openingBalance: customer.openingBalance,
          creditLimit: customer.creditLimit,
          paymentTermsDays: customer.paymentTermsDays,
        );
        widget.onSavedParty?.call(savedCustomer);
      } else {
        final supplier = Supplier(
          id: widget.supplier?.id,
          name: partyName,
          phone: phoneVal,
          email: emailVal,
          gstin: gstinVal,
          pan: panVal,
          state: stateVal,
          address: billingVal,
          openingBalance: _toPaise(_opening.text),
          creditPeriodDays: _creditPeriod,
        );
        final id = await Repository.instance.upsertSupplier(
          supplier,
          businessIdOverride: widget.businessId,
        );
        final savedSupplier = Supplier(
          id: widget.supplier?.id ?? id,
          name: supplier.name,
          phone: supplier.phone,
          email: supplier.email,
          gstin: supplier.gstin,
          pan: supplier.pan,
          state: supplier.state,
          address: supplier.address,
          openingBalance: supplier.openingBalance,
          creditPeriodDays: supplier.creditPeriodDays,
        );
        widget.onSavedParty?.call(savedSupplier);
      }

      await SyncEngine.instance.refreshPending();
      if (mounted) Navigator.of(context).pop();
      await widget.onSaved();
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save party: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCustomer = _partyType == 'customer';
    final isValidGstin = GstService.isValidGstinFormat(_gstin.text.trim().toUpperCase());

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Close
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (isCustomer ? const Color(0xFF00897B) : const Color(0xFFE65100)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCustomer ? Icons.people_alt_outlined : Icons.storefront_outlined,
                      color: isCustomer ? const Color(0xFF00897B) : const Color(0xFFE65100),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit
                          ? (isCustomer
                              ? (l10n.isHindi ? 'ग्राहक संपादित करें' : 'Edit Customer')
                              : (l10n.isHindi ? 'सप्लायर संपादित करें' : 'Edit Supplier'))
                          : l10n.text('add_party'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Party Type Selector (Customer vs Supplier)
              SegmentedButton<String>(
                showSelectedIcon: true,
                segments: [
                  ButtonSegment<String>(
                    value: 'customer',
                    icon: const Icon(Icons.person_outline_rounded, size: 18),
                    label: Text(l10n.text('customer')),
                  ),
                  ButtonSegment<String>(
                    value: 'supplier',
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: Text(l10n.text('supplier')),
                  ),
                ],
                selected: {_partyType},
                onSelectionChanged: _isEdit
                    ? null
                    : (set) {
                        if (set.isNotEmpty) {
                          setState(() => _partyType = set.first);
                        }
                      },
              ),
              const SizedBox(height: 18),

              // GST Auto-Fill Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isValidGstin ? StitchColors.success : StitchColors.outline.withValues(alpha: 0.7),
                    width: isValidGstin ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: isValidGstin ? StitchColors.success : StitchColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'GSTIN Details Auto-Fill',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        const Spacer(),
                        if (_isGstLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (isValidGstin)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 15),
                            label: const Text('Re-fill', style: TextStyle(fontSize: 12)),
                            onPressed: () => _handleGstInput(_gstin.text, force: true),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _gstin,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'GSTIN (15 Alphanumeric)',
                        hintText: 'e.g. 27AABCS1429B1Z5',
                        suffixIcon: isValidGstin
                            ? const Icon(Icons.check_circle_rounded, color: StitchColors.success)
                            : null,
                      ),
                      onChanged: (val) => _handleGstInput(val),
                    ),
                    if (_gstInfo != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: StitchColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_rounded, size: 12, color: StitchColors.success),
                                const SizedBox(width: 4),
                                Text(
                                  _gstInfo!.state ?? 'Verified',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: StitchColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_gstInfo!.constitution != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: StitchColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _gstInfo!.constitution!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: StitchColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Business Name & PAN
              AppTextField(
                controller: _name,
                label: isCustomer ? 'Customer / Business name *' : 'Supplier / Business name *',
                hint: 'Official Trade or Registered Name',
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pan,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'PAN No',
                        hintText: 'e.g. AABCS1429B',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: _phone,
                      label: 'Phone number',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              AppTextField(
                controller: _email,
                label: 'Email address',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // Addresses Section
              const Text(
                'Address & Location',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _state,
                      label: 'State',
                      hint: 'State / Union Territory',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: _city,
                      label: 'City / District',
                      hint: 'City',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              AppTextField(
                controller: _billingAddress,
                label: isCustomer ? 'Billing address' : 'Registered address',
                maxLines: 2,
                onChanged: (val) {
                  if (_sameAsBilling) {
                    _shippingAddress.text = val;
                  }
                },
              ),
              const SizedBox(height: 6),

              // Shipping Address Toggle (for Customers)
              if (isCustomer) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Shipping address same as billing address',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  value: _sameAsBilling,
                  onChanged: (val) {
                    final checked = val ?? true;
                    setState(() {
                      _sameAsBilling = checked;
                      if (checked) {
                        _shippingAddress.text = _billingAddress.text;
                      }
                    });
                  },
                ),
                if (!_sameAsBilling) ...[
                  const SizedBox(height: 4),
                  AppTextField(
                    controller: _shippingAddress,
                    label: 'Shipping / Delivery address',
                    maxLines: 2,
                  ),
                ],
                const SizedBox(height: 10),
              ],

              const Divider(height: 24),

              // Financial & Credit Terms
              const Text(
                'Credit & Financial Terms',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: AppAmountField(
                      controller: _opening,
                      label: 'Opening balance',
                    ),
                  ),
                  if (isCustomer) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppAmountField(
                        controller: _creditLimit,
                        label: 'Credit limit',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              if (isCustomer)
                DropdownButtonFormField<int>(
                  initialValue: _paymentTerms,
                  decoration: inputDecoration('Credit / payment terms'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('None (Spot / immediate)')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 15, child: Text('15 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 45, child: Text('45 days')),
                    DropdownMenuItem(value: 60, child: Text('60 days')),
                  ],
                  onChanged: (v) => _paymentTerms = v ?? 0,
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _creditPeriod,
                  decoration: inputDecoration('Supplier credit period'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('None (Spot payment)')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 15, child: Text('15 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 45, child: Text('45 days')),
                    DropdownMenuItem(value: 60, child: Text('60 days')),
                  ],
                  onChanged: (v) => _creditPeriod = v ?? 0,
                ),

              const SizedBox(height: 24),

              // Save Action Button
              SizedBox(
                width: double.infinity,
                child: AsyncButton(
                  loading: _saving,
                  label: _isEdit
                      ? 'Save Changes'
                      : (isCustomer ? 'Add Customer' : 'Add Supplier'),
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
