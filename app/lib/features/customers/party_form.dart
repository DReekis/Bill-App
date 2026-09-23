import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/gst_service.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
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
  bool _showAutofillSuccessBanner = false;

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

  Future<void> _handleGstInput(String raw, {bool force = false}) async {
    final clean = raw.trim().toUpperCase();
    if (clean.length == 15 && GstService.isValidGstinFormat(clean)) {
      final extractedPan = clean.substring(2, 12);
      if (_pan.text.trim().isEmpty || force) {
        _pan.text = extractedPan;
      }

      final prevAutoName = _gstInfo?.effectiveName;
      final prevAutoAddress = _gstInfo?.address;
      final prevAutoCity = _gstInfo?.city;

      setState(() => _isGstLoading = true);
      try {
        final session = context.read<Session>();
        final info = await GstService.instance.lookup(
          clean,
          gstnApiKey: session.gstnApiKey.isNotEmpty ? session.gstnApiKey : null,
        );
        if (!mounted) return;
        setState(() {
          _gstInfo = info;
          if ((_state.text.trim().isEmpty || force) && info.state != null) {
            _state.text = info.state!;
          }
          if ((_pan.text.trim().isEmpty || force) && (info.pan != null || extractedPan.isNotEmpty)) {
            _pan.text = info.pan ?? extractedPan;
          }
          if ((_name.text.trim().isEmpty || force || _name.text == prevAutoName) &&
              info.effectiveName.isNotEmpty) {
            _name.text = info.effectiveName;
          }
          if ((_city.text.trim().isEmpty || force || _city.text == prevAutoCity) &&
              info.city != null && info.city!.isNotEmpty) {
            _city.text = info.city!;
          }
          if (info.address != null && info.address!.isNotEmpty) {
            if (_billingAddress.text.trim().isEmpty || force || _billingAddress.text == prevAutoAddress) {
              _billingAddress.text = info.address!;
            }
            if (_sameAsBilling || _shippingAddress.text.trim().isEmpty || force || _shippingAddress.text == prevAutoAddress) {
              _shippingAddress.text = info.address!;
            }
          }
          _showAutofillSuccessBanner = true;
        });

        if (info.effectiveName.isNotEmpty) {
          showAppMessage(context, 'Party details auto-filled from GSTIN ✓');
        }
      } finally {
        if (mounted) setState(() => _isGstLoading = false);
      }
    } else if (clean.length < 15 && _gstInfo != null) {
      setState(() {
        _gstInfo = null;
        _showAutofillSuccessBanner = false;
      });
    }
  }

  Future<void> _save() async {
    final partyName = _name.text.trim();
    if (partyName.isEmpty) {
      showAppMessage(context, 'Party name is required', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final gstinVal = _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase();
      final panVal = _pan.text.trim().isEmpty ? null : _pan.text.trim().toUpperCase();
      final stateVal = _state.text.trim().isEmpty ? null : _state.text.trim();
      final cityVal = _city.text.trim().isEmpty ? null : _city.text.trim();
      final phoneVal = _phone.text.trim().isEmpty ? null : _phone.text.trim();
      final emailVal = _email.text.trim().isEmpty ? null : _email.text.trim();
      final billingVal = _billingAddress.text.trim().isEmpty ? null : _billingAddress.text.trim();
      final shippingVal = _sameAsBilling
          ? billingVal
          : (_shippingAddress.text.trim().isEmpty ? null : _shippingAddress.text.trim());

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

  Widget _buildPartyTypePill(String type, String label) {
    final isSelected = _partyType == type;
    return InkWell(
      onTap: _isEdit ? null : () => setState(() => _partyType = type),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? StitchColors.primary : StitchColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? StitchColors.primary : StitchColors.outline,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : StitchColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = _partyType == 'customer';
    final isValidGstin = GstService.isValidGstinFormat(_gstin.text.trim().toUpperCase());

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: StitchColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Top Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. Pinned Header Row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCustomer ? Icons.person_rounded : Icons.store_rounded,
                        color: StitchColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEdit
                            ? (isCustomer ? 'Edit Customer' : 'Edit Supplier')
                            : (isCustomer ? 'Add Customer' : 'Add Supplier'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                      ),
                    ),
                    _buildPartyTypePill('customer', 'Customer'),
                    const SizedBox(width: 6),
                    _buildPartyTypePill('supplier', 'Supplier'),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 3. Scrollable Unified Form
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Autofill Success Notification Banner
                      if (_showAutofillSuccessBanner) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: StitchColors.successSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StitchColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: StitchColors.success, size: 16),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Party details auto-filled from GSTIN',
                                  style: TextStyle(
                                    color: StitchColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _showAutofillSuccessBanner = false),
                                child: const Icon(Icons.close_rounded, color: StitchColors.success, size: 16),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Party Name* (Required)
                      AppTextField(
                        controller: _name,
                        label: isCustomer ? 'Customer Name *' : 'Supplier / Party Name *',
                        hint: 'e.g. Sharma Traders',
                        icon: Icons.business_outlined,
                      ),
                      const SizedBox(height: 14),

                      // Phone & Email Row
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _phone,
                              label: 'Phone Number',
                              hint: 'e.g. 9876543210',
                              keyboardType: TextInputType.phone,
                              icon: Icons.phone_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _email,
                              label: 'Email (Optional)',
                              hint: 'e.g. info@domain.com',
                              keyboardType: TextInputType.emailAddress,
                              icon: Icons.mail_outline_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // GSTIN Field with Live Lookup Indicator
                      TextFormField(
                        controller: _gstin,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        decoration: InputDecoration(
                          labelText: 'GSTIN (Optional)',
                          hintText: 'e.g. 29AAAAA0000A1Z5',
                          prefixIcon: const Icon(Icons.receipt_long_outlined, size: 20),
                          suffixIcon: _isGstLoading
                              ? const UnconstrainedBox(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : isValidGstin
                                  ? const Icon(Icons.check_circle_rounded, color: StitchColors.success)
                                  : null,
                        ),
                        onChanged: (val) => _handleGstInput(val),
                      ),

                      // Verified Taxpayer Info Strip
                      if (_gstInfo != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: StitchColors.successSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StitchColors.success.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user_rounded, color: StitchColors.success, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_gstInfo!.status} • ${_gstInfo!.state ?? ''}${_gstInfo!.constitution != null ? ' • ${_gstInfo!.constitution}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: StitchColors.success,
                                  ),
                                ),
                              ),
                              if (isValidGstin)
                                GestureDetector(
                                  onTap: () => _handleGstInput(_gstin.text, force: true),
                                  child: const Text(
                                    'Re-fill',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: StitchColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // PAN & State Row
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _pan,
                              label: 'PAN Number',
                              hint: 'e.g. AABCS1429B',
                              icon: Icons.badge_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _state,
                              label: 'State',
                              hint: 'e.g. Karnataka',
                              icon: Icons.map_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Billing Address
                      AppTextField(
                        controller: _billingAddress,
                        label: 'Billing Address',
                        hint: 'Building, Street, Area, City, PIN',
                        maxLines: 2,
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 8),

                      // Shipping Address Checkbox
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _sameAsBilling,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              activeColor: StitchColors.primary,
                              onChanged: (val) {
                                setState(() {
                                  _sameAsBilling = val ?? true;
                                  if (_sameAsBilling) {
                                    _shippingAddress.text = _billingAddress.text;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _sameAsBilling = !_sameAsBilling;
                                if (_sameAsBilling) {
                                  _shippingAddress.text = _billingAddress.text;
                                }
                              });
                            },
                            child: const Text(
                              'Shipping address same as billing address',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: StitchColors.textPrimary),
                            ),
                          ),
                        ],
                      ),

                      // Separate Shipping Address (if unchecked)
                      if (!_sameAsBilling) ...[
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _shippingAddress,
                          label: 'Shipping Address',
                          hint: 'Delivery address with City & PIN',
                          maxLines: 2,
                          icon: Icons.local_shipping_outlined,
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Opening Balance & Credit Limit
                      Row(
                        children: [
                          Expanded(
                            child: AppAmountField(
                              controller: _opening,
                              label: 'Opening balance',
                              hintText: '0.00',
                            ),
                          ),
                          if (isCustomer) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppAmountField(
                                controller: _creditLimit,
                                label: 'Credit limit',
                                hintText: '0.00',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Credit / Payment Terms Dropdown
                      DropdownButtonFormField<int>(
                        key: ValueKey(_paymentTerms),
                        initialValue: isCustomer ? _paymentTerms : _creditPeriod,
                        decoration: inputDecoration(isCustomer ? 'Credit / payment terms' : 'Credit period').copyWith(
                          prefixIcon: const Icon(Icons.schedule_rounded, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('None (Spot / immediate)')),
                          DropdownMenuItem(value: 7, child: Text('7 days')),
                          DropdownMenuItem(value: 15, child: Text('15 days')),
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 45, child: Text('45 days')),
                          DropdownMenuItem(value: 60, child: Text('60 days')),
                        ],
                        onChanged: (v) {
                          final val = v ?? 0;
                          setState(() {
                            if (isCustomer) {
                              _paymentTerms = val;
                            } else {
                              _creditPeriod = val;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Pinned Bottom Save Button Bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: BoxDecoration(
                  color: StitchColors.background,
                  border: Border(top: BorderSide(color: StitchColors.outline.withValues(alpha: 0.8))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: AsyncButton(
                    loading: _saving,
                    label: _isEdit
                        ? 'Save Changes'
                        : (isCustomer ? 'Add Customer' : 'Add Supplier'),
                    onPressed: _save,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
