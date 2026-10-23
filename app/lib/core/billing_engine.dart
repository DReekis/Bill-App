import 'gst_service.dart';
import 'models.dart';
import 'money.dart';

class LineCalcInput {
  LineCalcInput({
    required this.quantity,
    required this.price,
    this.discountPercent = 0,
    this.discountFlat = 0,
    this.gstRate = 0,
    this.taxIncluded = false,
  });
  final double quantity;
  /// Unit price in paise.
  final int price;
  final double discountPercent;
  /// Flat per-line discount in paise.
  final int discountFlat;
  final int gstRate;
  final bool taxIncluded;
}

class LineCalcResult {
  LineCalcResult({
    required this.quantity,
    required this.price,
    required this.lineTotal,
    required this.discount,
    required this.taxable,
    required this.tax,
    required this.gstRate,
    required this.taxIncluded,
  });
  final double quantity;
  final int price;
  final Money lineTotal;
  final Money discount;
  final Money taxable;
  final Money tax;
  final int gstRate;
  final bool taxIncluded;
}

class InvoiceDiscountInput {
  const InvoiceDiscountInput.percent(this.value)
      : type = 'percent',
        assert(value >= 0);
  const InvoiceDiscountInput.flat(this.value)
      : type = 'flat',
        assert(value >= 0);
  const InvoiceDiscountInput.none()
      : type = '',
        value = 0.0;
  final String type;
  final double value;
}

class QuoteResult {
  QuoteResult({
    required this.lines,
    required this.subtotal,
    required this.itemDiscount,
    required this.invoiceDiscount,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
    required this.roundOff,
    required this.total,
    required this.intraState,
    this.charges = const [],
    Money? chargesSubtotal,
    Money? chargesTax,
    Money? tcsTotal,
  })  : chargesSubtotal = chargesSubtotal ?? Money.zero(),
        chargesTax = chargesTax ?? Money.zero(),
        tcsTotal = tcsTotal ?? Money.zero();

  final List<LineCalcResult> lines;
  final Money subtotal;
  final Money itemDiscount;
  final Money invoiceDiscount;
  final Money taxable;
  final Money cgst;
  final Money sgst;
  final Money igst;
  final Money cess;
  final Money roundOff;
  final Money total;
  final bool intraState;
  final List<InvoiceCharge> charges;
  final Money chargesSubtotal;
  final Money chargesTax;
  final Money tcsTotal;

  Money get taxTotal => cgst + sgst + igst + cess;
  Money get chargesTotal => chargesSubtotal + chargesTax + tcsTotal;
}

int _round(num value) => value.round();

Money _taxOn(Money taxable, int rate) => rate == 0
    ? Money.zero()
    : Money(_round(taxable.paise * rate / 100));

class BillingEngine {
  static Money lineTaxable(Money lineTotal, int gstRate, bool taxIncluded) {
    if (!taxIncluded || gstRate == 0) return lineTotal;
    return Money(_round(lineTotal.paise * 100 / (100 + gstRate)));
  }

  static LineCalcResult calculateLine(LineCalcInput input) {
    final quantity = input.quantity;
    final lineTotal = Money(_round(input.price * quantity));
    Money discount = Money.zero();
    if (input.discountPercent > 0) {
      discount = Money(_round(lineTotal.paise * input.discountPercent / 100));
    } else if (input.discountFlat > 0) {
      final discountPaise = input.discountFlat;
      discount = discountPaise >= lineTotal.paise
          ? lineTotal
          : Money(discountPaise);
    }
    final base = lineTotal - discount;
    final taxable = lineTaxable(base, input.gstRate, input.taxIncluded);
    final tax = _taxOn(taxable, input.gstRate);
    return LineCalcResult(
      quantity: quantity,
      price: input.price,
      lineTotal: lineTotal,
      discount: discount,
      taxable: taxable,
      tax: tax,
      gstRate: input.gstRate,
      taxIncluded: input.taxIncluded,
    );
  }

  static QuoteResult calculateQuote({
    required List<LineCalcInput> lines,
    required InvoiceDiscountInput invoiceDiscount,
    List<InvoiceCharge> charges = const [],
    bool gstEnabled = true,
    bool businessTaxRegistered = true,
    String? businessState,
    String? customerState,
    bool? intraStateOverride,
  }) {
    final computed =
        lines.map((line) => calculateLine(line)).toList(growable: false);

    Money subtotal = Money.zero();
    Money itemDiscount = Money.zero();
    Money taxable = Money.zero();
    for (final line in computed) {
      subtotal += line.lineTotal;
      itemDiscount += line.discount;
      taxable += line.taxable;
    }

    Money invoiceDiscountAmount = Money.zero();
    if (invoiceDiscount.type == 'percent' && invoiceDiscount.value > 0) {
      invoiceDiscountAmount = Money(
          _round(taxable.paise * invoiceDiscount.value / 100));
    } else if (invoiceDiscount.type == 'flat' && invoiceDiscount.value > 0) {
      invoiceDiscountAmount = Money(_round(invoiceDiscount.value * 100));
    }
    if (invoiceDiscountAmount.greaterThan(taxable)) {
      invoiceDiscountAmount = taxable;
    }
    final grossTaxable = taxable;
    taxable = taxable - invoiceDiscountAmount;

    final effectiveGstEnabled = gstEnabled ||
        lines.any((l) => l.gstRate > 0) ||
        charges.any((c) => c.gstRate > 0);
    final effectiveTaxRegistered = businessTaxRegistered ||
        lines.any((l) => l.gstRate > 0) ||
        charges.any((c) => c.gstRate > 0);

    final sameState = businessState != null &&
        customerState != null &&
        IndianStates.isSameState(businessState, customerState);
    final intraState = effectiveGstEnabled &&
        effectiveTaxRegistered &&
        (intraStateOverride ?? sameState);

    Money cgst = Money.zero();
    Money sgst = Money.zero();
    Money igst = Money.zero();
    if (effectiveGstEnabled && effectiveTaxRegistered) {
      final lineTax = computed.fold<int>(0, (sum, l) => sum + l.tax.paise);
      final gst = grossTaxable.isZero
          ? Money.zero()
          : Money(_round(lineTax * taxable.paise / grossTaxable.paise));
      if (intraState) {
        final half = _round(gst.paise / 2);
        cgst = Money(half);
        sgst = Money(gst.paise - half);
      } else {
        igst = gst;
      }
    }

    // Sequence: [Subtotal of Items] -> [Apply Item GST] -> [Apply Charges/TCS] -> [Grand Total]
    Money chargesSubtotal = Money.zero();
    Money chargesTax = Money.zero();
    Money tcsTotal = Money.zero();

    for (final charge in charges) {
      if (charge.isTcs) {
        tcsTotal += Money(charge.amount);
      } else {
        chargesSubtotal += Money(charge.amount);
        if (effectiveGstEnabled && effectiveTaxRegistered && charge.gstRate > 0) {
          final cTax = _round(charge.amount * charge.gstRate / 100);
          chargesTax += Money(cTax);
          if (intraState) {
            final half = _round(cTax / 2);
            cgst += Money(half);
            sgst += Money(cTax - half);
          } else {
            igst += Money(cTax);
          }
        }
      }
    }

    final net = taxable + cgst + sgst + igst + chargesSubtotal + tcsTotal;
    final roundedToRupee = Money(_round(net.paise / 100) * 100);
    final roundOff = roundedToRupee - net;
    final total = net + roundOff;

    return QuoteResult(
      lines: computed,
      subtotal: subtotal,
      itemDiscount: itemDiscount,
      invoiceDiscount: invoiceDiscountAmount,
      taxable: taxable,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      cess: Money.zero(),
      roundOff: roundOff,
      total: total,
      intraState: intraState,
      charges: charges,
      chargesSubtotal: chargesSubtotal,
      chargesTax: chargesTax,
      tcsTotal: tcsTotal,
    );
  }

  static String taxLabel(Invoice invoice) {
    if (invoice.igst > 0) return 'IGST';
    if (invoice.cgst > 0 || invoice.sgst > 0) return 'CGST + SGST';
    return '';
  }
}

String invoiceStatusFor(Money outstanding) {
  if (outstanding.paise <= 0) return 'Paid';
  return 'Unpaid';
}

String resolveInvoiceStatus({required int total, required int amountPaid}) {
  final outstanding = total - amountPaid;
  if (amountPaid <= 0) return 'Unpaid';
  if (outstanding <= 0) return 'Paid';
  return 'Partially paid';
}