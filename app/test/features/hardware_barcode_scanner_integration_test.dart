import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:billket/core/session.dart';
import 'package:billket/core/physical_barcode_scanner.dart';
import 'package:billket/features/sales/hardware_scanner_dialog.dart';

void main() {
  setUp(() {
    PhysicalBarcodeScanner.instance.stop();
  });

  tearDown(() {
    PhysicalBarcodeScanner.instance.stop();
  });

  Widget buildTestApp(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Session()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  testWidgets('HardwareScannerDialog renders readiness state and guide tiles', (tester) async {
    await tester.pumpWidget(buildTestApp(const HardwareScannerDialog()));

    expect(find.text('Physical Barcode Scanner'), findsOneWidget);
    expect(find.text('Active & Ready (Wired USB / Bluetooth HID)'), findsOneWidget);
    expect(find.text('LIVE TEST STATUS'), findsOneWidget);
    expect(find.textContaining('Wired USB Scanners'), findsOneWidget);
    expect(find.textContaining('Bluetooth Wireless Scanners'), findsOneWidget);

    // Simulate scanning a barcode while the dialog is open
    PhysicalBarcodeScanner.instance.dispatchManual('8901234567890');
    await tester.pumpAndSettle();

    expect(find.text('8901234567890'), findsOneWidget);
    expect(find.textContaining('13 chars'), findsOneWidget);
  });

  testWidgets('PhysicalBarcodeScannerListener receives keystrokes and invokes callback', (tester) async {
    String? captured;
    await tester.pumpWidget(
      buildTestApp(
        PhysicalBarcodeScannerListener(
          onBarcodeScanned: (code) => captured = code,
          child: const Text('Counter POS Mode'),
        ),
      ),
    );

    expect(find.text('Counter POS Mode'), findsOneWidget);

    // Send rapid keystrokes + Enter
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7, character: '7');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(captured, '987');
  });
}
