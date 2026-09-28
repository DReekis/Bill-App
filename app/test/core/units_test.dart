import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/units.dart';

void main() {
  group('AppUnit Catalog & Helpers', () {
    test('standard catalog contains all required categories and units', () {
      expect(kStandardUnits.length, greaterThanOrEqualTo(45));
      expect(kUnitCategories, containsAll([
        'All',
        'Count',
        'Packages',
        'Weight',
        'Volume',
        'Length',
        'Area',
        'Services',
        'Others',
      ]));
    });

    test('matchAppUnit correctly maps exact codes and common aliases', () {
      expect(matchAppUnit('PCS')?.code, 'PCS');
      expect(matchAppUnit('pcs')?.code, 'PCS');
      expect(matchAppUnit('pc')?.code, 'PCS');
      expect(matchAppUnit('pieces')?.code, 'PCS');

      expect(matchAppUnit('kg')?.code, 'KGS');
      expect(matchAppUnit('kgs')?.code, 'KGS');
      expect(matchAppUnit('g')?.code, 'GMS');
      expect(matchAppUnit('gms')?.code, 'GMS');

      expect(matchAppUnit('l')?.code, 'LTR');
      expect(matchAppUnit('litre')?.code, 'LTR');
      expect(matchAppUnit('box')?.code, 'BOX');
      expect(matchAppUnit('boxes')?.code, 'BOX');
      expect(matchAppUnit('packet')?.code, 'PKT');
    });

    test('formatUnitDisplay formats correctly', () {
      expect(formatUnitDisplay('PCS'), 'PCS (Pieces)');
      expect(formatUnitDisplay('kg'), 'KGS (Kilograms)');
      expect(formatUnitDisplay('CUSTOM_UNIT'), 'CUSTOM_UNIT');
    });
  });
}
