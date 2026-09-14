import 'package:flutter_test/flutter_test.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/money.dart';

void main() {
  group('BillingEngine.calculateLine', () {
    test('plain line keeps full value', () {
      final r = BillingEngine.calculateLine(LineCalcInput(quantity: 2, price: 100000));
      expect(r.lineTotal.paise, 200000);
      expect(r.discount.paise, 0);
      expect(r.taxable.paise, 200000);
      expect(r.tax.paise, 0);
    });

    test('percent discount applies to line total', () {
      final r = BillingEngine.calculateLine(
          LineCalcInput(quantity: 2, price: 100000, discountPercent: 5, gstRate: 10));
      expect(r.lineTotal.paise, 200000);
      expect(r.discount.paise, 10000);
      expect(r.taxable.paise, 190000);
      expect(r.tax.paise, 19000);
    });

    test('flat discount caps at line total', () {
      final r = BillingEngine.calculateLine(
          LineCalcInput(quantity: 1, price: 50000, discountFlat: 100000));
      expect(r.discount.paise, 50000);
      expect(r.taxable.paise, 0);
    });
  });

  group('BillingEngine.calculateQuote', () {
    test('₹2000 at 10% GST totals ₹2200', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
      );
      expect(q.taxable.paise, 200000);
      expect(q.igst.paise, 20000);
      expect(q.cgst.paise, 0);
      expect(q.sgst.paise, 0);
      expect(q.roundOff.paise, 0);
      expect(q.total.paise, 220000);
    });

    test('₹1800 taxable at 18% GST totals ₹2124', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 180000, gstRate: 18)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
      );
      expect(q.taxable.paise, 180000);
      expect(q.igst.paise, 32400);
      expect(q.total.paise, 212400);
    });

    test('same state splits GST into CGST + SGST', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );
      expect(q.intraState, isTrue);
      expect(q.cgst.paise, 10000);
      expect(q.sgst.paise, 10000);
      expect(q.igst.paise, 0);
    });

    test('inter-state sale falls back to IGST', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Tamil Nadu',
      );
      expect(q.intraState, isFalse);
      expect(q.igst.paise, 20000);
    });

    test('tax-inclusive price back-calculates taxable base', () {
      final q = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 1, price: 118000, gstRate: 18, taxIncluded: true),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
      );
      expect(q.taxable.paise, 100000);
      expect(q.igst.paise, 18000);
      expect(q.total.paise, 118000);
    });

    test('percent invoice discount reduces taxable before tax', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.percent(10),
      );
      expect(q.invoiceDiscount.paise, 20000);
      expect(q.taxable.paise, 180000);
      expect(q.total.paise, 198000);
    });

    test('flat invoice discount caps at taxable', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 50000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.flat(1000),
      );
      expect(q.invoiceDiscount.paise, 50000);
      expect(q.taxable.paise, 0);
      expect(q.total.paise, 0);
    });

    test('intraStateOverride forces the split the user picked at checkout', () {
      final forcedInter = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
        intraStateOverride: false,
      );
      expect(forcedInter.intraState, isFalse);
      expect(forcedInter.igst.paise, 20000);
      expect(forcedInter.cgst.paise, 0);

      final forcedIntra = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 1, price: 200000, gstRate: 10)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Tamil Nadu',
        intraStateOverride: true,
      );
      expect(forcedIntra.cgst.paise, 10000);
      expect(forcedIntra.sgst.paise, 10000);
      expect(forcedIntra.igst.paise, 0);
    });

    test('rounds total to nearest rupee and reports roundOff', () {
      final q = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 3, price: 18300, gstRate: 18)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
      );
      expect(q.taxable.paise, 54900);
      expect(q.igst.paise, 9882);
      expect(q.total.paise, 64800);
      expect(q.roundOff.paise, 18);
    });
  });

  test('mixed GST rates keep exact per-line tax (no blended-rate drift)', () {
    final q = BillingEngine.calculateQuote(
      lines: [
        LineCalcInput(quantity: 3, price: 34000, gstRate: 18),
        LineCalcInput(quantity: 10, price: 9000, gstRate: 12),
      ],
      invoiceDiscount: const InvoiceDiscountInput.none(),
    );
    expect(q.taxable.paise, 192000);
    expect(q.igst.paise, 18360 + 10800);
    expect(q.total.paise, 221200);
  });

  group('status helpers', () {
    test('resolveInvoiceStatus covers unpaid/partial/paid', () {
      expect(resolveInvoiceStatus(total: 200000, amountPaid: 0), 'Unpaid');
      expect(resolveInvoiceStatus(total: 200000, amountPaid: 100000), 'Partially paid');
      expect(resolveInvoiceStatus(total: 200000, amountPaid: 200000), 'Paid');
    });

    test('invoiceStatusFor from outstanding balance', () {
      expect(invoiceStatusFor(Money.zero()), 'Paid');
      expect(invoiceStatusFor(const Money(5000)), 'Unpaid');
    });
  });
}