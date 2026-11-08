import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

/// Shows an action sheet allowing the user to choose between Camera or Gallery,
/// then opens the interactive image cropper, and returns the cropped image path.
Future<String?> pickAndCropSignature(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _SignatureSourceSheet(),
  );

  if (source == null) return null;

  try {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );

    if (picked == null) return null;
    if (!context.mounted) return null;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SignatureCropScreen(imageFile: File(picked.path)),
      ),
    );

    return result;
  } catch (e) {
    if (context.mounted) {
      showAppMessage(context, 'Could not access ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e', error: true);
    }
    return null;
  }
}

/// Allows cropping an already-selected signature file.
Future<String?> cropExistingSignature(BuildContext context, String filePath) async {
  final file = File(filePath);
  final exists = await file.exists();
  if (!context.mounted) return null;
  if (!exists) {
    showAppMessage(context, 'Signature image not found', error: true);
    return null;
  }

  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => SignatureCropScreen(imageFile: file),
    ),
  );
}

class _SignatureSourceSheet extends StatelessWidget {
  const _SignatureSourceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: StitchColors.outlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Add Digital Signature',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: StitchColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose how you want to add your signature or official seal',
            style: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _buildSourceOption(
            context: context,
            icon: Icons.photo_library_rounded,
            title: 'Choose from Gallery',
            subtitle: 'Pick a saved signature image, scan, or stamp from device',
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          _buildSourceOption(
            context: context,
            icon: Icons.camera_alt_rounded,
            title: 'Take Photo with Camera',
            subtitle: 'Snap a picture of a physical paper signature or stamp',
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: StitchColors.textSecondary,
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: StitchColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: StitchColors.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: StitchColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: StitchColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: StitchColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

enum _CropHandle {
  none,
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  right,
  top,
  bottom,
}

class SignatureCropScreen extends StatefulWidget {
  final File imageFile;

  const SignatureCropScreen({super.key, required this.imageFile});

  @override
  State<SignatureCropScreen> createState() => _SignatureCropScreenState();
}

class _SignatureCropScreenState extends State<SignatureCropScreen> {
  bool _loading = true;
  String _loadingMessage = 'Loading signature image...';
  img.Image? _currentImage;
  Uint8List? _previewBytes;

  Rect? _cropRect;
  Rect? _imageRectOnScreen;
  _CropHandle _activeHandle = _CropHandle.none;

  // Presets: 3.0 is standard signature aspect ratio (3:1 width:height)
  double? _aspectRatio = 3.0;
  bool _enhanceContrast = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() {
      _loading = true;
      _loadingMessage = 'Loading image...';
    });

    try {
      final bytes = await widget.imageFile.readAsBytes();
      final loaded = await compute(_decodeAndOrient, bytes);
      if (loaded == null) {
        if (mounted) {
          showAppMessage(context, 'Unable to decode selected image', error: true);
          Navigator.of(context).pop();
        }
        return;
      }

      final preview = Uint8List.fromList(img.encodePng(loaded));

      if (mounted) {
        setState(() {
          _currentImage = loaded;
          _previewBytes = preview;
          _cropRect = null;
          _imageRectOnScreen = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Failed to load image: $e', error: true);
        Navigator.of(context).pop();
      }
    }
  }

  static img.Image? _decodeAndOrient(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    if (oriented.width > 2048 || oriented.height > 2048) {
      final maxDim = oriented.width > oriented.height ? oriented.width : oriented.height;
      final scale = 2048.0 / maxDim;
      return img.copyResize(
        oriented,
        width: (oriented.width * scale).round(),
        height: (oriented.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    return oriented;
  }

  Future<void> _rotate90() async {
    if (_currentImage == null || _loading) return;
    setState(() {
      _loading = true;
      _loadingMessage = 'Rotating...';
    });

    try {
      final rotated = await compute(_rotateImage, _currentImage!);
      final preview = Uint8List.fromList(img.encodePng(rotated));

      if (mounted) {
        setState(() {
          _currentImage = rotated;
          _previewBytes = preview;
          _cropRect = null;
          _imageRectOnScreen = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppMessage(context, 'Rotation failed: $e', error: true);
      }
    }
  }

  static img.Image _rotateImage(img.Image src) {
    return img.copyRotate(src, angle: 90);
  }

  void _resetCrop() {
    if (_imageRectOnScreen == null) return;
    setState(() {
      _cropRect = _calculateInitialCropRect(_imageRectOnScreen!, _aspectRatio);
    });
  }

  void _setAspectRatio(double? ratio) {
    setState(() {
      _aspectRatio = ratio;
      if (_imageRectOnScreen != null) {
        _cropRect = _calculateInitialCropRect(_imageRectOnScreen!, ratio);
      }
    });
  }

  Rect _calculateInitialCropRect(Rect bounds, double? targetAspect) {
    if (targetAspect == null) {
      final w = bounds.width * 0.88;
      final h = bounds.height * 0.88;
      return Rect.fromCenter(center: bounds.center, width: w, height: h);
    }
    double w = bounds.width * 0.88;
    double h = w / targetAspect;
    if (h > bounds.height * 0.88) {
      h = bounds.height * 0.88;
      w = h * targetAspect;
    }
    return Rect.fromCenter(center: bounds.center, width: w, height: h);
  }

  void _onPanStart(DragStartDetails details) {
    if (_cropRect == null || _imageRectOnScreen == null) return;
    final pos = details.localPosition;
    final rect = _cropRect!;
    const hit = 32.0;

    if ((pos - rect.topLeft).distance <= hit) {
      _activeHandle = _CropHandle.topLeft;
    } else if ((pos - rect.topRight).distance <= hit) {
      _activeHandle = _CropHandle.topRight;
    } else if ((pos - rect.bottomLeft).distance <= hit) {
      _activeHandle = _CropHandle.bottomLeft;
    } else if ((pos - rect.bottomRight).distance <= hit) {
      _activeHandle = _CropHandle.bottomRight;
    } else if (_aspectRatio == null && (pos.dy - rect.top).abs() <= 20 && pos.dx >= rect.left && pos.dx <= rect.right) {
      _activeHandle = _CropHandle.top;
    } else if (_aspectRatio == null && (pos.dy - rect.bottom).abs() <= 20 && pos.dx >= rect.left && pos.dx <= rect.right) {
      _activeHandle = _CropHandle.bottom;
    } else if (_aspectRatio == null && (pos.dx - rect.left).abs() <= 20 && pos.dy >= rect.top && pos.dy <= rect.bottom) {
      _activeHandle = _CropHandle.left;
    } else if (_aspectRatio == null && (pos.dx - rect.right).abs() <= 20 && pos.dy >= rect.top && pos.dy <= rect.bottom) {
      _activeHandle = _CropHandle.right;
    } else if (rect.contains(pos)) {
      _activeHandle = _CropHandle.move;
    } else {
      _activeHandle = _CropHandle.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_cropRect == null || _imageRectOnScreen == null || _activeHandle == _CropHandle.none) return;
    final imgBounds = _imageRectOnScreen!;
    final delta = details.delta;
    var rect = _cropRect!;

    const minSize = 40.0;

    if (_activeHandle == _CropHandle.move) {
      double dx = delta.dx;
      double dy = delta.dy;
      if (rect.left + dx < imgBounds.left) dx = imgBounds.left - rect.left;
      if (rect.right + dx > imgBounds.right) dx = imgBounds.right - rect.right;
      if (rect.top + dy < imgBounds.top) dy = imgBounds.top - rect.top;
      if (rect.bottom + dy > imgBounds.bottom) dy = imgBounds.bottom - rect.bottom;
      setState(() {
        _cropRect = rect.shift(Offset(dx, dy));
      });
      return;
    }

    double newLeft = rect.left;
    double newRight = rect.right;
    double newTop = rect.top;
    double newBottom = rect.bottom;

    if (_aspectRatio == null) {
      // Freeform crop
      switch (_activeHandle) {
        case _CropHandle.topLeft:
          newLeft = (rect.left + delta.dx).clamp(imgBounds.left, rect.right - minSize);
          newTop = (rect.top + delta.dy).clamp(imgBounds.top, rect.bottom - minSize);
          break;
        case _CropHandle.topRight:
          newRight = (rect.right + delta.dx).clamp(rect.left + minSize, imgBounds.right);
          newTop = (rect.top + delta.dy).clamp(imgBounds.top, rect.bottom - minSize);
          break;
        case _CropHandle.bottomLeft:
          newLeft = (rect.left + delta.dx).clamp(imgBounds.left, rect.right - minSize);
          newBottom = (rect.bottom + delta.dy).clamp(rect.top + minSize, imgBounds.bottom);
          break;
        case _CropHandle.bottomRight:
          newRight = (rect.right + delta.dx).clamp(rect.left + minSize, imgBounds.right);
          newBottom = (rect.bottom + delta.dy).clamp(rect.top + minSize, imgBounds.bottom);
          break;
        case _CropHandle.left:
          newLeft = (rect.left + delta.dx).clamp(imgBounds.left, rect.right - minSize);
          break;
        case _CropHandle.right:
          newRight = (rect.right + delta.dx).clamp(rect.left + minSize, imgBounds.right);
          break;
        case _CropHandle.top:
          newTop = (rect.top + delta.dy).clamp(imgBounds.top, rect.bottom - minSize);
          break;
        case _CropHandle.bottom:
          newBottom = (rect.bottom + delta.dy).clamp(rect.top + minSize, imgBounds.bottom);
          break;
        default:
          break;
      }
    } else {
      // Locked aspect ratio crop
      final ratio = _aspectRatio!;
      switch (_activeHandle) {
        case _CropHandle.bottomRight:
          final reqW = (rect.right + delta.dx - rect.left).clamp(minSize, imgBounds.right - rect.left);
          final reqH = reqW / ratio;
          if (rect.top + reqH <= imgBounds.bottom) {
            newRight = rect.left + reqW;
            newBottom = rect.top + reqH;
          }
          break;
        case _CropHandle.bottomLeft:
          final reqW = (rect.right - (rect.left + delta.dx)).clamp(minSize, rect.right - imgBounds.left);
          final reqH = reqW / ratio;
          if (rect.top + reqH <= imgBounds.bottom) {
            newLeft = rect.right - reqW;
            newBottom = rect.top + reqH;
          }
          break;
        case _CropHandle.topRight:
          final reqW = (rect.right + delta.dx - rect.left).clamp(minSize, imgBounds.right - rect.left);
          final reqH = reqW / ratio;
          if (rect.bottom - reqH >= imgBounds.top) {
            newRight = rect.left + reqW;
            newTop = rect.bottom - reqH;
          }
          break;
        case _CropHandle.topLeft:
          final reqW = (rect.right - (rect.left + delta.dx)).clamp(minSize, rect.right - imgBounds.left);
          final reqH = reqW / ratio;
          if (rect.bottom - reqH >= imgBounds.top) {
            newLeft = rect.right - reqW;
            newTop = rect.bottom - reqH;
          }
          break;
        default:
          break;
      }
    }

    setState(() {
      _cropRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = _CropHandle.none;
  }

  Future<void> _saveCrop() async {
    if (_currentImage == null || _cropRect == null || _imageRectOnScreen == null || _loading) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Cropping and saving signature...';
    });

    try {
      final img = _currentImage!;
      final imageRect = _imageRectOnScreen!;
      final crop = _cropRect!;

      final scaleX = img.width / imageRect.width;
      final scaleY = img.height / imageRect.height;

      final pixelX = ((crop.left - imageRect.left) * scaleX).round().clamp(0, img.width - 1);
      final pixelY = ((crop.top - imageRect.top) * scaleY).round().clamp(0, img.height - 1);
      final pixelW = (crop.width * scaleX).round().clamp(1, img.width - pixelX);
      final pixelH = (crop.height * scaleY).round().clamp(1, img.height - pixelY);

      final cropParams = _CropJobParams(
        image: img,
        x: pixelX,
        y: pixelY,
        width: pixelW,
        height: pixelH,
        enhanceContrast: _enhanceContrast,
      );

      final pngBytes = await compute(_performCrop, cropParams);

      final appDir = await getApplicationDocumentsDirectory();
      final sigDir = Directory('${appDir.path}/signatures');
      if (!await sigDir.exists()) {
        await sigDir.create(recursive: true);
      }

      final savedFile = File('${sigDir.path}/signature_${DateTime.now().millisecondsSinceEpoch}.png');
      await savedFile.writeAsBytes(pngBytes);

      if (mounted) {
        showAppMessage(context, 'Signature cropped successfully ✓');
        Navigator.of(context).pop(savedFile.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppMessage(context, 'Cropping failed: $e', error: true);
      }
    }
  }

  static Uint8List _performCrop(_CropJobParams params) {
    final cropped = img.copyCrop(
      params.image,
      x: params.x,
      y: params.y,
      width: params.width,
      height: params.height,
    );

    final result = params.enhanceContrast ? img.contrast(cropped, contrast: 135) : cropped;
    return Uint8List.fromList(img.encodePng(result));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Crop Signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
            tooltip: 'Rotate 90°',
            onPressed: _loading ? null : _rotate90,
          ),
          IconButton(
            icon: Icon(
              _enhanceContrast ? Icons.auto_fix_high : Icons.auto_fix_normal_outlined,
              color: _enhanceContrast ? const Color(0xFF38BDF8) : Colors.white,
            ),
            tooltip: 'Enhance Paper Contrast',
            onPressed: () {
              setState(() => _enhanceContrast = !_enhanceContrast);
              showAppMessage(
                context,
                _enhanceContrast ? 'Contrast boost enabled (crisp ink)' : 'Original contrast restored',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reset Crop',
            onPressed: _loading ? null : _resetCrop,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          Text(_loadingMessage, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
                        if (_currentImage != null && (_imageRectOnScreen == null || _cropRect == null)) {
                          final fitted = applyBoxFit(
                            BoxFit.contain,
                            Size(_currentImage!.width.toDouble(), _currentImage!.height.toDouble()),
                            containerSize,
                          );
                          final renderedSize = fitted.destination;
                          final imgOffset = Offset(
                            (containerSize.width - renderedSize.width) / 2,
                            (containerSize.height - renderedSize.height) / 2,
                          );
                          _imageRectOnScreen = Rect.fromLTWH(
                            imgOffset.dx,
                            imgOffset.dy,
                            renderedSize.width,
                            renderedSize.height,
                          );
                          _cropRect = _calculateInitialCropRect(_imageRectOnScreen!, _aspectRatio);
                        }

                        return GestureDetector(
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_previewBytes != null && _imageRectOnScreen != null)
                                Positioned(
                                  left: _imageRectOnScreen!.left,
                                  top: _imageRectOnScreen!.top,
                                  width: _imageRectOnScreen!.width,
                                  height: _imageRectOnScreen!.height,
                                  child: Image.memory(
                                    _previewBytes!,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              if (_cropRect != null && _imageRectOnScreen != null)
                                CustomPaint(
                                  size: containerSize,
                                  painter: _CropOverlayPainter(
                                    cropRect: _cropRect!,
                                    imageRect: _imageRectOnScreen!,
                                    activeHandle: _activeHandle,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Bottom Controls Bar
            Container(
              color: const Color(0xFF111827),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Aspect Ratio Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildRatioPill('Signature (3:1)', 3.0),
                        const SizedBox(width: 8),
                        _buildRatioPill('Free Crop', null),
                        const SizedBox(width: 8),
                        _buildRatioPill('Box (4:3)', 4 / 3),
                        const SizedBox(width: 8),
                        _buildRatioPill('Square (1:1)', 1.0),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Crop & Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _saveCrop,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        'Apply & Save Signature',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: StitchColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioPill(String label, double? ratio) {
    final isSelected = (_aspectRatio == ratio);
    return InkWell(
      onTap: () => _setAspectRatio(ratio),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? StitchColors.primary : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? StitchColors.primary : const Color(0xFF374151),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}

class _CropJobParams {
  final img.Image image;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool enhanceContrast;

  _CropJobParams({
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.enhanceContrast,
  });
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Rect imageRect;
  final _CropHandle activeHandle;

  _CropOverlayPainter({
    required this.cropRect,
    required this.imageRect,
    required this.activeHandle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Dim mask outside cropRect
    final scrimPath = Path()
      ..addRect(fullRect)
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    // White crop border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(cropRect, borderPaint);

    // 3x3 Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final w3 = cropRect.width / 3;
    final h3 = cropRect.height / 3;

    canvas.drawLine(Offset(cropRect.left + w3, cropRect.top), Offset(cropRect.left + w3, cropRect.bottom), gridPaint);
    canvas.drawLine(Offset(cropRect.left + 2 * w3, cropRect.top), Offset(cropRect.left + 2 * w3, cropRect.bottom), gridPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.top + h3), Offset(cropRect.right, cropRect.top + h3), gridPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.top + 2 * h3), Offset(cropRect.right, cropRect.top + 2 * h3), gridPaint);

    // Corner brackets
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cLen = 18.0;

    // Top-Left
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(cLen, 0), cornerPaint);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, cLen), cornerPaint);

    // Top-Right
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-cLen, 0), cornerPaint);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, cLen), cornerPaint);

    // Bottom-Left
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(cLen, 0), cornerPaint);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -cLen), cornerPaint);

    // Bottom-Right
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-cLen, 0), cornerPaint);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -cLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.activeHandle != activeHandle;
  }
}
