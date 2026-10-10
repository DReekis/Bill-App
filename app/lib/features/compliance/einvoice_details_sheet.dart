import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/compliance_service.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/subscription_service.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../subscription/upgrade_paywall_sheet.dart';

class EInvoiceDetailsSheet extends StatefulWidget {
  const EInvoiceDetailsSheet({
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
      builder: (ctx) => EInvoiceDetailsSheet(
        business: business,
        invoice: invoice,
        customer: customer,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<EInvoiceDetailsSheet> createState() => _EInvoiceDetailsSheetState();
}

class _EInvoiceDetailsSheetState extends State<EInvoiceDetailsSheet> {
  bool _busy = false;

  Future<void> _generate() async {
    // Check subscription entitlement
    if (!SubscriptionService.instance.canAccessEInvoice) {
      UpgradePaywallSheet.show(
        context,
        featureName: 'E-Invoice (IRN) Generation',
        description: 'Generate Government-compliant E-Invoices with real-time IRN and signed QR codes directly from your device.',
        requiredTier: SubscriptionTier.gold,
        bulletPoints: const [
          'Direct Sandbox.co.in GSP Integration',
          'Instant IRN generation adhering to NIC Schema v1.03',
          'Automatic Signed QR Code printing on PDF bills',
          '24-Hour statutory cancellation support',
        ],
      );
      return;
    }

    final validationErr = ComplianceService.validateForEInvoice(
      widget.business,
      widget.invoice,
      customer: widget.customer,
    );

    if (validationErr != null) {
      showAppMessage(context, validationErr, error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      final client = session.token != null ? session.client : null;
      await ComplianceService.instance.generateEInvoice(
        business: widget.business,
        invoice: widget.invoice,
        customer: widget.customer,
        apiClient: client,
      );
      if (mounted) {
        showAppMessage(context, 'E-Invoice IRN generated successfully ✓');
        widget.onUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'E-Invoice generation error: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selectedReason = '3';
        final remarksCtrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: StitchColors.error, size: 22),
              SizedBox(width: 8),
              Text('Cancel E-Invoice IRN?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: StatefulBuilder(
            builder: (ctx, setDlgState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Per GSTN rules, an IRN can only be cancelled within 24 hours of generation. Once cancelled, this invoice number cannot be re-used for E-Invoicing.',
                  style: TextStyle(fontSize: 12.5, color: StitchColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 14),
                const Text('Select Cancellation Reason:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('1. Duplicate entry')),
                    DropdownMenuItem(value: '2', child: Text('2. Data entry error')),
                    DropdownMenuItem(value: '3', child: Text('3. Order cancelled')),
                    DropdownMenuItem(value: '4', child: Text('4. Other reasons')),
                  ],
                  onChanged: (val) => setDlgState(() => selectedReason = val ?? '3'),
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
        await ComplianceService.instance.cancelEInvoice(
          businessId: widget.business.id!,
          invoice: widget.invoice,
          reason: confirmed,
          apiClient: client,
        );
        if (mounted) {
          showAppMessage(context, 'E-Invoice IRN cancelled successfully.');
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
    final hasIrn = inv.hasEInvoice;
    final isCancelled = inv.einvoiceStatus == 'CNL';
    final irn = inv.irn ?? '';
    final ackNo = inv.ackNo ?? '—';
    final ackDate = inv.ackDate ?? '—';
    final qrData = inv.signedQrCode ?? '';

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
                      color: hasIrn ? StitchColors.successSoft : StitchColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasIrn ? Icons.verified_rounded : Icons.receipt_long_rounded,
                      color: hasIrn ? StitchColors.success : StitchColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Government E-Invoice',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                        ),
                        Text(
                          hasIrn
                              ? (isCancelled ? 'Status: Cancelled' : 'IRN Active • NIC Schema v1.03')
                              : 'Invoice Reference Number (IRN)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isCancelled
                                ? StitchColors.error
                                : (hasIrn ? StitchColors.success : StitchColors.textSecondary),
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
                        Text('Connecting to Government Compliance Gateway...', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else if (hasIrn) ...[
                // Active E-Invoice Card
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // IRN Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Invoice Reference Number (IRN)',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.textSecondary),
                                  ),
                                  GestureDetector(
                                    onTap: () => _copy(irn, 'IRN'),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.copy_rounded, size: 14, color: StitchColors.primary),
                                        SizedBox(width: 4),
                                        Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                irn,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: StitchColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Acknowledgement Row
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ack Number', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                    const SizedBox(height: 4),
                                    Text(ackNo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ack Date', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                                    const SizedBox(height: 4),
                                    Text(ackDate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // QR Code Preview
                        if (qrData.isNotEmpty) ...[
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
                                ],
                              ),
                              child: Column(
                                children: [
                                  QrImageView(
                                    data: qrData,
                                    version: QrVersions.auto,
                                    size: 140.0,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Signed NIC Barcode QR',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Actions
                        if (!isCancelled) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: StitchColors.error,
                              side: const BorderSide(color: StitchColors.error),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel E-Invoice (Within 24h)', style: TextStyle(fontWeight: FontWeight.w700)),
                            onPressed: _cancel,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Unregistered / Not Generated State
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Generate a cryptographically signed Invoice Reference Number (IRN) and QR code conforming to official NIC Schema v1.03 for B2B transactions.',
                                style: TextStyle(fontSize: 12.5, color: Color(0xFF166534), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildInfoRow('Seller GSTIN', widget.business.gstin ?? 'Not set in profile'),
                      _buildInfoRow('Buyer GSTIN', widget.customer?.gstin ?? 'Missing on customer record'),
                      _buildInfoRow('Invoice Value', '₹${(widget.invoice.total / 100).toStringAsFixed(2)}'),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: StitchColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.bolt_rounded),
                        label: const Text('Generate E-Invoice (1-Tap)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        onPressed: _generate,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: StitchColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: StitchColors.textPrimary)),
        ],
      ),
    );
  }
}
