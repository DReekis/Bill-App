import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import 'tally_export_service.dart';

class TallyExportScreen extends StatefulWidget {
  const TallyExportScreen({super.key});

  @override
  State<TallyExportScreen> createState() => _TallyExportScreenState();
}

class _TallyExportScreenState extends State<TallyExportScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _datePreset = 'This Month';

  bool _includeSales = true;
  bool _includePurchases = true;
  bool _includeReceipts = true;
  bool _includePayments = true;
  bool _includeMasters = true;

  bool _isGenerating = false;
  TallyExportSummary? _summary;

  @override
  void initState() {
    super.initState();
    _applyPreset('This Month');
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _datePreset = preset;
      if (preset == 'This Month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
      } else if (preset == 'Last Month') {
        _startDate = DateTime(now.year, now.month - 1, 1);
        _endDate = DateTime(now.year, now.month, 0);
      } else if (preset == 'This FY') {
        final fyYear = now.month >= 4 ? now.year : now.year - 1;
        _startDate = DateTime(fyYear, 4, 1);
        _endDate = DateTime(fyYear + 1, 3, 31);
      } else if (preset == 'All Time') {
        _startDate = null;
        _endDate = null;
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
    );
    if (picked != null) {
      setState(() {
        _datePreset = 'Custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _generateExport({bool autoShare = false}) async {
    final bizId = Session().businessId;
    if (bizId == null) {
      showAppMessage(context, 'No active business selected');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final summary = await TallyExportService.instance.exportTallyXml(
        businessId: bizId,
        filter: TallyExportFilter(
          startDate: _startDate,
          endDate: _endDate,
          includeSales: _includeSales,
          includePurchases: _includePurchases,
          includeReceipts: _includeReceipts,
          includePayments: _includePayments,
          includeMasters: _includeMasters,
        ),
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isGenerating = false;
      });

      if (autoShare) {
        await Share.shareXFiles(
          [XFile(summary.file.path)],
          subject: 'Tally Prime XML Export',
          text: 'Tally Prime XML Export (${summary.totalVouchers} vouchers, ${summary.ledgerCount} ledgers)',
        );
      } else {
        showAppMessage(
          context,
          'XML generated! ${summary.totalVouchers} vouchers ready for Tally Prime',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      showAppMessage(context, 'Export error: $e');
    }
  }

  void _copyToClipboard() {
    if (_summary == null) return;
    Clipboard.setData(ClipboardData(text: _summary!.xml));
    showAppMessage(context, 'Tally XML copied to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Export to Tally Prime',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Banner / Hero Card
          _buildHeroCard(),
          const SizedBox(height: 16),

          // Date Range Card
          _buildCard(
            title: '1. Select Period',
            icon: Icons.calendar_today_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PresetChip(
                        label: 'This Month',
                        selected: _datePreset == 'This Month',
                        onSelected: () => _applyPreset('This Month'),
                      ),
                      const SizedBox(width: 8),
                      _PresetChip(
                        label: 'Last Month',
                        selected: _datePreset == 'Last Month',
                        onSelected: () => _applyPreset('Last Month'),
                      ),
                      const SizedBox(width: 8),
                      _PresetChip(
                        label: 'This FY',
                        selected: _datePreset == 'This FY',
                        onSelected: () => _applyPreset('This FY'),
                      ),
                      const SizedBox(width: 8),
                      _PresetChip(
                        label: 'All Time',
                        selected: _datePreset == 'All Time',
                        onSelected: () => _applyPreset('All Time'),
                      ),
                      const SizedBox(width: 8),
                      _PresetChip(
                        label: 'Custom',
                        selected: _datePreset == 'Custom',
                        onSelected: _pickCustomRange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickCustomRange,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _startDate != null && _endDate != null
                              ? '${dateFormat.format(_startDate!)}  →  ${dateFormat.format(_endDate!)}'
                              : 'All Recorded Transactions',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Icon(Icons.edit_calendar_rounded, size: 18, color: StitchColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Selection Card
          _buildCard(
            title: '2. Select Data to Include',
            icon: Icons.checklist_rounded,
            child: Column(
              children: [
                _buildCheckboxTile(
                  title: 'Sales Invoices',
                  subtitle: 'Invoices with item rates, GST (CGST/SGST/IGST), and party bill allocations',
                  value: _includeSales,
                  onChanged: (v) => setState(() => _includeSales = v ?? true),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildCheckboxTile(
                  title: 'Purchase Bills',
                  subtitle: 'Stock purchases with supplier credits and tax input debits',
                  value: _includePurchases,
                  onChanged: (v) => setState(() => _includePurchases = v ?? true),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildCheckboxTile(
                  title: 'Customer Receipts',
                  subtitle: 'Payment-in vouchers linked to Cash or Bank accounts',
                  value: _includeReceipts,
                  onChanged: (v) => setState(() => _includeReceipts = v ?? true),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildCheckboxTile(
                  title: 'Supplier & Expense Payments',
                  subtitle: 'Payment-out vouchers for vendors and operational expenses',
                  value: _includePayments,
                  onChanged: (v) => setState(() => _includePayments = v ?? true),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildCheckboxTile(
                  title: 'Master Ledgers (Parties & Accounts)',
                  subtitle: 'Sundry Debtors & Creditors with GSTIN, State, and Opening Balance',
                  value: _includeMasters,
                  onChanged: (v) => setState(() => _includeMasters = v ?? true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Export & Share Primary Buttons
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : () => _generateExport(autoShare: true),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded, color: Colors.white, size: 20),
              label: Text(
                _isGenerating ? 'Generating Tally XML...' : 'Generate & Share Tally XML',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E), // Tally Emerald Green
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isGenerating ? null : () => _generateExport(autoShare: false),
              icon: const Icon(Icons.code_rounded, color: Color(0xFF0F766E), size: 20),
              label: const Text(
                'Generate & Preview XML',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0F766E), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          // Generated Summary Card
          if (_summary != null) ...[
            const SizedBox(height: 20),
            _buildSummaryCard(_summary!),
          ],

          const SizedBox(height: 24),
          // How to Import in Tally Instructions
          _buildInstructionsCard(),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.file_download_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tally Prime Direct XML Export',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'Export compliant XML for TallyPrime and Tally.ERP 9. Simply import via "Import Data" in Tally without connectors.',
                  style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF0F766E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(TallyExportSummary s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // Light green tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              const Text(
                'XML File Ready for Tally',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF16A34A)),
                tooltip: 'Copy XML',
                onPressed: _copyToClipboard,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatBox('Sales', '${s.salesCount} bills'),
              const SizedBox(width: 8),
              _buildStatBox('Purchases', '${s.purchaseCount} bills'),
              const SizedBox(width: 8),
              _buildStatBox('Receipts', '${s.receiptCount} rcpts'),
              const SizedBox(width: 8),
              _buildStatBox('Payments', '${s.paymentCount} pays'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total ${s.totalVouchers} vouchers and ${s.ledgerCount} account ledgers generated.',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Share.shareXFiles(
                [XFile(s.file.path)],
                subject: 'Tally Prime XML File',
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send XML via WhatsApp / Email'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF15803D),
                side: const BorderSide(color: Color(0xFF22C55E)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'How to Import in TallyPrime',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
              ),
            ],
          ),
          SizedBox(height: 10),
          _StepText(number: '1', text: 'Transfer the generated XML file to your PC / Laptop.'),
          _StepText(number: '2', text: 'Open TallyPrime and select your company.'),
          _StepText(number: '3', text: 'Go to Top Menu → Import → Transactions (or Masters).'),
          _StepText(number: '4', text: 'Select File format "XML" and choose the exported file.'),
          _StepText(number: '5', text: 'Press Enter to import. All vouchers and ledgers populate instantly!'),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFF0F766E),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : const Color(0xFF475569),
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(
        color: selected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _StepText extends StatelessWidget {
  final String number;
  final String text;

  const _StepText({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
