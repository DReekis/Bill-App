import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billket/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations & Short Name Tests', () {
    test('English short quick action names are punchy and easily identifiable', () {
      final l10nEn = AppLocalizations(const Locale('en'));
      expect(l10nEn.text('sale'), 'Sale');
      expect(l10nEn.text('purchase'), 'Purchase');
      expect(l10nEn.text('gst'), 'GST');
      expect(l10nEn.text('cash_bank'), 'Cash/Bank');
      expect(l10nEn.text('item'), 'Item');
      expect(l10nEn.text('estimate'), 'Estimate');
      expect(l10nEn.text('order'), 'Order');
      expect(l10nEn.text('reports'), 'Reports');
    });

    test('Hindi quick actions are clean, short, and under 12 characters', () {
      final l10nHi = AppLocalizations(const Locale('hi'));
      final shortActions = [
        l10nHi.text('sale'),
        l10nHi.text('purchase'),
        l10nHi.text('gst'),
        l10nHi.text('cash_bank'),
        l10nHi.text('item'),
        l10nHi.text('estimate'),
        l10nHi.text('order'),
        l10nHi.text('reports'),
      ];

      expect(l10nHi.text('sale'), 'बिक्री');
      expect(l10nHi.text('purchase'), 'खरीद');
      expect(l10nHi.text('gst'), 'जीएसटी');
      expect(l10nHi.text('cash_bank'), 'कैश-बैंक');
      expect(l10nHi.text('item'), 'सामान');
      expect(l10nHi.text('estimate'), 'कोटेशन');
      expect(l10nHi.text('order'), 'ऑर्डर');
      expect(l10nHi.text('reports'), 'रिपोर्ट्स');

      for (final action in shortActions) {
        expect(action.length, lessThanOrEqualTo(12),
            reason: '$action should be short so it never overflows');
      }
    });

    test('Delegate reloads properly when locale changes', () {
      const delegate = AppLocalizations.delegate;
      expect(delegate.shouldReload(delegate), isTrue);
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('hi')), isTrue);
      expect(delegate.isSupported(const Locale('fr')), isFalse);
    });
  });
}
