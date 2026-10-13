import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/physical_barcode_scanner.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../inventory/product_form.dart';

/// Interactive diagnostic sheet allowing merchants to verify and test
/// their wired USB or wireless Bluetooth physical barcode scanners.
class HardwareScannerDialog extends StatefulWidget {
  const HardwareScannerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HardwareScannerDialog(),
    );
  }

  @override
  State<HardwareScannerDialog> createState() => _HardwareScannerDialogState();
}

class _HardwareScannerDialogState extends State<HardwareScannerDialog> {
  BarcodeScanResult? _latestResult;
  Product? _matchedProduct;
  bool _searchingProduct = false;
  final List<BarcodeScanResult> _history = [];

  @override
  void initState() {
    super.initState();
    PhysicalBarcodeScanner.instance.addListener(_onBarcodeScanned);
    _latestResult = PhysicalBarcodeScanner.instance.lastScan.value;
    if (_latestResult != null) {
      _lookupProduct(_latestResult!.barcode);
    }
  }

  @override
  void dispose() {
    PhysicalBarcodeScanner.instance.removeListener(_onBarcodeScanned);
    super.dispose();
  }

  void _onBarcodeScanned(BarcodeScanResult result) {
    if (!mounted) return;
    setState(() {
      _latestResult = result;
      _history.insert(0, result);
      if (_history.length > 5) _history.removeLast();
    });
    _lookupProduct(result.barcode);
  }

  Future<void> _lookupProduct(String barcode) async {
    final session = context.read<Session>();
    final bizId = session.businessId;
    if (bizId == null) return;

    setState(() => _searchingProduct = true);
    try {
      final all = await Repository.instance.products(bizId);
      Product? found;
      final clean = barcode.trim().toLowerCase();
      for (final p in all) {
        if ((p.barcode?.trim().toLowerCase() ?? '') == clean ||
            (p.sku?.trim().toLowerCase() ?? '') == clean ||
            (p.itemCode?.trim().toLowerCase() ?? '') == clean) {
          found = p;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _matchedProduct = found;
          _searchingProduct = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searchingProduct = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle & Header
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StitchColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: StitchColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Physical Barcode Scanner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: StitchColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Active & Ready (Wired USB / Bluetooth HID)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Live Test Area Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _latestResult != null
                      ? StitchColors.primary
                      : const Color(0xFFE2E8F0),
                  width: _latestResult != null ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LIVE TEST STATUS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: StitchColors.textSecondary,
                        ),
                      ),
                      if (_latestResult != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StitchColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_latestResult!.charCount} chars · ${_latestResult!.averageInterKeyMs.toStringAsFixed(1)}ms/char',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: StitchColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_latestResult == null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          color: StitchColors.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Pull the trigger on your scanner gun or pass an item over your desktop scanner now.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      _latestResult!.barcode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: StitchColors.textPrimary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_searchingProduct) ...[
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Checking catalog...',
                            style: TextStyle(
                              fontSize: 12,
                              color: StitchColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ] else if (_matchedProduct != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF16A34A),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _matchedProduct!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                  Text(
                                    'Sale Price: ₹${(_matchedProduct!.salePrice / 100).toStringAsFixed(2)} · Stock: ${_matchedProduct!.stock}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFFD97706),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Barcode received successfully, but item is not yet in your product catalog.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                final bizId = context.read<Session>().businessId;
                                if (bizId == null) return;
                                final code = _latestResult!.barcode;
                                Navigator.pop(context);
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => ProductFormSheet(
                                    businessId: bizId,
                                    initialBarcode: code,
                                    onSaved: () async {},
                                    onSavedProduct: (prod) {},
                                  ),
                                );
                              },
                              child: const Text('Add Item'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // How to Connect Guide
            const Text(
              'How to Connect Physical Scanners',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: StitchColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _buildGuideTile(
              icon: Icons.usb_rounded,
              title: 'Wired USB Scanners (Plug & Play)',
              subtitle:
                  'Plug the USB cable directly into your computer or POS counter terminal. On Android phones/tablets, use a simple USB-OTG adapter. No software or drivers needed.',
            ),
            const SizedBox(height: 8),
            _buildGuideTile(
              icon: Icons.bluetooth_rounded,
              title: 'Bluetooth Wireless Scanners',
              subtitle:
                  'Turn on your wireless scanner in Bluetooth HID mode (default on Honeywell, Zebra, Eyoyo, Netum). Go to device Settings > Bluetooth, pair the device, and start scanning directly.',
            ),
            const SizedBox(height: 8),
            _buildGuideTile(
              icon: Icons.flash_on_rounded,
              title: 'Hands-Free Invoice Counter Mode',
              subtitle:
                  'Inside the Invoice Creation screen, pull the trigger on any scanned item to add it to the bill instantly or increment its quantity without opening the camera view.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: StitchColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Got It, Ready to Bill'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: StitchColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: StitchColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: StitchColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: StitchColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
