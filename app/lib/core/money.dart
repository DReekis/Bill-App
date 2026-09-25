import 'package:flutter/painting.dart' show Color, FontFeature, FontWeight, TextStyle;

class Money {
  final int paise;
  const Money(this.paise);

  static Money zero() => const Money(0);
  static Money fromRupees(num rupees) => Money((rupees * 100).round());
  static Money parse(Object? value) => Money((value as num).round());

  double get rupees => paise / 100;
  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  Money operator -() => Money(-paise);
  Money multiply(num factor) => Money((paise * factor).round());
  Money abs() => Money(paise.abs());

  int compareTo(Money other) => paise.compareTo(other.paise);
  bool greaterThan(Money other) => paise > other.paise;
  bool lesserThan(Money other) => paise < other.paise;

  int toJson() => paise;

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;
  @override
  int get hashCode => paise.hashCode;
  @override
  String toString() => formatMoney(this);
}

String formatMoney(Money money) => formatPaise(money.paise);

String formatMoneySigned(Money money) {
  if (money.isZero) return formatPaise(0);
  final prefix = money.isNegative ? '-' : '+';
  return '$prefix${formatPaise(money.abs().paise)}';
}

String formatPaise(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final wholeStr = _groupThousands(whole.toString());
  final body =
      fraction == 0 ? wholeStr : '$wholeStr.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}₹$body';
}

/// Formats paise into plain numeric text with Indian comma grouping (e.g. "6,099" or "6,099.50"),
/// WITHOUT any currency symbol.
/// Safe for use in PDF tables, charts, or where "(Rs)" is already in the column header.
String formatPaiseClean(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final wholeStr = _groupThousands(whole.toString());
  final body =
      fraction == 0 ? wholeStr : '$wholeStr.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$body';
}

/// Formats paise for PDF output with ASCII-safe "Rs." prefix (e.g. "Rs. 7,900" or "-Rs. 500").
/// Never emits the Unicode ₹ glyph which causes missing character tofu boxes (☒) in PDF viewers.
String formatPaisePdf(int paise, {bool prefixRs = false}) {
  final clean = formatPaiseClean(paise);
  if (prefixRs) {
    if (clean.startsWith('-')) {
      return '-Rs. ${clean.substring(1)}';
    }
    return 'Rs. $clean';
  }
  return clean;
}

String _groupThousands(String digits) {
  if (digits.length <= 3) return digits;
  final last = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last';
}

TextStyle moneyStyle({double fontSize = 15, FontWeight weight = FontWeight.w700, Color color = const Color(0xFF0F1C3E)}) =>
    TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: -0.2,
    );