import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/dates.dart';

void main() {
  group('DateFilterPreset calculations', () {
    // Fixed reference date: Tuesday, 29 September 2026
    final refNow = DateTime(2026, 9, 29, 14, 30);

    test('today preset', () {
      final range = calculateDateRange(DateFilterPreset.today, nowOverride: refNow);
      expect(range.startIso, '2026-09-29');
      expect(range.endIso, '2026-09-29');
      expect(range.formatted, '29 Sep 2026');
    });

    test('yesterday preset', () {
      final range = calculateDateRange(DateFilterPreset.yesterday, nowOverride: refNow);
      expect(range.startIso, '2026-09-28');
      expect(range.endIso, '2026-09-28');
      expect(range.formatted, '28 Sep 2026');
    });

    test('thisWeek preset (Monday to Sunday)', () {
      final range = calculateDateRange(DateFilterPreset.thisWeek, nowOverride: refNow);
      expect(range.startIso, '2026-09-28'); // Monday
      expect(range.endIso, '2026-10-04');   // Sunday
      expect(range.formatted, '28 Sep - 04 Oct 2026');
    });

    test('lastWeek preset', () {
      final range = calculateDateRange(DateFilterPreset.lastWeek, nowOverride: refNow);
      expect(range.startIso, '2026-09-21'); // Previous Monday
      expect(range.endIso, '2026-09-27');   // Previous Sunday
      expect(range.formatted, '21 - 27 Sep 2026');
    });

    test('last7Days preset', () {
      final range = calculateDateRange(DateFilterPreset.last7Days, nowOverride: refNow);
      expect(range.startIso, '2026-09-23');
      expect(range.endIso, '2026-09-29');
      expect(range.formatted, '23 - 29 Sep 2026');
    });

    test('thisMonth preset', () {
      final range = calculateDateRange(DateFilterPreset.thisMonth, nowOverride: refNow);
      expect(range.startIso, '2026-09-01');
      expect(range.endIso, '2026-09-30');
      expect(range.formatted, '01 - 30 Sep 2026');
    });

    test('lastMonth preset', () {
      final range = calculateDateRange(DateFilterPreset.lastMonth, nowOverride: refNow);
      expect(range.startIso, '2026-08-01');
      expect(range.endIso, '2026-08-31');
      expect(range.formatted, '01 - 31 Aug 2026');
    });

    test('thisQuarter preset in Q2 (September)', () {
      final range = calculateDateRange(DateFilterPreset.thisQuarter, nowOverride: refNow);
      expect(range.startIso, '2026-07-01');
      expect(range.endIso, '2026-09-30');
      expect(range.formatted, '01 Jul - 30 Sep 2026');
    });

    test('lastQuarter preset in Q2', () {
      final range = calculateDateRange(DateFilterPreset.lastQuarter, nowOverride: refNow);
      expect(range.startIso, '2026-04-01');
      expect(range.endIso, '2026-06-30');
      expect(range.formatted, '01 Apr - 30 Jun 2026');
    });

    test('quarter transitions across Q1, Q3, Q4', () {
      // Q1 (May)
      final may = DateTime(2026, 5, 10);
      final q1 = calculateDateRange(DateFilterPreset.thisQuarter, nowOverride: may);
      expect(q1.startIso, '2026-04-01');
      expect(q1.endIso, '2026-06-30');

      final prevQ1 = calculateDateRange(DateFilterPreset.lastQuarter, nowOverride: may);
      expect(prevQ1.startIso, '2026-01-01');
      expect(prevQ1.endIso, '2026-03-31');

      // Q3 (November)
      final nov = DateTime(2026, 11, 15);
      final q3 = calculateDateRange(DateFilterPreset.thisQuarter, nowOverride: nov);
      expect(q3.startIso, '2026-10-01');
      expect(q3.endIso, '2026-12-31');

      // Q4 (February)
      final feb = DateTime(2027, 2, 10);
      final q4 = calculateDateRange(DateFilterPreset.thisQuarter, nowOverride: feb);
      expect(q4.startIso, '2027-01-01');
      expect(q4.endIso, '2027-03-31');

      final prevQ4 = calculateDateRange(DateFilterPreset.lastQuarter, nowOverride: feb);
      expect(prevQ4.startIso, '2026-10-01');
      expect(prevQ4.endIso, '2026-12-31');
    });

    test('currentFinancialYear and previousFinancialYear (Indian FY)', () {
      // In Sep 2026
      final fy = calculateDateRange(DateFilterPreset.currentFinancialYear, nowOverride: refNow);
      expect(fy.startIso, '2026-04-01');
      expect(fy.endIso, '2027-03-31');
      expect(fy.formatted, '01 Apr 2026 - 31 Mar 2027');

      final prevFy = calculateDateRange(DateFilterPreset.previousFinancialYear, nowOverride: refNow);
      expect(prevFy.startIso, '2025-04-01');
      expect(prevFy.endIso, '2026-03-31');
      expect(prevFy.formatted, '01 Apr 2025 - 31 Mar 2026');

      // In Feb 2027 (still FY 2026-27)
      final feb = DateTime(2027, 2, 10);
      final fyFeb = calculateDateRange(DateFilterPreset.currentFinancialYear, nowOverride: feb);
      expect(fyFeb.startIso, '2026-04-01');
      expect(fyFeb.endIso, '2027-03-31');

      final prevFyFeb = calculateDateRange(DateFilterPreset.previousFinancialYear, nowOverride: feb);
      expect(prevFyFeb.startIso, '2025-04-01');
      expect(prevFyFeb.endIso, '2026-03-31');
    });

    test('custom preset', () {
      final custom = calculateDateRange(
        DateFilterPreset.custom,
        customStart: DateTime(2026, 9, 10),
        customEnd: DateTime(2026, 9, 20),
      );
      expect(custom.startIso, '2026-09-10');
      expect(custom.endIso, '2026-09-20');
      expect(custom.formatted, '10 - 20 Sep 2026');
    });
  });
}
