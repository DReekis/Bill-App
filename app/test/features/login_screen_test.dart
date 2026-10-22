import 'package:billket/core/session.dart';
import 'package:billket/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('LoginScreen has faded placeholder and displays error as popup dialog', (tester) async {
    final session = Session();
    await session.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify phone placeholder is present and has faded styling
    final phoneFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '9876543210',
    );
    expect(phoneFinder, findsOneWidget);

    final phoneField = tester.widget<TextField>(phoneFinder);
    expect(phoneField.decoration?.hintStyle?.color, isNotNull);
    // Ensure the hint color has opacity/faded tone
    expect(
      phoneField.decoration!.hintStyle!.color!.a < 1.0 ||
          phoneField.decoration!.hintStyle!.color == const Color(0xFF94A3B8),
      isTrue,
    );

    // 2. Trigger validation error without entering 10-digit number
    final getOtpButton = find.widgetWithText(FilledButton, 'Get OTP');
    expect(getOtpButton, findsOneWidget);
    await tester.ensureVisible(getOtpButton);
    await tester.pumpAndSettle();
    await tester.tap(getOtpButton);
    await tester.pumpAndSettle();

    // 3. Verify a clean popup dialog appears rather than an inline error banner
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Invalid Mobile Number'), findsOneWidget);
    expect(find.text('Please enter a valid 10-digit mobile number.'), findsOneWidget);

    // 4. Tap Okay to dismiss the popup dialog
    final okayButton = find.widgetWithText(FilledButton, 'Okay');
    expect(okayButton, findsOneWidget);
    await tester.tap(okayButton);
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.byType(Dialog), findsNothing);
  });
}
