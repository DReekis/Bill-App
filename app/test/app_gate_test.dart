import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billket/core/session.dart';
import 'package:billket/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpGate(WidgetTester tester, Session session) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: const MaterialApp(home: AppGate()),
      ),
    );
  }

  testWidgets('fresh session shows onboarding from the gate', (tester) async {
    final session = Session();
    await session.load();
    await pumpGate(tester, session);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Stitch Bill'), findsOneWidget);
  });

  testWidgets('locked session with PIN shows the lock screen', (tester) async {
    final session = Session();
    await session.load();
    await session.setPin('1234');
    await session.lock();
    await pumpGate(tester, session);
    await tester.pumpAndSettle();
    expect(find.text('App locked'), findsOneWidget);
  });

  test('verifyPin validates the stored hash', () async {
    final session = Session();
    await session.load();
    await session.setPin('1234');
    expect(session.verifyPin('1234'), isTrue);
    expect(session.verifyPin('0000'), isFalse);
  });
}