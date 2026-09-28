class InvoiceNumbering {
  static String format(String prefix, int sequence) =>
      '${prefix.trim().isEmpty ? 'INV' : prefix.trim().toUpperCase()}-${sequence.toString().padLeft(4, '0')}';

  static int? extractSequence(String number) {
    final clean = number.trim();
    final match = RegExp(r'(\d+)$').firstMatch(clean);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}

String todayIso() {
  final now = DateTime.now();
  return _iso(now);
}

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _iso(DateTime d) => isoDate(d);

DateTime? parseIso(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

DateTime dateTimeFor(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed != null) return parsed;
  final now = DateTime.now();
  if (iso.length >= 10) {
    final parts = iso.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]) ?? now.year;
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2].split(' ').first);
      if (m != null && d != null) return DateTime(y, m, d);
    }
  }
  return DateTime(now.year, now.month, now.day);
}

String displayDate(String? iso) {
  final parsed = parseIso(iso);
  if (parsed == null) return iso ?? '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

String humanTime(String? iso) {
  final parsed = parseIso(iso);
  if (parsed == null) return iso ?? '';
  final h = parsed.hour.toString().padLeft(2, '0');
  final m = parsed.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String timestampNow() {
  final now = DateTime.now();
  final date = isoDate(now);
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  final s = now.second.toString().padLeft(2, '0');
  return '$date $h:$m:$s';
}

enum DateFilterPreset {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  lastWeek('Last week'),
  last7Days('Last 7 days'),
  thisMonth('This month'),
  lastMonth('Last Month'),
  thisQuarter('This Quarter'),
  lastQuarter('Last Quarter'),
  currentFinancialYear('Current Financial year'),
  previousFinancialYear('Previous Financial Year'),
  custom('Custom');

  final String label;
  const DateFilterPreset(this.label);
}

class DateFilterRange {
  final DateTime? start;
  final DateTime? end;

  const DateFilterRange({this.start, this.end});

  String? get startIso => start != null ? isoDate(start!) : null;
  String? get endIso => end != null ? isoDate(end!) : null;

  String get formatted {
    if (start == null && end == null) return 'All dates';
    if (start != null && end == null) return 'From ${displayDate(startIso)}';
    if (start == null && end != null) return 'Until ${displayDate(endIso)}';
    return formatRangeDisplay(start!, end!);
  }
}

String formatRangeDisplay(DateTime start, DateTime end) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final sDay = start.day.toString().padLeft(2, '0');
  final eDay = end.day.toString().padLeft(2, '0');
  final sMonth = months[start.month - 1];
  final eMonth = months[end.month - 1];

  if (start.year == end.year && start.month == end.month && start.day == end.day) {
    return '$sDay $sMonth ${start.year}';
  }
  if (start.year == end.year && start.month == end.month) {
    return '$sDay - $eDay $sMonth ${start.year}';
  }
  if (start.year == end.year) {
    return '$sDay $sMonth - $eDay $eMonth ${start.year}';
  }
  return '$sDay $sMonth ${start.year} - $eDay $eMonth ${end.year}';
}

DateFilterRange calculateDateRange(
  DateFilterPreset preset, {
  DateTime? customStart,
  DateTime? customEnd,
  DateTime? nowOverride,
}) {
  final now = nowOverride ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (preset) {
    case DateFilterPreset.today:
      return DateFilterRange(start: today, end: today);

    case DateFilterPreset.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return DateFilterRange(start: yesterday, end: yesterday);

    case DateFilterPreset.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return DateFilterRange(start: start, end: end);

    case DateFilterPreset.lastWeek:
      final start = today.subtract(Duration(days: today.weekday - 1 + 7));
      final end = start.add(const Duration(days: 6));
      return DateFilterRange(start: start, end: end);

    case DateFilterPreset.last7Days:
      final start = today.subtract(const Duration(days: 6));
      return DateFilterRange(start: start, end: today);

    case DateFilterPreset.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      final end = DateTime(today.year, today.month + 1, 0);
      return DateFilterRange(start: start, end: end);

    case DateFilterPreset.lastMonth:
      final start = DateTime(today.year, today.month - 1, 1);
      final end = DateTime(today.year, today.month, 0);
      return DateFilterRange(start: start, end: end);

    case DateFilterPreset.thisQuarter:
      if (today.month >= 4 && today.month <= 6) {
        return DateFilterRange(start: DateTime(today.year, 4, 1), end: DateTime(today.year, 6, 30));
      } else if (today.month >= 7 && today.month <= 9) {
        return DateFilterRange(start: DateTime(today.year, 7, 1), end: DateTime(today.year, 9, 30));
      } else if (today.month >= 10 && today.month <= 12) {
        return DateFilterRange(start: DateTime(today.year, 10, 1), end: DateTime(today.year, 12, 31));
      } else {
        return DateFilterRange(start: DateTime(today.year, 1, 1), end: DateTime(today.year, 3, 31));
      }

    case DateFilterPreset.lastQuarter:
      if (today.month >= 4 && today.month <= 6) {
        return DateFilterRange(start: DateTime(today.year, 1, 1), end: DateTime(today.year, 3, 31));
      } else if (today.month >= 7 && today.month <= 9) {
        return DateFilterRange(start: DateTime(today.year, 4, 1), end: DateTime(today.year, 6, 30));
      } else if (today.month >= 10 && today.month <= 12) {
        return DateFilterRange(start: DateTime(today.year, 7, 1), end: DateTime(today.year, 9, 30));
      } else {
        return DateFilterRange(start: DateTime(today.year - 1, 10, 1), end: DateTime(today.year - 1, 12, 31));
      }

    case DateFilterPreset.currentFinancialYear:
      if (today.month >= 4) {
        return DateFilterRange(start: DateTime(today.year, 4, 1), end: DateTime(today.year + 1, 3, 31));
      } else {
        return DateFilterRange(start: DateTime(today.year - 1, 4, 1), end: DateTime(today.year, 3, 31));
      }

    case DateFilterPreset.previousFinancialYear:
      if (today.month >= 4) {
        return DateFilterRange(start: DateTime(today.year - 1, 4, 1), end: DateTime(today.year, 3, 31));
      } else {
        return DateFilterRange(start: DateTime(today.year - 2, 4, 1), end: DateTime(today.year - 1, 3, 31));
      }

    case DateFilterPreset.custom:
      final start = customStart ?? DateTime(today.year, today.month, 1);
      final end = customEnd ?? today;
      return DateFilterRange(start: start, end: end);
  }
}