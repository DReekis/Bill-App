import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/physical_barcode_scanner.dart';

void main() {
  setUp(() {
    PhysicalBarcodeScanner.instance.stop();
  });

  tearDown(() {
    PhysicalBarcodeScanner.instance.stop();
  });

  testWidgets('PhysicalBarcodeScanner buffers keystrokes and dispatches on Enter', (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: const Text('Testing scanner'),
          ),
        ),
      ),
    );

    // Simulate rapid barcode scanner typing: '8', '9', '0', '1', '2', '3' + Enter
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(scanned, '890123');
    expect(PhysicalBarcodeScanner.instance.lastScan.value?.barcode, '890123');
    expect(PhysicalBarcodeScanner.instance.lastScan.value?.charCount, 6);
  });

  testWidgets('PhysicalBarcodeScanner supports Numpad digits and Numpad Enter', (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: const Text('Numpad test'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3, character: '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);

    expect(scanned, '123');
  });

  testWidgets('PhysicalBarcodeScanner supports Tab as terminator key', (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: const Text('Tab test'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'C');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    expect(scanned, 'ABC');
  });

  testWidgets('PhysicalBarcodeScanner ignores short input (< 2 chars)', (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: const Text('Short test'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(scanned, isNull);
  });

  testWidgets('PhysicalBarcodeScannerListener can be disabled', (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            enabled: false,
            onBarcodeScanned: (code) => scanned = code,
            child: const Text('Disabled test'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(scanned, isNull);
  });

  test('dispatchManual dispatches barcode result', () {
    BarcodeScanResult? result;
    void listener(BarcodeScanResult r) => result = r;

    PhysicalBarcodeScanner.instance.addListener(listener);
    PhysicalBarcodeScanner.instance.dispatchManual('CUSTOM-999', source: 'manual_test');

    expect(result, isNotNull);
    expect(result!.barcode, 'CUSTOM-999');
    expect(result!.source, 'manual_test');

    PhysicalBarcodeScanner.instance.removeListener(listener);
  });

  testWidgets('PhysicalBarcodeScanner ignores slow typing when text field is focused', (tester) async {
    String? scanned;
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(PhysicalBarcodeScanner.isEditableFocused(), isTrue);

    // Simulate slow human typing: advance clock by 150ms between keystrokes
    var fakeTime = DateTime(2026, 1, 1, 12, 0, 0);
    PhysicalBarcodeScanner.instance.nowProvider = () => fakeTime;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    fakeTime = fakeTime.add(const Duration(milliseconds: 150));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    fakeTime = fakeTime.add(const Duration(milliseconds: 150));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    // Slow human typing in text field should NOT trigger barcode scanned callback
    expect(scanned, isNull);

    // Reset nowProvider
    PhysicalBarcodeScanner.instance.nowProvider = DateTime.now;
  });

  testWidgets('PhysicalBarcodeScanner captures fast scanner burst even when text field is focused', (tester) async {
    String? scanned;
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeScannerListener(
            onBarcodeScanned: (code) => scanned = code,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(PhysicalBarcodeScanner.isEditableFocused(), isTrue);

    // Fast burst without delays (< 60ms average)
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(scanned, '8901');
  });
}
