import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../../utils/widgets.dart';

class InvoiceCustomizationScreen extends StatefulWidget {
  const InvoiceCustomizationScreen({super.key});

  @override
  State<InvoiceCustomizationScreen> createState() => _InvoiceCustomizationScreenState();
}

class _InvoiceCustomizationScreenState extends State<InvoiceCustomizationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  InvoiceCustomizationSettings? _settings;
  Business? _business;
  List<BankAccount> _bankAccounts = [];
  bool _loading = true;
  bool _saving = false;

  // Controllers
  final _titleController = TextEditingController();
  final _declarationController = TextEditingController();

  static const List<Map<String, String>> _curatedColors = [
    {'name': 'Navy Blue', 'hex': '#1E3A8A'},
    {'name': 'Emerald Green', 'hex': '#065F46'},
    {'name': 'Slate Grey', 'hex': '#1E293B'},
    {'name': 'Wine Crimson', 'hex': '#831843'},
    {'name': 'Royal Indigo', 'hex': '#4338CA'},
    {'name': 'Teal Ocean', 'hex': '#0F766E'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _declarationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final biz = await repo.getBusiness(businessId);
    final settings = await repo.getInvoiceCustomizationSettings(businessId);
    final banks = await repo.bankAccounts(businessId);

    if (!mounted) return;
    setState(() {
      _business = biz;
      _settings = settings;
      _bankAccounts = banks.where((b) => !b.inactive).toList();
      _titleController.text = settings.customTitleOverride ?? '';
      _declarationController.text = settings.declarationText;
      _loading = false;
    });
  }

  Future<void> _pickSignatureImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _settings = _settings?.copyWith(signatureImagePath: result.files.single.path);
      });
    }
  }

  Future<void> _pickBusinessLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.single.path != null && _business != null) {
      final newBiz = _business!.copyWith(logoPath: result.files.single.path);
      await Repository.instance.updateBusiness(newBiz);
      setState(() {
        _business = newBiz;
      });
    }
  }

  Future<void> _removeBusinessLogo() async {
    if (_business == null) return;
    final newBiz = _business!.copyWith(logoPath: null);
    await Repository.instance.updateBusiness(newBiz);
    setState(() {
      _business = newBiz;
    });
  }

  Future<void> _showEditBusinessDetailsSheet() async {
    if (_business == null) return;
    final biz = _business!;

    final nameCtrl = TextEditingController(text: biz.name);
    final phoneCtrl = TextEditingController(text: biz.phone ?? biz.invoicePhone ?? '');
    final emailCtrl = TextEditingController(text: biz.email ?? biz.invoiceEmail ?? '');
    final addressCtrl = TextEditingController(text: biz.address ?? '');
    final cityCtrl = TextEditingController(text: biz.city ?? '');
    final stateCtrl = TextEditingController(text: biz.state ?? '');
    final pinCtrl = TextEditingController(text: biz.pinCode ?? '');
    final gstinCtrl = TextEditingController(text: biz.gstin ?? '');
    final panCtrl = TextEditingController(text: biz.pan ?? '');

    bool savingBiz = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
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
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
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
                  const Row(
                    children: [
                      Icon(Icons.business_rounded, color: StitchColors.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Edit Business Details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                  'These details appear on your invoice header, e-way bills, and commercial documents.',
                  style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                ),
              ),
              const Divider(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      AppTextField(
                        controller: nameCtrl,
                        label: 'Business Name *',
                        icon: Icons.storefront_outlined,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: phoneCtrl,
                              label: 'Mobile / Phone No.',
                              hint: '+91 98765 43210',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: emailCtrl,
                              label: 'Email Address',
                              hint: 'contact@store.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: addressCtrl,
                        label: 'Building / Street Address',
                        icon: Icons.location_on_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: cityCtrl,
                              label: 'City',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: stateCtrl,
                              label: 'State',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: pinCtrl,
                              label: 'PIN Code',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: panCtrl,
                              label: 'PAN Number',
                              hint: 'e.g. ABCDE1234F',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: gstinCtrl,
                        label: 'GSTIN Number (15 Characters)',
                        hint: 'e.g. 29AAAAA0000A1Z5',
                        icon: Icons.receipt_long_outlined,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: savingBiz
                              ? null
                              : () async {
                                  if (nameCtrl.text.trim().isEmpty) {
                                    showAppMessage(context, 'Business name is required', error: true);
                                    return;
                                  }
                                  setModalState(() => savingBiz = true);
                                  try {
                                    final updatedBiz = biz.copyWith(
                                      name: nameCtrl.text.trim(),
                                      phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                      invoicePhone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                      email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                      invoiceEmail: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                      address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                                      city: cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
                                      state: stateCtrl.text.trim().isEmpty ? null : stateCtrl.text.trim(),
                                      pinCode: pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim(),
                                      pan: panCtrl.text.trim().isEmpty ? null : panCtrl.text.trim().toUpperCase(),
                                      gstin: gstinCtrl.text.trim().isEmpty ? null : gstinCtrl.text.trim().toUpperCase(),
                                    );
                                    await Repository.instance.updateBusiness(updatedBiz);
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _business = updatedBiz;
                                      });
                                      showAppMessage(context, 'Business details updated successfully');
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setModalState(() => savingBiz = false);
                                    }
                                    if (mounted) {
                                      showAppMessage(context, 'Failed to update business: $e', error: true);
                                    }
                                  }
                                },
                          icon: savingBiz
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_rounded),
                          label: const Text('Save Business Details', style: TextStyle(fontWeight: FontWeight.w700)),
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

  Future<void> _saveSettings() async {
    if (_settings == null || _business == null) return;
    setState(() => _saving = true);
    try {
      final updated = _settings!.copyWith(
        customTitleOverride: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        declarationText: _declarationController.text.trim(),
      );
      await Repository.instance.saveInvoiceCustomizationSettings(updated);
      setState(() => _settings = updated);
      if (mounted) {
        showAppMessage(context, 'Invoice customization settings saved successfully');
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Failed to save settings: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Uint8List> _generatePreviewPdf() async {
    if (_business == null || _settings == null) {
      return Uint8List(0);
    }
    final currentSettings = _settings!.copyWith(
      customTitleOverride: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
      declarationText: _declarationController.text.trim(),
    );

    BankAccount? primaryBank;
    if (_bankAccounts.isNotEmpty) {
      if (_business!.bankAccountId != null) {
        primaryBank = _bankAccounts.firstWhere((b) => b.id == _business!.bankAccountId, orElse: () => _bankAccounts.first);
      } else {
        primaryBank = _bankAccounts.first;
      }
    }

    return generateCommercialSamplePdf(
      business: _business!,
      settings: currentSettings,
      bankAccount: primaryBank,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Customization'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Save Template', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
        bottom: isDesktop
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.tune_rounded), text: 'Controls'),
                  Tab(icon: Icon(Icons.picture_as_pdf_outlined), text: 'Live Preview'),
                ],
              ),
      ),
      body: isDesktop ? _buildSplitScreen() : _buildMobileTabs(),
    );
  }

  Widget _buildSplitScreen() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildControlsList(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.all(16),
            child: _buildPdfPreviewWidget(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTabs() {
    return TabBarView(
      controller: _tabController,
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildControlsList(),
        ),
        Container(
          color: const Color(0xFFF1F5F9),
          padding: const EdgeInsets.all(8),
          child: _buildPdfPreviewWidget(),
        ),
      ],
    );
  }

  Widget _buildPdfPreviewWidget() {
    return PdfPreview(
      build: (format) => _generatePreviewPdf(),
      allowPrinting: true,
      allowSharing: true,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      previewPageMargin: const EdgeInsets.all(8),
      dynamicLayout: false,
    );
  }

  Widget _buildControlsList() {
    final settings = _settings!;
    final biz = _business!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==========================================
        // 1. BUSINESS DETAILS & BRANDING
        // ==========================================
        _sectionHeader(Icons.business_rounded, 'Business Details & Branding'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo and Business Overview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          border: Border.all(color: StitchColors.outline),
                          borderRadius: BorderRadius.circular(10),
                          color: StitchColors.surfaceVariant,
                        ),
                        child: biz.logoPath != null && File(biz.logoPath!).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.file(File(biz.logoPath!), fit: BoxFit.cover),
                              )
                            : const Icon(Icons.storefront_rounded, color: StitchColors.textSecondary, size: 30),
                      ),
                      if (biz.logoPath != null)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: InkWell(
                            onTap: _removeBusinessLogo,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(biz.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        if (biz.displayInvoicePhone.isNotEmpty)
                          Text('📞 ${biz.displayInvoicePhone}', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                        if (biz.displayInvoiceEmail.isNotEmpty)
                          Text('✉️ ${biz.displayInvoiceEmail}', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                        if (biz.gstin != null && biz.gstin!.isNotEmpty)
                          Text('GSTIN: ${biz.gstin}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showEditBusinessDetailsSheet,
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text('Edit Business Details'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickBusinessLogo,
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: Text(biz.logoPath != null ? 'Change Logo' : 'Upload Logo'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              // Header Visibility Toggles
              const Text('Invoice Header Fields Visibility:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
              const SizedBox(height: 6),
              _buildCompactToggle('Show Business Address', settings.showAddress, (v) => setState(() => _settings = _settings?.copyWith(showAddress: v))),
              _buildCompactToggle('Show Phone / Mobile No.', settings.showPhone, (v) => setState(() => _settings = _settings?.copyWith(showPhone: v))),
              _buildCompactToggle('Show Email Address', settings.showEmail, (v) => setState(() => _settings = _settings?.copyWith(showEmail: v))),
              _buildCompactToggle('Show GSTIN Number', settings.showGstin, (v) => setState(() => _settings = _settings?.copyWith(showGstin: v))),
              _buildCompactToggle('Show PAN Number', settings.showPan, (v) => setState(() => _settings = _settings?.copyWith(showPan: v))),
              const Divider(height: 20),
              // Logo Placement Selector
              const Text('Logo Alignment:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'left', label: Text('Left'), icon: Icon(Icons.format_align_left_rounded, size: 16)),
                  ButtonSegment(value: 'center', label: Text('Center'), icon: Icon(Icons.format_align_center_rounded, size: 16)),
                  ButtonSegment(value: 'right', label: Text('Right'), icon: Icon(Icons.format_align_right_rounded, size: 16)),
                ],
                selected: {settings.logoPlacement},
                onSelectionChanged: (val) {
                  setState(() {
                    _settings = _settings?.copyWith(logoPlacement: val.first);
                  });
                },
              ),
              const SizedBox(height: 16),
              // Document Title Override
              TextField(
                controller: _titleController,
                onChanged: (_) => setState(() {}),
                decoration: inputDecoration(
                  'Document Title Override',
                  hint: 'TAX INVOICE / BILL OF SUPPLY / ORIGINAL',
                ),
              ),
              const SizedBox(height: 16),
              // Primary Palette Colors
              const Text('Theme Accent Color:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _curatedColors.map((c) {
                  final isSelected = settings.primaryColorHex.toUpperCase() == c['hex']!.toUpperCase();
                  final col = Color(int.parse('FF${c['hex']!.replaceAll('#', '')}', radix: 16));
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _settings = _settings?.copyWith(primaryColorHex: c['hex']!);
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? col.withValues(alpha: 0.15) : Colors.transparent,
                        border: Border.all(color: isSelected ? col : StitchColors.outline, width: isSelected ? 2 : 1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(c['name']!, style: TextStyle(fontSize: 11.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // 2. ITEM TABLE COLUMN VISIBILITY TOGGLES
        // ==========================================
        _sectionHeader(Icons.table_chart_outlined, 'Line Items Table Columns'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Column(
            children: [
              _buildCompactToggle('HSN / SAC Code Column', settings.showHsnColumn, (v) => setState(() => _settings = _settings?.copyWith(showHsnColumn: v))),
              const Divider(height: 1),
              _buildCompactToggle('Quantity & Unit (UOM) Column', settings.showUnitColumn, (v) => setState(() => _settings = _settings?.copyWith(showUnitColumn: v))),
              const Divider(height: 1),
              _buildCompactToggle('Discount Column', settings.showDiscountColumn, (v) => setState(() => _settings = _settings?.copyWith(showDiscountColumn: v))),
              const Divider(height: 1),
              _buildCompactToggle('Tax Rate (%) Column', settings.showTaxColumn, (v) => setState(() => _settings = _settings?.copyWith(showTaxColumn: v))),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // 3. PARTY & STATUTORY FIELDS
        // ==========================================
        _sectionHeader(Icons.business_center_outlined, 'Party & Statutory Formatting'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Column(
            children: [
              _buildCompactToggle('Dedicated "SHIP TO" Address Block', settings.showShipTo, (v) => setState(() => _settings = _settings?.copyWith(showShipTo: v))),
              const Divider(height: 1),
              _buildCompactToggle('Customer PAN Display', settings.showPan, (v) => setState(() => _settings = _settings?.copyWith(showPan: v))),
              const Divider(height: 1),
              _buildCompactToggle('Customer Phone Number', settings.showPhone, (v) => setState(() => _settings = _settings?.copyWith(showPhone: v))),
              const Divider(height: 1),
              _buildCompactToggle('Purchase Order (PO) Details', settings.showPoDetails, (v) => setState(() => _settings = _settings?.copyWith(showPoDetails: v))),
              const Divider(height: 1),
              _buildCompactToggle('Transport & E-Way Bill Strip', settings.showVehicleDetails, (v) => setState(() => _settings = _settings?.copyWith(showVehicleDetails: v))),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // 4. FOOTER PLACEMENT & LAYOUT (SETTLEMENT, QR, TERMS, SIGNATURE)
        // ==========================================
        _sectionHeader(Icons.dashboard_customize_outlined, 'Footer Placement & Layout'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bank & QR Placement Selector
              const Text('Bank Details & Payment QR Placement:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'left', label: Text('Left Column'), icon: Icon(Icons.align_horizontal_left_rounded, size: 16)),
                  ButtonSegment(value: 'right', label: Text('Right Column'), icon: Icon(Icons.align_horizontal_right_rounded, size: 16)),
                  ButtonSegment(value: 'bottom', label: Text('Full Width'), icon: Icon(Icons.table_rows_rounded, size: 16)),
                ],
                selected: {settings.bankQrPlacement},
                onSelectionChanged: (val) {
                  setState(() {
                    _settings = _settings?.copyWith(bankQrPlacement: val.first);
                  });
                },
              ),
              const SizedBox(height: 6),
              const Text('Choose where Bank Details and UPI QR appear in relation to invoice totals.', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
              const SizedBox(height: 12),
              _buildCompactToggle('Show Bank Account Details', settings.showBankDetails, (v) => setState(() => _settings = _settings?.copyWith(showBankDetails: v))),
              _buildCompactToggle('Show Dynamic NPCI UPI QR Code', settings.showUpiQr, (v) => setState(() => _settings = _settings?.copyWith(showUpiQr: v))),

              const Divider(height: 24),

              // Authorized Signatory Placement
              const Text('Authorized Signatory Placement:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'right', label: Text('Right Aligned'), icon: Icon(Icons.format_align_right_rounded, size: 16)),
                  ButtonSegment(value: 'left', label: Text('Left Aligned'), icon: Icon(Icons.format_align_left_rounded, size: 16)),
                ],
                selected: {settings.signaturePlacement},
                onSelectionChanged: (val) {
                  setState(() {
                    _settings = _settings?.copyWith(signaturePlacement: val.first);
                  });
                },
              ),
              const SizedBox(height: 10),
              _buildCompactToggle('Show Signatory Container', settings.showSignatureBox, (v) => setState(() => _settings = _settings?.copyWith(showSignatureBox: v))),
              const SizedBox(height: 10),
              // Signature image upload
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: StitchColors.outline),
                      borderRadius: BorderRadius.circular(6),
                      color: StitchColors.surfaceVariant,
                    ),
                    child: settings.signatureImagePath != null && File(settings.signatureImagePath!).existsSync()
                        ? Image.file(File(settings.signatureImagePath!), fit: BoxFit.contain)
                        : const Center(child: Icon(Icons.draw_rounded, size: 20, color: StitchColors.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Digital Signature Stamp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('Upload transparent PNG of stamp or signature.', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickSignatureImage,
                    icon: const Icon(Icons.upload_rounded, size: 15),
                    label: Text(settings.signatureImagePath != null ? 'Replace' : 'Upload'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Terms & Declarations Visibility & Placement
              const Text('Terms & Declarations Visibility:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
              const SizedBox(height: 6),
              _buildCompactToggle('Show Terms & Conditions', settings.showTerms, (v) => setState(() => _settings = _settings?.copyWith(showTerms: v))),
              _buildCompactToggle('Show Statutory Declaration', settings.showDeclaration, (v) => setState(() => _settings = _settings?.copyWith(showDeclaration: v))),
              _buildCompactToggle('Show HSN/SAC Breakdown Table', settings.showHsnSummaryTable, (v) => setState(() => _settings = _settings?.copyWith(showHsnSummaryTable: v))),
              const SizedBox(height: 14),
              // Custom declaration / terms override
              TextField(
                controller: _declarationController,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: inputDecoration(
                  'Custom Declaration / Disclaimer Override',
                  hint: 'Leave blank to use default commercial declaration or business terms...',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded),
            label: const Text('Save Customization Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            style: FilledButton.styleFrom(
              backgroundColor: StitchColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: StitchColors.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildCompactToggle(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: StitchColors.primary,
    );
  }
}
