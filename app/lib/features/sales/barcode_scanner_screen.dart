import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../inventory/product_form.dart';

/// Camera barcode scanner for rapid counter POS item lookup.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  final TextEditingController _manualInputController = TextEditingController();
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String rawCode) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Audio click & haptic feedback for real POS hardware feel
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    final cleanCode = rawCode.trim();
    final session = context.read<Session>();
    final bizId = session.businessId;

    if (bizId == null) {
      setState(() => _isProcessing = false);
      return;
    }

    try {
      final all = await Repository.instance.products(bizId);
      Product? found;
      for (final p in all) {
        if (p.barcode?.trim() == cleanCode ||
            p.sku?.trim() == cleanCode ||
            p.itemCode?.trim() == cleanCode) {
          found = p;
          break;
        }
      }

      if (!mounted) return;

      if (found != null) {
        // Product matched
        Navigator.pop(context, found);
      } else {
        // Unrecognized barcode — offer quick product registration
        await _showNotFoundSheet(cleanCode);
        if (mounted) setState(() => _isProcessing = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showNotFoundSheet(String code) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StitchColors.warning.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: StitchColors.warning, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Unrecognized Barcode',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'No product in your catalogue matches code "$code".',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: StitchColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Scan Again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Product'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _registerNewWithBarcode(code);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerNewWithBarcode(String code) async {
    final session = context.read<Session>();
    final bizId = session.businessId!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ProductFormSheet(
        businessId: bizId,
        initialBarcode: code,
        onSaved: () async {},
        onSavedProduct: (newProd) {
          Navigator.pop(ctx);
          if (mounted) {
            Navigator.pop(context, newProd);
          }
        },
      ),
    );
  }

  void _manualSearch() {
    final code = _manualInputController.text.trim();
    if (code.isNotEmpty) {
      _handleBarcode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Barcode Scanner', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Toggle Flashlight',
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? Colors.amber : Colors.white,
            ),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Live Camera Stream
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final b in barcodes) {
                if (b.rawValue != null && b.rawValue!.isNotEmpty) {
                  _handleBarcode(b.rawValue!);
                  break;
                }
              }
            },
          ),

          // Reticle Overlay
          Positioned.fill(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: Colors.black.withValues(alpha: 0.6),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.crop_free_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Align barcode within frame',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Centered Viewfinder Window
                Center(
                  child: SizedBox(
                    width: 270,
                    height: 200,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: StitchColors.primary, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        // Animated Scanning Line
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            return Positioned(
                              top: _animController.value * 180 + 10,
                              left: 10,
                              right: 10,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  color: StitchColors.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: StitchColors.primary.withValues(alpha: 0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),

                // Manual Input Fallback Dock
                Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    MediaQuery.of(context).padding.bottom + 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualInputController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: 'Enter barcode or SKU manually',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            prefixIcon: const Icon(Icons.keyboard_outlined, color: Colors.white70, size: 20),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (_) => _manualSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _manualSearch,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
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
