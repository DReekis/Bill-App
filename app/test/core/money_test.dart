import 'package:flutter_test/flutter_test.dart';

import 'package:billket/core/money.dart';

void main() {
  group('Money', () {
    test('arithmetic and helpers', () {
      expect(Money.fromRupees(12.5).paise, 1250);
      expect((const Money(100) + const Money(25)).paise, 125);
      expect((const Money(100) - const Money(25)).paise, 75);
      expect((-const Money(30)).paise, -30);
      expect(const Money(-30).abs().paise, 30);
      expect(const Money(30).greaterThan(const Money(29)), isTrue);
      expect(const Money(29).lesserThan(const Money(30)), isTrue);
      expect(Money.parse(1234).paise, 1234);
      expect(const Money(1234).rupees, 12.34);
    });
  });

  group('formatPaise', () {
    test('whole rupees drop the decimals', () {
      expect(formatPaise(0), '₹0');
      expect(formatPaise(100), '₹1');
      expect(formatPaise(-500), '-₹5');
    });

    test('Indian digit grouping', () {
      expect(formatPaise(123456), '₹1,234.56');
      expect(formatPaise(123456789), '₹12,34,567.89');
      expect(formatPaise(100000), '₹1,000');
    });

    test('fraction pads to two digits', () {
      expect(formatPaise(1205), '₹12.05');
    });
  });

  group('formatPaiseClean & formatPaisePdf', () {
    test('formatPaiseClean drops currency symbol and formats cleanly', () {
      expect(formatPaiseClean(0), '0');
      expect(formatPaiseClean(609900), '6,099');
      expect(formatPaiseClean(123456), '1,234.56');
      expect(formatPaiseClean(-50000), '-500');
    });

    test('formatPaisePdf uses ASCII-safe Rs. prefix without unicode glyphs', () {
      expect(formatPaisePdf(790000, prefixRs: true), 'Rs. 7,900');
      expect(formatPaisePdf(-50000, prefixRs: true), '-Rs. 500');
      expect(formatPaisePdf(1205, prefixRs: false), '12.05');
      // Must not contain the unicode rupee glyph \u20B9
      expect(formatPaisePdf(790000, prefixRs: true).contains('₹'), isFalse);
      expect(formatPaiseClean(790000).contains('₹'), isFalse);
    });
  });
}