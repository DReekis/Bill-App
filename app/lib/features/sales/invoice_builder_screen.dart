import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/billing_engine.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../inventory/product_form.dart';

class InvoiceBuilderScreen extends StatefulWidget {
  const InvoiceBuilderScreen({super.key, this.customerId});
  final int? customerId;
  @override
  State<InvoiceBuilderScreen> createState() => _InvoiceBuilderScreenState();
}

class _LineEdit {
  _LineEdit({required this.product, required this.qty, required this.price, required this.discountPercent, required this.gstRate, required this.taxIncluded, this.batch, this.serial});
  final Product product;
  double qty;
  int price;
  double discountPercent;
  int gstRate;
  bool taxIncluded;
  String? batch;
  String? serial;
}

class _InvoiceBuilderScreenState extends State<InvoiceBuilderScreen> {
  List<_LineEdit> lines = [];
  Business? business;
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  String? customerState;
  String invoiceDiscountType = 'percent';
  double invoiceDiscountValue = 0;
  bool saving = false;

  QuoteResult? get quote => _quoteFor();

  QuoteResult? _quoteFor({bool? intraStateOverride}) =>
      lines.isEmpty ? null : BillingEngine.calculateQuote(
            lines: lines.map((l) => LineCalcInput(
              quantity: l.qty,
              price: l.price,
              discountPercent: l.discountPercent,
              gstRate: l.gstRate,
              taxIncluded: l.taxIncluded,
            )).toList(),
            invoiceDiscount: invoiceDiscountType == 'percent'
                ? InvoiceDiscountInput.percent(invoiceDiscountValue)
                : invoiceDiscountType == 'flat'
                    ? InvoiceDiscountInput.flat(invoiceDiscountValue)
                    : const InvoiceDiscountInput.none(),
            gstEnabled: business?.taxRegistered ?? false,
            businessTaxRegistered: business?.taxRegistered ?? false,
            businessState: _clean(business?.state),
            customerState: _clean(customerState),
            intraStateOverride: intraStateOverride,
          );

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final biz = await repo.getBusiness(businessId);
    final custs = await repo.customers(businessId);
    final prods = await repo.products(businessId);
    if (!mounted) return;
    setState(() {
      business = biz;
      customers = custs;
      products = prods;
    });
    if (widget.customerId != null) {
      for (final c in custs) {
        if (c.id == widget.customerId) {
          _selectCustomer(c);
          break;
        }
      }
    }
  }

  Future<void> _refreshProducts() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final prods = await Repository.instance.products(businessId);
    if (mounted) setState(() => products = prods);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  void _selectCustomer(Customer c) {
    setState(() {
      customerId = c.id;
      customerName = c.name;
      customerState = _clean(c.state);
    });
  }

  void _pickCustomer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final all = customers ?? const <Customer>[];
        final businessId = context.read<Session>().businessId!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select customer', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Walk-in customer', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() {
                  customerId = null;
                  customerName = null;
                  customerState = null;
                });
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ...all.map((c) => ListTile(
                  leading: InitialsAvatar(c.name, size: 36),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.phone ?? ''),
                  onTap: () {
                    _selectCustomer(c);
                    Navigator.pop(context);
                  },
                )),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => CustomerFormSheet(
                    businessId: businessId,
                    onSaved: _load,
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add new customer'),
            ),
          ]),
        );
      },
    );
  }

  void _addItem() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductPickerList(
        products: products ?? const [],
        onPick: (product) {
          Navigator.pop(context);
          _editLine(_LineEdit(product: product, qty: 1, price: product.salePrice, discountPercent: 0, gstRate: product.gstRate, taxIncluded: product.taxIncluded));
        },
        onAddNew: () async {
          Navigator.pop(context);
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _refreshProducts,
              onSavedProduct: (p) => _editLine(_LineEdit(product: p, qty: 1, price: p.salePrice, discountPercent: 0, gstRate: p.gstRate, taxIncluded: p.taxIncluded)),
              businessId: context.read<Session>().businessId!,
            ),
          );
        },
      ),
    );
  }

  void _editLine(_LineEdit line) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LineEditorSheet(line: line, onSave: (updated) {
        setState(() {
          final i = lines.indexOf(line);
          if (i >= 0) {
            lines[i] = updated;
          } else {
            lines.add(updated);
          }
        });
      }),
    );
  }

  void _removeLine(_LineEdit line) {
    setState(() => lines.remove(line));
  }

  Future<void> _checkout() async {
    final q = quote;
    final biz = business;
    if (q == null || biz == null) return;
    String invoiceDate = todayIso();
    String gstType = q.intraState ? 'intra' : 'inter';
    String? mode = 'Cash';
    final paidController = TextEditingController();
    final notesController = TextEditingController();
    final commit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Save invoice — ${q.total}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                AppAmountField(
                  controller: paidController,
                  label: 'Amount paid now',
                  suffix: '0 for credit',
                ),
                if (biz.taxRegistered) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'intra', label: Text('Intra-state')),
                      ButtonSegment(value: 'inter', label: Text('Inter-state')),
                    ],
                    selected: {gstType},
                    onSelectionChanged: (s) => setSheetState(() => gstType = s.first),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: inputDecoration('Payment mode'),
                  items: paymentModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setSheetState(() => mode = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final dt = dateTimeFor(invoiceDate);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dt,
                      firstDate: DateTime(dt.year - 2),
                      lastDate: DateTime(dt.year + 2),
                    );
                    if (picked != null) setSheetState(() => invoiceDate = isoDate(picked));
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(invoiceDate),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(controller: notesController, label: 'Notes (optional)'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: AsyncButton(
                    label: 'Save & finalize',
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (commit != true) return;
    final finalQuote = _quoteFor(intraStateOverride: gstType == 'intra') ?? q;
    await _save(finalQuote, biz, date: invoiceDate, gstType: gstType, mode: mode, paidController: paidController, notesController: notesController);
  }

  Future<void> _save(
    QuoteResult q,
    Business biz, {
    required String date,
    required String gstType,
    String? mode,
    required TextEditingController paidController,
    required TextEditingController notesController,
  }) async {
    final session = context.read<Session>();
    final businessId = session.businessId!;
    setState(() => saving = true);
    try {
      final number = await Repository.instance.nextInvoiceNumber(businessId, biz.invoicePrefix);
      final invoiceLines = <InvoiceLine>[];
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final calc = q.lines[i];
        invoiceLines.add(InvoiceLine(
          productId: l.product.id,
          name: l.product.name,
          hsn: l.product.hsn,
          gstRate: l.gstRate,
          quantity: l.qty,
          price: l.price,
          discount: calc.discount.paise,
          discountPercent: l.discountPercent,
          taxable: calc.taxable.paise,
          tax: calc.tax.paise,
          batchNumber: l.batch,
          serialNumber: l.serial,
        ));
      }
      final amountPaid = _toPaise(paidController.text);
      await Repository.instance.finalizeSale(
        businessId: businessId,
        number: number,
        customerId: customerId,
        customerName: customerName ?? 'Walk-in',
        date: date,
        gstType: gstType,
        quote: q,
        lines: invoiceLines,
        paymentMode: amountPaid > 0 ? (mode ?? 'Cash') : null,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        amountPaid: amountPaid,
      );
      if (mounted) {
        showAppMessage(context, '$number saved');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save invoice: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          IconButton(tooltip: 'Items', onPressed: _addItem, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        AppCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            onTap: _pickCustomer,
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              if (customerName != null)
                InitialsAvatar(customerName!, size: 38)
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: StitchColors.surfaceVariant, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.person_outline_rounded, color: StitchColors.primary, size: 20),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customerName ?? 'Walk-in customer',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: customerName == null ? StitchColors.textSecondary : StitchColors.textPrimary)),
                  Text(customerName == null ? 'Tap to choose a customer' : 'Tap to change',
                      style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: StitchColors.textTertiary),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add item')),
        ]),
        if (lines.isEmpty)
          const AppEmptyState(icon: Icons.shopping_cart_outlined, title: 'No items yet', subtitle: 'Tap add item to bill a product')
        else
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LineTile(line: l, onTap: () => _editLine(l), onRemove: () => _removeLine(l)),
              )),
        if (q != null) ...[
          const SizedBox(height: 8),
          AppCard(
            child: Column(children: [
              _summaryRow('Subtotal', formatPaise(q.subtotal.paise)),
              if (q.itemDiscount.paise > 0)
                _summaryRow('Item discounts', '-${formatPaise(q.itemDiscount.paise)}', color: StitchColors.success),
              _invoiceDiscountRow(q),
              _summaryRow('Taxable', formatPaise(q.taxable.paise)),
              if (q.cgst.paise > 0 || q.sgst.paise > 0) ...[
                _summaryRow('CGST', formatPaise(q.cgst.paise)),
                _summaryRow('SGST', formatPaise(q.sgst.paise)),
              ],
              if (q.igst.paise > 0) _summaryRow('IGST', formatPaise(q.igst.paise)),
              if (q.roundOff.paise != 0)
                _summaryRow('Round off', '${q.roundOff.paise > 0 ? '+' : '-'}${formatPaise(q.roundOff.paise.abs())}'),
              const Divider(height: 16),
              _summaryRow('Grand total', formatPaise(q.total.paise), bold: true),
              if (customerState == null && (business?.taxRegistered ?? false))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No customer state selected — applying interstate GST.',
                      style: TextStyle(fontSize: 11, color: StitchColors.warning)),
                ),
            ]),
          ),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(formatPaise(q?.total.paise ?? 0), style: moneyStyle(fontSize: 18, weight: FontWeight.w800, color: StitchColors.textPrimary)),
                Text('${lines.length} item(s)', style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
              ]),
            ),
            Expanded(
              child: AsyncButton(
                loading: saving,
                icon: Icons.receipt_long_rounded,
                label: q == null ? 'Add items to continue' : 'Save & checkout',
                onPressed: q == null ? () {} : _checkout,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _invoiceDiscountRow(QuoteResult q) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Invoice discount', style: TextStyle(fontSize: 12.5)),
          if (invoiceDiscountValue <= 0.0)
            TextButton(onPressed: () => _setDiscount(), child: const Text('Add'))
          else
            Row(children: [
              Text('-${formatPaise(q.invoiceDiscount.paise)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: StitchColors.success)),
              IconButton(
                onPressed: () => _setDiscount(),
                icon: const Icon(Icons.edit_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ]),
        ],
      );

  Future<void> _setDiscount() async {
    final valueController = TextEditingController(text: invoiceDiscountValue > 0 ? _trimNum(invoiceDiscountValue) : '');
    String discountType = invoiceDiscountType;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Invoice discount', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'percent', label: Text('%')),
                    ButtonSegment(value: 'flat', label: Text('₹')),
                  ],
                  selected: {discountType},
                  onSelectionChanged: (s) => setSheetState(() => discountType = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: discountType == 'flat' ? 'Discount amount (₹)' : 'Discount percent (%)',
                    prefixText: discountType == 'flat' ? '₹ ' : '',
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final value = double.tryParse(valueController.text.trim()) ?? 0;
                        setState(() {
                          invoiceDiscountType = discountType;
                          invoiceDiscountValue = value;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color color = StitchColors.textPrimary, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            Text(value, style: TextStyle(fontSize: bold ? 15 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ],
        ),
      );
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap, required this.onRemove});
  final _LineEdit line;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final calc = BillingEngine.calculateLine(LineCalcInput(
      quantity: line.qty,
      price: line.price,
      discountPercent: line.discountPercent,
      gstRate: line.gstRate,
    ));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('${_qty(line.qty)} × ${formatPaise(line.price)}  ${line.discountPercent > 0 ? '· ${_qty(line.discountPercent)}% off  ' : ''}${line.gstRate > 0 ? '· GST ${line.gstRate}%' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatPaise(calc.taxable.paise + calc.tax.paise), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 17), visualDensity: VisualDensity.compact, color: StitchColors.textTertiary),
          ]),
        ]),
      ),
    );
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}

class _ProductPickerList extends StatelessWidget {
  const _ProductPickerList({required this.products, required this.onPick, required this.onAddNew});
  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onAddNew;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add item', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Flexible(
            child: products.isEmpty
                ? const AppEmptyState(icon: Icons.inventory_2_outlined, title: 'No products yet')
                : ListView(
                    shrinkWrap: true,
                    children: products
                        .map((p) => ListTile(
                              leading: InitialsAvatar(p.name, size: 36),
                              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${_qty(p.stock)} in stock  •  ${formatPaise(p.salePrice)}'),
                              onTap: () => onPick(p),
                            ))
                        .toList(),
                  ),
          ),
          TextButton.icon(onPressed: onAddNew, icon: const Icon(Icons.add_rounded), label: const Text('Create new product')),
        ]),
      ),
    );
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}

class _LineEditorSheet extends StatefulWidget {
  const _LineEditorSheet({required this.line, required this.onSave});
  final _LineEdit line;
  final ValueChanged<_LineEdit> onSave;
  @override
  State<_LineEditorSheet> createState() => _LineEditorSheetState();
}

class _LineEditorSheetState extends State<_LineEditorSheet> {
  late final TextEditingController qtyController;
  late final TextEditingController priceController;
  late final TextEditingController discountController;
  late int gstRate;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    qtyController = TextEditingController(text: _qty(line.qty));
    priceController = TextEditingController(text: line.price == 0 ? '' : (line.price / 100).toStringAsFixed(2));
    discountController = TextEditingController(text: line.discountPercent == 0 ? '' : _qty(line.discountPercent));
    gstRate = line.gstRate;
  }

  void _apply() {
    final qty = double.tryParse(qtyController.text.trim());
    final price = _toPaise(priceController.text);
    if (qty == null || qty <= 0 || price <= 0) return;
    final update = _LineEdit(
      product: widget.line.product,
      qty: qty,
      price: price,
      discountPercent: double.tryParse(discountController.text.trim()) ?? 0,
      gstRate: gstRate,
      taxIncluded: widget.line.taxIncluded,
    );
    widget.onSave(update);
    Navigator.of(context).pop();
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (line.product.hasBatch) ...[
              AppTextField(
                controller: TextEditingController(text: line.batch),
                label: 'Batch number',
                onChanged: (v) => line.batch = v,
              ),
              const SizedBox(height: 12),
            ],
            if (line.product.hasSerial) ...[
              AppTextField(
                controller: TextEditingController(text: line.serial),
                label: 'Serial / IMEI',
                onChanged: (v) => line.serial = v,
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(child: TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: inputDecoration('Quantity'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: inputDecoration('Unit price'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: discountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: inputDecoration('Discount %'))),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: gstRate,
                  decoration: inputDecoration('GST %'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0%')),
                    DropdownMenuItem(value: 5, child: Text('5%')),
                    DropdownMenuItem(value: 12, child: Text('12%')),
                    DropdownMenuItem(value: 18, child: Text('18%')),
                    DropdownMenuItem(value: 28, child: Text('28%')),
                  ],
                  onChanged: (v) => setState(() => gstRate = v ?? 0),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _apply, child: const Text('Apply')),
            ),
          ]),
        ),
      ),
    );
  }
}
