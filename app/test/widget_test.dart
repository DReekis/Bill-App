import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billket/core/money.dart';
import 'package:billket/utils/widgets.dart';

void main() {
  testWidgets('MoneyText renders Indian-formatted amount', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MoneyText(123456))));
    expect(find.text('₹1,234.56'), findsOneWidget);
    final rendered = tester.widget<Text>(find.byType(Text));
    expect(rendered.style?.fontSize, 15);
    expect(rendered.style?.fontWeight, FontWeight.w700);
  });

  test('moneyStyle exposes size, weight and tabular figures', () {
    final style = moneyStyle(fontSize: 12, weight: FontWeight.w600);
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.fontFeatures, isNotNull);
  });
}