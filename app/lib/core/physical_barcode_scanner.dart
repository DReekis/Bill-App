import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents the metadata and timing analysis of a physical barcode scan.
class BarcodeScanResult {
  const BarcodeScanResult({
    required this.barcode,
    required this.charCount,
    required this.totalDuration,
    required this.averageInterKeyMs,
    required this.scannedAt,
    this.source = 'physical_hid',
  });

  final String barcode;
  final int charCount;
  final Duration totalDuration;
  final double averageInterKeyMs;
  final DateTime scannedAt;
  final String source;

  @override
  String toString() =>
      'BarcodeScanResult(barcode: $barcode, chars: $charCount, avgMs: ${averageInterKeyMs.toStringAsFixed(1)})';
}

/// Helper record for tracking individual keystrokes in the buffer.
class _BufferedKey {
  _BufferedKey(this.character, this.timestamp, this.eventTimeStamp);
  final String character;
  final DateTime timestamp;
  final Duration eventTimeStamp;
}

/// Core service that intercepts rapid hardware keystrokes from USB wired,
/// 2.4GHz wireless dongle, and Bluetooth HID barcode scanners.
class PhysicalBarcodeScanner {
  PhysicalBarcodeScanner._();
  static final PhysicalBarcodeScanner instance = PhysicalBarcodeScanner._();

  final List<_BufferedKey> _buffer = [];
  final List<ValueChanged<BarcodeScanResult>> _listeners = [];
  bool _isListening = false;

  /// ValueNotifier exposing the most recent scan result (for UI status & diagnostics).
  final ValueNotifier<BarcodeScanResult?> lastScan = ValueNotifier<BarcodeScanResult?>(null);

  /// Clock provider (overridable in unit tests)
  @visibleForTesting
  DateTime Function() nowProvider = DateTime.now;

  /// Maximum allowed delay between characters for non-focused idle state.
  static const Duration idleInterKeyTimeout = Duration(milliseconds: 650);

  /// Maximum allowed average delay between characters when an EditableText has focus.
  /// Barcode scanners typically emit keys every 5-30ms. Fast humans type > 80ms.
  static const double maxScannerBurstAverageMs = 60.0;

  /// Minimum characters required for a valid barcode.
  static const int minBarcodeLength = 2;

  /// Starts listening to global hardware keyboard events.
  void start() {
    if (_isListening) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _isListening = true;
  }

  /// Stops listening to global hardware keyboard events.
  void stop() {
    if (!_isListening) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isListening = false;
    _buffer.clear();
  }

  /// Adds a listener for barcode scan events.
  void addListener(ValueChanged<BarcodeScanResult> listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
    if (!_isListening) {
      start();
    }
  }

  /// Removes an active listener.
  void removeListener(ValueChanged<BarcodeScanResult> listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      stop();
    }
  }

  /// Checks whether an EditableText widget currently has primary focus.
  static bool isEditableFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    if (focus.debugLabel == 'EditableText') return true;
    final ctx = focus.context;
    if (ctx != null) {
      if (ctx.widget is EditableText) return true;
      if (ctx.findAncestorStateOfType<EditableTextState>() != null) return true;
      final widget = ctx.widget;
      if (widget is Focus && widget.debugLabel == 'EditableText') return true;
    }
    return false;
  }

  /// Extracts printable character from KeyEvent across platforms & keyboards.
  static String? extractPrintableChar(KeyEvent event) {
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      final code = char.codeUnitAt(0);
      // Printable ASCII (space to tilde), ignoring raw control characters
      if (code >= 32 && code <= 126) {
        return char;
      }
    }

    // Fallback mapping for special keys if event.character is null
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.numpad0) return '0';
    if (key == LogicalKeyboardKey.numpad1) return '1';
    if (key == LogicalKeyboardKey.numpad2) return '2';
    if (key == LogicalKeyboardKey.numpad3) return '3';
    if (key == LogicalKeyboardKey.numpad4) return '4';
    if (key == LogicalKeyboardKey.numpad5) return '5';
    if (key == LogicalKeyboardKey.numpad6) return '6';
    if (key == LogicalKeyboardKey.numpad7) return '7';
    if (key == LogicalKeyboardKey.numpad8) return '8';
    if (key == LogicalKeyboardKey.numpad9) return '9';

    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) return '-';
    if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) return '.';
    if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) return '/';
    if (key == LogicalKeyboardKey.numpadMultiply) return '*';
    if (key == LogicalKeyboardKey.numpadAdd) return '+';

    if (key.keyLabel.length == 1) {
      final code = key.keyLabel.codeUnitAt(0);
      if (code >= 32 && code <= 126) {
        return key.keyLabel;
      }
    }
    return null;
  }

  /// Determines if the key is a terminator (Enter, Numpad Enter, Tab, \n, \r).
  static bool isTerminatorKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      return true;
    }
    final char = event.character;
    if (char == '\n' || char == '\r' || char == '\t') {
      return true;
    }
    return false;
  }

  /// Internal handler for hardware key events.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }

    final now = nowProvider();

    // Check terminator key (End of barcode transmission)
    if (isTerminatorKey(event)) {
      if (_buffer.length >= minBarcodeLength) {
        final totalDurationFromEvent = _buffer.last.eventTimeStamp - _buffer.first.eventTimeStamp;
        final totalDurationFromWallClock = _buffer.last.timestamp.difference(_buffer.first.timestamp);
        final totalDuration = totalDurationFromEvent.inMilliseconds > 0
            ? totalDurationFromEvent
            : totalDurationFromWallClock;
        final avgMs = _buffer.length > 1
            ? totalDuration.inMilliseconds / (_buffer.length - 1)
            : 0.0;

        final isFocused = isEditableFocused();

        // If an editable input has focus, only intercept if it was a true scanner burst
        if (isFocused && avgMs > maxScannerBurstAverageMs) {
          // Manual typing by human into text field: do not intercept
          _buffer.clear();
          return false;
        }

        final rawBarcode = _buffer.map((k) => k.character).join();
        final result = BarcodeScanResult(
          barcode: rawBarcode.trim(),
          charCount: _buffer.length,
          totalDuration: totalDuration,
          averageInterKeyMs: avgMs,
          scannedAt: now,
        );

        _buffer.clear();

        // Notify subscribers
        _dispatchScan(result);

        // Consume event so Enter doesn't trigger secondary actions
        return true;
      }
      _buffer.clear();
      return false;
    }

    // Printable character key
    final char = extractPrintableChar(event);
    if (char != null) {
      // If buffer has stale keys (exceeded idle timeout), clear buffer
      if (_buffer.isNotEmpty) {
        final lastTime = _buffer.last.timestamp;
        final lastEventTime = _buffer.last.eventTimeStamp;
        final eventDiff = event.timeStamp - lastEventTime;
        final wallDiff = now.difference(lastTime);
        final elapsed = eventDiff.inMilliseconds > 0 ? eventDiff : wallDiff;
        if (elapsed > idleInterKeyTimeout) {
          _buffer.clear();
        }
      }

      _buffer.add(_BufferedKey(char, now, event.timeStamp));

      // If no text field is focused, we can consume the printable character
      // so it doesn't trigger unexpected shortcut keys.
      if (!isEditableFocused()) {
        return true;
      }
    }

    return false;
  }

  void _dispatchScan(BarcodeScanResult result) {
    lastScan.value = result;

    // Trigger audio & haptic feedback for realistic hardware confirmation
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    // Copy to avoid concurrent modification
    final listenersCopy = List<ValueChanged<BarcodeScanResult>>.from(_listeners);
    for (final listener in listenersCopy) {
      listener(result);
    }
  }

  /// Manually dispatches a barcode (useful for testing and camera scanner fallback).
  void dispatchManual(String barcode, {String source = 'manual'}) {
    final clean = barcode.trim();
    if (clean.isEmpty) return;

    final result = BarcodeScanResult(
      barcode: clean,
      charCount: clean.length,
      totalDuration: Duration.zero,
      averageInterKeyMs: 0.0,
      scannedAt: DateTime.now(),
      source: source,
    );
    _dispatchScan(result);
  }
}

/// A reactive widget that listens to physical barcode scanner input
/// (wired USB or wireless Bluetooth HID) and invokes [onBarcodeScanned].
class PhysicalBarcodeScannerListener extends StatefulWidget {
  const PhysicalBarcodeScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<String> onBarcodeScanned;
  final bool enabled;

  @override
  State<PhysicalBarcodeScannerListener> createState() =>
      _PhysicalBarcodeScannerListenerState();
}

class _PhysicalBarcodeScannerListenerState
    extends State<PhysicalBarcodeScannerListener> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      PhysicalBarcodeScanner.instance.addListener(_handleScan);
    }
  }

  @override
  void didUpdateWidget(covariant PhysicalBarcodeScannerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        PhysicalBarcodeScanner.instance.addListener(_handleScan);
      } else {
        PhysicalBarcodeScanner.instance.removeListener(_handleScan);
      }
    }
  }

  @override
  void dispose() {
    PhysicalBarcodeScanner.instance.removeListener(_handleScan);
    super.dispose();
  }

  void _handleScan(BarcodeScanResult result) {
    if (mounted && widget.enabled) {
      widget.onBarcodeScanned(result.barcode);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
