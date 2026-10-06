import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../../utils/widgets.dart';
import 'invoice_customization_screen.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key, this.businessId});
  final int? businessId;

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Numbering
  final _invPrefix = TextEditingController(text: 'INV');
  final _invSequence = TextEditingController(text: '0');
  final _quotePrefix = TextEditingController(text: 'EST');
  final _quoteSequence = TextEditingController(text: '0');
  final _purchasePrefix = TextEditingController(text: 'PUR');
  final _purchaseSequence = TextEditingController(text: '0');

  // Contact & Address on invoices
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pinCode = TextEditingController();
  final _invoicePhone = TextEditingController();
  final _invoiceEmail = TextEditingController();

  // Terms and Conditions per document type
  String _selectedDocType = 'sales';
  final _termsSales = TextEditingController();
  final _termsQuotation = TextEditingController();
  final _termsPurchase = TextEditingController();
  final _termsChallan = TextEditingController();

  // Signature
  String? _signaturePath;
  final _signatureText = TextEditingController(text: 'Authorised Signatory');
  bool _showEmptySignatureBox = true;

  // Payment QR & Bank
  final _upiId = TextEditingController();
  bool _showPaymentQr = true;
  int? _selectedBankAccountId;
  List<BankAccount> _bankAccounts = [];

  Business? _business;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invPrefix.dispose();
    _invSequence.dispose();
    _quotePrefix.dispose();
    _quoteSequence.dispose();
    _purchasePrefix.dispose();
    _purchaseSequence.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pinCode.dispose();
    _invoicePhone.dispose();
    _invoiceEmail.dispose();
    _termsSales.dispose();
    _termsQuotation.dispose();
    _termsPurchase.dispose();
    _termsChallan.dispose();
    _signatureText.dispose();
    _upiId.dispose();
    super.dispose();
  }

  int get _bizId =>
      widget.businessId ?? context.read<Session>().businessId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = Repository.instance;
    final b = await repo.getBusiness(_bizId);
    final banks = await repo.bankAccounts(_bizId);

    if (!mounted) return;
    setState(() {
      _business = b;
      _bankAccounts = banks;
      if (b != null) {
        _invPrefix.text = b.invoicePrefix;
        _invSequence.text = b.invoiceSequence.toString();
        _quotePrefix.text = b.quotationPrefix;
        _quoteSequence.text = b.quotationSequence.toString();
        _purchasePrefix.text = b.purchasePrefix;
        _purchaseSequence.text = b.purchaseSequence.toString();

        _address.text = b.address ?? '';
        _city.text = b.city ?? '';
        _state.text = b.state ?? '';
        _pinCode.text = b.pinCode ?? '';
        _invoicePhone.text = b.invoicePhone ?? b.phone ?? '';
        _invoiceEmail.text = b.invoiceEmail ?? b.email ?? '';

        _termsSales.text = b.termsSales ?? _defaultSalesTerms();
        _termsQuotation.text = b.termsQuotation ?? _defaultQuotationTerms();
        _termsPurchase.text = b.termsPurchase ?? _defaultPurchaseTerms();
        _termsChallan.text = b.termsChallan ?? _defaultChallanTerms();

        _signaturePath = b.signaturePath;
        _signatureText.text = b.signatureText.isNotEmpty ? b.signatureText : 'Authorised Signatory';
        _showEmptySignatureBox = b.showEmptySignatureBox;

        _upiId.text = b.upiId ?? '';
        _showPaymentQr = b.showPaymentQr;
        _selectedBankAccountId = b.bankAccountId ?? (banks.isNotEmpty ? banks.first.id : null);
      }
      _loading = false;
    });
  }

  String _defaultSalesTerms() =>
      '1. Goods once sold will not be taken back or exchanged.\n'
      '2. Payment is due within the agreed credit period.\n'
      '3. Interest @ 18% p.a. will be charged for delayed payments.\n'
      '4. Any dispute is subject to local jurisdiction.';

  String _defaultQuotationTerms() =>
      '1. Quotation is valid for 15 days from the date of issue.\n'
      '2. 50% advance payment required upon order confirmation.\n'
      '3. Delivery schedule commences after advance payment.\n'
      '4. Prices are subject to prevailing GST rates and material costs.';

  String _defaultPurchaseTerms() =>
      '1. Material is accepted subject to warehouse inspection.\n'
      '2. Defective or rejected goods must be replaced within 7 days.\n'
      '3. Invoices must reference the valid purchase order number.';

  String _defaultChallanTerms() =>
      '1. Goods dispatched at consignee risk.\n'
      '2. Please verify package count and condition on delivery.\n'
      '3. Acknowledged copy must be signed and returned.';

  void _loadStandardTemplate() {
    switch (_selectedDocType) {
      case 'sales':
        _termsSales.text = _defaultSalesTerms();
      case 'quotation':
        _termsQuotation.text = _defaultQuotationTerms();
      case 'purchase':
        _termsPurchase.text = _defaultPurchaseTerms();
      case 'challan':
        _termsChallan.text = _defaultChallanTerms();
    }
    setState(() {});
    showAppMessage(context, 'Loaded standard template for ${_selectedDocType.toUpperCase()}');
  }

  Future<void> _pickSignatureImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        if (!mounted) return;
        setState(() {
          _signaturePath = result.files.single.path;
        });
        showAppMessage(context, 'Signature selected');
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Failed to pick image: $e', error: true);
      }
    }
  }

  void _removeSignature() {
    setState(() => _signaturePath = null);
    showAppMessage(context, 'Signature image removed');
  }

  Future<void> _save() async {
    if (_business == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final updated = Business(
        id: _business!.id,
        name: _business!.name,
        ownerName: _business!.ownerName,
        phone: _business!.phone,
        email: _business!.email,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        state: _state.text.trim().isEmpty ? null : _state.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        pinCode: _pinCode.text.trim().isEmpty ? null : _pinCode.text.trim(),
        country: _business!.country,
        logoPath: _business!.logoPath,
        signaturePath: _signaturePath,
        website: _business!.website,
        gstin: _business!.gstin,
        pan: _business!.pan,
        industry: _business!.industry,
        upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
        taxRegistered: _business!.taxRegistered,
        isComposition: _business!.isComposition,
        invoicePrefix: _invPrefix.text.trim().toUpperCase(),
        invoiceSequence: int.tryParse(_invSequence.text.trim()) ?? _business!.invoiceSequence,
        allowNegativeStock: _business!.allowNegativeStock,
        fyStart: _business!.fyStart,
        currency: _business!.currency,
        invoicePhone: _invoicePhone.text.trim().isEmpty ? null : _invoicePhone.text.trim(),
        invoiceEmail: _invoiceEmail.text.trim().isEmpty ? null : _invoiceEmail.text.trim(),
        termsSales: _termsSales.text.trim().isEmpty ? null : _termsSales.text.trim(),
        termsQuotation: _termsQuotation.text.trim().isEmpty ? null : _termsQuotation.text.trim(),
        termsPurchase: _termsPurchase.text.trim().isEmpty ? null : _termsPurchase.text.trim(),
        termsChallan: _termsChallan.text.trim().isEmpty ? null : _termsChallan.text.trim(),
        signatureText: _signatureText.text.trim().isEmpty ? 'Authorised Signatory' : _signatureText.text.trim(),
        showEmptySignatureBox: _showEmptySignatureBox,
        showPaymentQr: _showPaymentQr,
        bankAccountId: _selectedBankAccountId,
        quotationPrefix: _quotePrefix.text.trim().toUpperCase(),
        quotationSequence: int.tryParse(_quoteSequence.text.trim()) ?? _business!.quotationSequence,
        purchasePrefix: _purchasePrefix.text.trim().toUpperCase(),
        purchaseSequence: int.tryParse(_purchaseSequence.text.trim()) ?? _business!.purchaseSequence,
      );

      await Repository.instance.updateBusiness(updated);
      _business = updated;

      if (mounted) {
        showAppMessage(context, 'Invoice settings saved successfully');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Failed to save settings: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Business _buildCurrentBusiness() {
    return Business(
      id: _business?.id ?? _bizId,
      name: _business?.name ?? 'My Business',
      ownerName: _business?.ownerName,
      phone: _business?.phone,
      email: _business?.email,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      state: _state.text.trim().isEmpty ? null : _state.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      pinCode: _pinCode.text.trim().isEmpty ? null : _pinCode.text.trim(),
      country: _business?.country ?? 'India',
      logoPath: _business?.logoPath,
      signaturePath: _signaturePath,
      website: _business?.website,
      gstin: _business?.gstin,
      pan: _business?.pan,
      industry: _business?.industry,
      upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
      taxRegistered: _business?.taxRegistered ?? true,
      isComposition: _business?.isComposition ?? false,
      invoicePrefix: _invPrefix.text.trim().toUpperCase(),
      invoiceSequence: int.tryParse(_invSequence.text.trim()) ?? (_business?.invoiceSequence ?? 0),
      allowNegativeStock: _business?.allowNegativeStock ?? true,
      fyStart: _business?.fyStart ?? '2026-04-01',
      currency: _business?.currency ?? 'INR',
      invoicePhone: _invoicePhone.text.trim().isEmpty ? null : _invoicePhone.text.trim(),
      invoiceEmail: _invoiceEmail.text.trim().isEmpty ? null : _invoiceEmail.text.trim(),
      termsSales: _termsSales.text.trim().isEmpty ? null : _termsSales.text.trim(),
      termsQuotation: _termsQuotation.text.trim().isEmpty ? null : _termsQuotation.text.trim(),
      termsPurchase: _termsPurchase.text.trim().isEmpty ? null : _termsPurchase.text.trim(),
      termsChallan: _termsChallan.text.trim().isEmpty ? null : _termsChallan.text.trim(),
      signatureText: _signatureText.text.trim().isEmpty ? 'Authorised Signatory' : _signatureText.text.trim(),
      showEmptySignatureBox: _showEmptySignatureBox,
      showPaymentQr: _showPaymentQr,
      bankAccountId: _selectedBankAccountId,
      quotationPrefix: _quotePrefix.text.trim().toUpperCase(),
      quotationSequence: int.tryParse(_quoteSequence.text.trim()) ?? (_business?.quotationSequence ?? 0),
      purchasePrefix: _purchasePrefix.text.trim().toUpperCase(),
      purchaseSequence: int.tryParse(_purchaseSequence.text.trim()) ?? (_business?.purchaseSequence ?? 0),
    );
  }

  Future<void> _showAddEditBankAccountModal([BankAccount? account]) async {
    final nameCtrl = TextEditingController(text: account?.bankName ?? '');
    final acctNameCtrl = TextEditingController(text: account?.accountName ?? _business?.name ?? '');
    final numCtrl = TextEditingController(text: account?.accountNumber ?? '');
    final ifscCtrl = TextEditingController(text: account?.ifsc ?? '');
    String acctType = account?.accountType ?? 'Current';

    final isNew = account == null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, color: StitchColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        isNew ? 'Add Bank Account' : 'Edit Bank Account',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bank details will be printed on your invoices for NEFT/RTGS/IMPS payments.',
                  style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                ),
              ),
              const Divider(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: inputDecoration('Bank Name *', hint: 'e.g. HDFC Bank, SBI, ICICI Bank'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: acctNameCtrl,
                        decoration: inputDecoration('Beneficiary / Account Holder Name', hint: 'e.g. Apex Enterprises'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: numCtrl,
                        decoration: inputDecoration('Account Number', hint: 'e.g. 50200012345678'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: ifscCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: inputDecoration('IFSC Code', hint: 'HDFC0001234'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: acctType,
                              decoration: inputDecoration('Type'),
                              items: const [
                                DropdownMenuItem(value: 'Current', child: Text('Current')),
                                DropdownMenuItem(value: 'Savings', child: Text('Savings')),
                                DropdownMenuItem(value: 'Overdraft', child: Text('OD / CC')),
                              ],
                              onChanged: (val) {
                                if (val != null) setSheetState(() => acctType = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final bName = nameCtrl.text.trim();
                            if (bName.isEmpty) {
                              showAppMessage(context, 'Bank Name is required', error: true);
                              return;
                            }
                            final bank = BankAccount(
                              id: account?.id,
                              businessId: _bizId,
                              bankName: bName,
                              accountName: acctNameCtrl.text.trim().isNotEmpty ? acctNameCtrl.text.trim() : null,
                              accountNumber: numCtrl.text.trim().isNotEmpty ? numCtrl.text.trim() : null,
                              ifsc: ifscCtrl.text.trim().isNotEmpty ? ifscCtrl.text.trim().toUpperCase() : null,
                              accountType: acctType,
                              openingBalance: account?.openingBalance ?? 0,
                            );
                            final savedId = await Repository.instance.upsertBankAccount(bank);
                            if (ctx.mounted) Navigator.pop(ctx);
                            final updatedBanks = await Repository.instance.bankAccounts(_bizId);
                            if (mounted) {
                              setState(() {
                                _bankAccounts = updatedBanks;
                                _selectedBankAccountId ??= savedId;
                              });
                              showAppMessage(context, 'Bank account saved successfully');
                            }
                          },
                          icon: const Icon(Icons.check_circle_rounded),
                          label: Text(isNew ? 'Save & Add Bank Account' : 'Update Bank Account', style: const TextStyle(fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            backgroundColor: StitchColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _previewInvoice() async {
    if (_business == null) return;
    final currentBiz = _buildCurrentBusiness();
    final settings = await Repository.instance.getInvoiceCustomizationSettings(_bizId);
    final bank = _selectedBankAccountId != null
        ? _bankAccounts.where((b) => b.id == _selectedBankAccountId).firstOrNull
        : (_bankAccounts.isNotEmpty ? _bankAccounts.first : null);

    if (!mounted) return;
    await showInvoicePreviewModal(
      context,
      business: currentBiz,
      settings: settings,
      bankAccount: bank,
      title: 'Invoice Preview (${currentBiz.invoicePrefix})',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Settings'),
        actions: [
          TextButton.icon(
            onPressed: _previewInvoice,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Commercial Invoice Customization Banner
            AppCard(
              padding: const EdgeInsets.all(14),
              child: InkWell(
                onTap: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InvoiceCustomizationScreen()),
                  );
                  if (res == true && mounted) {
                    _load();
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: StitchColors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: StitchColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Customize Commercial Invoice Theme', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: StitchColors.primary)),
                          SizedBox(height: 2),
                          Text('Live split-screen preview, column toggles, HSN matrix, and branding', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: StitchColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 1. Voucher & Numbering Card
            _buildSectionCard(
              title: 'Voucher Prefixes & Sequences',
              subtitle: 'Customize starting numbers for sales bills, quotations, and purchases.',
              icon: Icons.tag_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _invPrefix,
                        decoration: inputDecoration('Sales Prefix (e.g. INV)'),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _invSequence,
                        decoration: inputDecoration('Next Sequence (e.g. 0)'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || int.tryParse(v.trim()) == null ? 'Enter number' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Next invoice: ${_invPrefix.text.trim().toUpperCase()}-${(int.tryParse(_invSequence.text.trim()) ?? 0) + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.primary),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _quotePrefix,
                        decoration: inputDecoration('Quotation Prefix'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _quoteSequence,
                        decoration: inputDecoration('Next Quotation No.'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _purchasePrefix,
                        decoration: inputDecoration('Purchase Prefix'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _purchaseSequence,
                        decoration: inputDecoration('Next Purchase No.'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Address & Contact Details on Invoices
            _buildSectionCard(
              title: 'Address & Contact Details on Invoices',
              subtitle: 'Control which address, phone number, and email are printed on your invoices.',
              icon: Icons.contact_phone_outlined,
              children: [
                TextFormField(
                  controller: _address,
                  decoration: inputDecoration('Business / Store Address', hint: 'Shop / Building, Street, Area'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _city,
                        decoration: inputDecoration('City', hint: 'e.g. Mumbai'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _state,
                        decoration: inputDecoration('State', hint: 'e.g. Maharashtra'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _pinCode,
                        decoration: inputDecoration('PIN Code', hint: '400001'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _invoicePhone,
                  decoration: inputDecoration('Invoice Phone / Mobile Number', hint: 'Leave blank to use business phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _invoiceEmail,
                  decoration: inputDecoration('Invoice Email Address', hint: 'Leave blank to use business email'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Terms & Conditions per Document Type
            _buildSectionCard(
              title: 'Terms & Conditions',
              subtitle: 'Set custom terms for each document type with 1-click standard templates.',
              icon: Icons.gavel_rounded,
              trailing: TextButton.icon(
                onPressed: _loadStandardTemplate,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                label: const Text('Load Standard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'sales', label: Text('Sales')),
                    ButtonSegment(value: 'quotation', label: Text('Quotation')),
                    ButtonSegment(value: 'purchase', label: Text('Purchase')),
                    ButtonSegment(value: 'challan', label: Text('Challan')),
                  ],
                  selected: {_selectedDocType},
                  onSelectionChanged: (s) => setState(() => _selectedDocType = s.first),
                ),
                const SizedBox(height: 12),
                if (_selectedDocType == 'sales')
                  TextFormField(
                    controller: _termsSales,
                    decoration: inputDecoration('Sales Invoice Terms & Conditions', hint: 'Enter terms, one per line'),
                    maxLines: 5,
                  )
                else if (_selectedDocType == 'quotation')
                  TextFormField(
                    controller: _termsQuotation,
                    decoration: inputDecoration('Quotation Terms & Conditions', hint: 'Enter quotation validity, advance %...'),
                    maxLines: 5,
                  )
                else if (_selectedDocType == 'purchase')
                  TextFormField(
                    controller: _termsPurchase,
                    decoration: inputDecoration('Purchase Order Terms', hint: 'Enter vendor inspection terms...'),
                    maxLines: 5,
                  )
                else
                  TextFormField(
                    controller: _termsChallan,
                    decoration: inputDecoration('Delivery Challan Terms', hint: 'Enter delivery & dispatch terms...'),
                    maxLines: 5,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Signature Management Card
            _buildSectionCard(
              title: 'Signature & Signatory',
              subtitle: 'Upload your physical signature image or print a clean authorised signature box.',
              icon: Icons.draw_outlined,
              children: [
                if (_signaturePath != null && _signaturePath!.isNotEmpty) ...[
                  Container(
                    height: 90,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StitchColors.outline),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 140,
                          height: 74,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: StitchColors.outlineStrong),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(_signaturePath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Image not found', style: TextStyle(fontSize: 10, color: Colors.red)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Signature Uploaded', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: _pickSignatureImage,
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('Change', style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _removeSignature,
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: StitchColors.error,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('Remove', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: _pickSignatureImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    label: const Text('Upload Signature from Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _signatureText,
                  decoration: inputDecoration('Signatory Label / Designation', hint: 'e.g. Authorised Signatory'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Stamp & Sign Box', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Prints an official stamped border box when no digital image is uploaded', style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                  value: _showEmptySignatureBox,
                  onChanged: (v) => setState(() => _showEmptySignatureBox = v),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 5. Payment QR & Bank Details
            _buildSectionCard(
              title: 'Payment QR & Bank Details',
              subtitle: 'Allow clients to scan and pay instantly via UPI apps or NEFT/RTGS/IMPS.',
              icon: Icons.qr_code_2_rounded,
              trailing: TextButton.icon(
                onPressed: () => _showAddEditBankAccountModal(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Bank', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: StitchColors.primary,
                ),
              ),
              children: [
                TextFormField(
                  controller: _upiId,
                  decoration: inputDecoration('UPI ID (VPA)', hint: 'e.g. business@okaxis or 9876543210@upi'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Print Dynamic UPI Payment QR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Clients can scan with PhonePe, Google Pay, Paytm, or BHIM', style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                  value: _showPaymentQr,
                  onChanged: (v) => setState(() => _showPaymentQr = v),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bank Account Configuration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    OutlinedButton.icon(
                      onPressed: () => _showAddEditBankAccountModal(),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Account', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_bankAccounts.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedBankAccountId,
                    decoration: inputDecoration('Primary Bank for Invoice Printing'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Do not print bank details'),
                      ),
                      ..._bankAccounts.map((b) => DropdownMenuItem<int?>(
                            value: b.id,
                            child: Text('${b.bankName} • ${b.accountNumber ?? ''} (${b.accountType})'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedBankAccountId = v),
                  ),
                  if (_selectedBankAccountId != null) ...[
                    const SizedBox(height: 10),
                    Builder(
                      builder: (ctx) {
                        final selBank = _bankAccounts.firstWhere(
                          (b) => b.id == _selectedBankAccountId,
                          orElse: () => _bankAccounts.first,
                        );
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: StitchColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: StitchColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.account_balance_rounded, color: StitchColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(selBank.bankName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    if (selBank.accountNumber != null && selBank.accountNumber!.isNotEmpty)
                                      Text('A/C: ${selBank.accountNumber} • IFSC: ${selBank.ifsc ?? 'N/A'}',
                                          style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                                    if (selBank.accountName != null && selBank.accountName!.isNotEmpty)
                                      Text('Beneficiary: ${selBank.accountName}',
                                          style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Edit Bank Details',
                                onPressed: () => _showAddEditBankAccountModal(selBank),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StitchColors.outline),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.account_balance_outlined, size: 20, color: StitchColors.textSecondary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No bank accounts configured yet. Add your bank details to print them on invoices and collect payments via NEFT/RTGS/IMPS.',
                                style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showAddEditBankAccountModal(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Bank Account Details'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: StitchColors.background,
            border: Border(top: BorderSide(color: StitchColors.outline)),
          ),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Save Invoice Settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: StitchColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: StitchColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
