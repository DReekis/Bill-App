import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billket/utils/widgets.dart';
import 'package:billket/features/customers/parties_tab.dart';
import 'package:billket/l10n/app_localizations.dart';
import 'package:billket/core/session.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 1: Toast Notification Duration & Dismissibility', () {
    testWidgets('showAppMessage appears and auto-dismisses in 1000ms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAppMessage(context, 'Test Toast Notification'),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      // Initially no toast
      expect(find.text('Test Toast Notification'), findsNothing);

      // Tap button to trigger toast
      await tester.tap(find.text('Show'));
      await tester.pump();

      // Toast is visible
      expect(find.text('Test Toast Notification'), findsOneWidget);

      // Advance by 500ms - toast still visible
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Test Toast Notification'), findsOneWidget);

      // Advance beyond 1000ms - toast dismissed
      await tester.pump(const Duration(milliseconds: 550));
      expect(find.text('Test Toast Notification'), findsNothing);
    });

    testWidgets('showAppMessage can be dismissed immediately on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAppMessage(context, 'Dismissible Toast'),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text('Dismissible Toast'), findsOneWidget);

      // Tap the toast directly to dismiss immediately
      await tester.tap(find.text('Dismissible Toast'));
      await tester.pump();

      // Toast immediately gone
      expect(find.text('Dismissible Toast'), findsNothing);
    });
  });

  group('Issue 3: Parties Tab Customers Label Visibility', () {
    testWidgets('PartiesTab displays Customers and Suppliers in single line with FittedBox', (tester) async {
      // Small screen size (e.g. narrow mobile screen 320x640)
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final session = Session();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: session),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PartiesTab(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Check SegmentedButton exists
      final segmentedButton = find.byType(SegmentedButton<int>);
      expect(segmentedButton, findsOneWidget);

      // Check Customers text is rendered
      final customersTextFinder = find.text('Customers');
      expect(customersTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(customersTextFinder);
      expect(textWidget.maxLines, 1);
      expect(textWidget.softWrap, false);

      // Check FittedBox wraps the Customers text
      final fittedBoxFinder = find.ancestor(
        of: customersTextFinder,
        matching: find.byType(FittedBox),
      );
      expect(fittedBoxFinder, findsOneWidget);

      // Check Suppliers text is also rendered on a single line
      final suppliersTextFinder = find.text('Suppliers');
      expect(suppliersTextFinder, findsOneWidget);
      final supText = tester.widget<Text>(suppliersTextFinder);
      expect(supText.maxLines, 1);
      expect(supText.softWrap, false);
    });
  });

  group('Issue 2: Image Processing & Cropping Logic', () {
    test('Image decoding, EXIF orientation, 90 deg rotation, and crop functions', () async {
      // Create a test image 300x200 with white background and black line
      final testImg = img.Image(width: 300, height: 200);
      img.fill(testImg, color: img.ColorRgb8(255, 255, 255));
      img.drawLine(testImg, x1: 50, y1: 50, x2: 250, y2: 150, color: img.ColorRgb8(0, 0, 0));

      final encodedPng = img.encodePng(testImg);
      expect(encodedPng.isNotEmpty, isTrue);

      // Test decoding
      final decoded = img.decodeImage(encodedPng);
      expect(decoded, isNotNull);
      expect(decoded!.width, 300);
      expect(decoded.height, 200);

      // Test bakeOrientation
      final oriented = img.bakeOrientation(decoded);
      expect(oriented.width, 300);
      expect(oriented.height, 200);

      // Test rotation 90 degrees
      final rotated = img.copyRotate(oriented, angle: 90);
      expect(rotated.width, 200);
      expect(rotated.height, 300);

      // Test cropping a 3:1 signature area (150x50)
      final cropped = img.copyCrop(oriented, x: 20, y: 20, width: 150, height: 50);
      expect(cropped.width, 150);
      expect(cropped.height, 50);

      // Test contrast adjustment
      final contrasted = img.contrast(cropped, contrast: 135);
      expect(contrasted.width, 150);
      expect(contrasted.height, 50);

      // Test writing to file
      final tempDir = Directory.systemTemp.createTempSync('sig_test');
      final targetFile = File('${tempDir.path}/test_sig.png');
      await targetFile.writeAsBytes(img.encodePng(contrasted));

      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), greaterThan(0));

      tempDir.deleteSync(recursive: true);
    });
  });
}
