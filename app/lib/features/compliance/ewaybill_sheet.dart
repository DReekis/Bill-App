import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/compliance_service.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/subscription_service.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../subscription/upgrade_paywall_sheet.dart';
import 'ewaybill_slip_screen.dart';

class EWayBillSheet extends StatefulWidget {
  const EWayBillSheet({
    super.key,
    required this.business,
    required this.invoice,
    this.customer,
    required this.onUpdated,
  });

  final Business business;
  final Invoice invoice;
  final Customer? customer;
  final VoidCallback onUpdated;

  static Future<void> show(
    BuildContext context, {
    required Business business,
    required Invoice invoice,
    Customer? customer,
    required VoidCallback onUpdated,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EWayBillSheet(
        business: business,
        invoice: invoice,
        customer: customer,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<EWayBillSheet> createState() => _EWayBillSheetState();
}

class _EWayBillSheetState extends State<EWayBillSheet> {
  final _distCtrl = TextEditingController(text: '50');
  final _vehicleCtrl = TextEditingController();
  final _transporterCtrl = TextEditingController();
  final _docNoCtrl = TextEditingController();
  String _transportMode = 'Road';
  final String _vehicleType = 'R';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.invoice.vehicleNumber != null) {
      _vehicleCtrl.text = widget.invoice.vehicleNumber!;
    }
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _vehicleCtrl.dispose();
    _transporterCtrl.dispose();
    _docNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!SubscriptionService.instance.canAccessEInvoice) {
      UpgradePaywallSheet.show(
        context,
        featureName: 'E-Way Bill Automation',
        description: 'Generate statutory Government E-Way bills with real-time tracking and printable Form EWB-01 slips.',
        requiredTier: SubscriptionTier.gold,
        bulletPoints: const [
          'Direct Sandbox.co.in E-Way Bill Gateway',
          'Automatic Part A & Part B vehicle updates',
          'Printable NIC Form EWB-01 slip export',
          '24-Hour statutory cancellation management',
        ],
      );
      return;
    }

    final vehicle = _vehicleCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    if (vehicle.isEmpty) {
      showAppMessage(context, 'Vehicle number is required (e.g. KA01AB1234)', error: true);
      return;
    }
    final distance = int.tryParse(_distCtrl.text.trim()) ?? 0;
    if (distance <= 0) {
      showAppMessage(context, 'Distance must be at least 1 KM', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      final client = session.token != null ? session.client : null;
      await ComplianceService.instance.generateEWayBill(
        business: widget.business,
        invoice: widget.invoice,
        distanceKm: distance,
        vehicleNo: vehicle,
        transportMode: _transportMode,
        vehicleType: _vehicleType,
        transporterName: _transporterCtrl.text.trim().isNotEmpty ? _transporterCtrl.text.trim() : null,
        transDocNo: _docNoCtrl.text.trim().isNotEmpty ? _docNoCtrl.text.trim() : null,
        customer: widget.customer,
        apiClient: client,
      );
      if (mounted) {
        showAppMessage(context, 'E-Way Bill generated successfully ✓');
        widget.onUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'E-Way Bill error: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selectedReason = '2';
        final remarksCtrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: StitchColors.error, size: 22),
              SizedBox(width: 8),
              Text('Cancel E-Way Bill?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: StatefulBuilder(
            builder: (ctx, setDlgState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Under GST rules, an E-Way Bill can be cancelled within 24 hours of generation if goods were not transported.',
                  style: TextStyle(fontSize: 12.5, color: StitchColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 14),
                const Text('Cancellation Reason:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('1. Duplicate entry')),
                    DropdownMenuItem(value: '2', child: Text('2. Order Cancelled')),
                    DropdownMenuItem(value: '3', child: Text('3. Data entry error')),
                    DropdownMenuItem(value: '4', child: Text('4. Other reasons')),
                  ],
                  onChanged: (val) => setDlgState(() => selectedReason = val ?? '2'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarksCtrl,
                  decoration: InputDecoration(
                    labelText: 'Remarks (Optional)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Back'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: StitchColors.error),
              onPressed: () => Navigator.pop(ctx, selectedReason),
              child: const Text('Confirm Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != null && mounted) {
      setState(() => _busy = true);
      try {
        final session = context.read<Session>();
        final client = session.token != null ? session.client : null;
        await ComplianceService.instance.cancelEWayBill(
          businessId: widget.business.id!,
          invoice: widget.invoice,
          reason: confirmed,
          apiClient: client,
        );
        if (mounted) {
          showAppMessage(context, 'E-Way Bill cancelled successfully.');
          widget.onUpdated();
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          showAppMessage(context, 'Cancellation failed: $e', error: true);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showAppMessage(context, '$label copied to clipboard ✓');
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final hasEwb = inv.hasEWayBill;
    final isCancelled = inv.ewbStatus == 'CNL';
    final ewbNo = inv.ewayBillNumber ?? '';
    final ewbDate = inv.ewbDate ?? '—';
    final validUntil = inv.ewbValidUntil ?? '—';
    final vehicleNo = inv.vehicleNumber ?? _vehicleCtrl.text;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasEwb ? const Color(0xFFEFF6FF) : StitchColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasEwb ? Icons.local_shipping_rounded : Icons.local_shipping_outlined,
                      color: hasEwb ? const Color(0xFF2563EB) : StitchColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Government E-Way Bill',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                        ),
                        Text(
                          hasEwb
                              ? (isCancelled ? 'Status: Cancelled' : 'EWB Active • Form EWB-01')
                              : 'Goods Movement Authorization (Part A & B)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isCancelled
                                ? StitchColors.error
                                : (hasEwb ? const Color(0xFF2563EB) : StitchColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 16),
                        Text('Generating E-Way Bill with NIC Gateway...', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else if (hasEwb) ...[
                // Active E-Way Bill Card
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // EWB Number Box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '12-Digit E-Way Bill Number',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                                  ),
                                  GestureDetector(
                                    onTap: () => _copy(ewbNo, 'E-Way Bill Number'),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.copy_rounded, size: 14, color: Color(0xFF16A34A)),
                                        SizedBox(width: 4),
                                        Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                ewbNo,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFF14532D)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Transport & Validity Grid
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow('Vehicle Number', vehicleNo),
                              const Divider(height: 16),
                              _buildDetailRow('Generated On', ewbDate),
                              const Divider(height: 16),
                              _buildDetailRow('Valid Until', validUntil),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Actions
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('View Form EWB-01 Slip', style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EWayBillSlipScreen(
                                  business: widget.business,
                                  invoice: widget.invoice,
                                  customer: widget.customer,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        if (!isCancelled)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: StitchColors.error,
                              side: const BorderSide(color: StitchColors.error),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel E-Way Bill (Within 24h)', style: TextStyle(fontWeight: FontWeight.w700)),
                            onPressed: _cancel,
                          ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Creation Form
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Vehicle Number
                        AppTextField(
                          controller: _vehicleCtrl,
                          label: 'Vehicle Number *',
                          hint: 'e.g. KA01AB1234',
                          icon: Icons.directions_car_outlined,
                        ),
                        const SizedBox(height: 12),

                        // Distance & Mode Row
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _distCtrl,
                                label: 'Distance (KM) *',
                                hint: '50',
                                keyboardType: TextInputType.number,
                                icon: Icons.straighten_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _transportMode,
                                decoration: InputDecoration(
                                  labelText: 'Transport Mode',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'Road', child: Text('Road')),
                                  DropdownMenuItem(value: 'Rail', child: Text('Rail')),
                                  DropdownMenuItem(value: 'Air', child: Text('Air')),
                                  DropdownMenuItem(value: 'Ship', child: Text('Ship')),
                                ],
                                onChanged: (v) => setState(() => _transportMode = v ?? 'Road'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Transporter Name & LR No Row
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _transporterCtrl,
                                label: 'Transporter Name (Optional)',
                                hint: 'e.g. VRL Logistics',
                                icon: Icons.business_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AppTextField(
                                controller: _docNoCtrl,
                                label: 'LR / RR No (Optional)',
                                hint: 'e.g. LR-9081',
                                icon: Icons.receipt_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.bolt_rounded),
                          label: const Text('Generate E-Way Bill (1-Tap)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          onPressed: _generate,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: StitchColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.textPrimary)),
      ],
    );
  }
}
