import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'barcode_scanner_screen.dart';

class InvoiceBuilderScreen extends StatefulWidget {
  const InvoiceBuilderScreen({super.key, this.customerId});
  final int? customerId;
  @override
  State<InvoiceBuilderScreen> createState() => _InvoiceBuilderScreenState();
}

class _LineEdit {
  _LineEdit({
    required this.product,
    required this.qty,
    required this.price,
    required this.discountPercent,
    required this.gstRate,
    required this.taxIncluded,
    this.batch,
    this.serial,
  });
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
  String? dueDate;
  String invoiceDiscountType = 'percent';
  double invoiceDiscountValue = 0;
  bool saving = false;
  bool _checkedDraft = false;

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
    } else if (!_checkedDraft) {
      _checkedDraft = true;
      await _checkDraft(businessId);
    }
  }

  static String _draftKey(int bizId) => 'draft_invoice_$bizId';

  Future<void> _saveDraft() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (lines.isEmpty && customerId == null) {
      await prefs.remove(_draftKey(businessId));
      return;
    }
    final data = {
      'customerId': customerId,
      'customerName': customerName,
      'customerState': customerState,
      'dueDate': dueDate,
      'invoiceDiscountType': invoiceDiscountType,
      'invoiceDiscountValue': invoiceDiscountValue,
      'lines': lines.map((l) => {
        'productId': l.product.id,
        'productName': l.product.name,
        'qty': l.qty,
        'price': l.price,
        'discountPercent': l.discountPercent,
        'gstRate': l.gstRate,
        'taxIncluded': l.taxIncluded,
        'batch': l.batch,
        'serial': l.serial,
      }).toList(),
    };
    await prefs.setString(_draftKey(businessId), jsonEncode(data));
  }

  Future<void> _checkDraft(int bizId) async {
    if (widget.customerId != null || lines.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey(bizId));
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final draftLines = (decoded['lines'] as List?) ?? [];
      if (draftLines.isEmpty) return;

      if (!mounted) return;
      final resume = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.restore_page_outlined, color: StitchColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Resume Unfinished Draft?',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Found an unfinished invoice draft with ${draftLines.length} ${draftLines.length == 1 ? "item" : "items"}'
                  '${decoded["customerName"] != null ? " for ${decoded["customerName"]}" : ""}. Would you like to restore it?',
                  style: const TextStyle(fontSize: 13.5, color: StitchColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await prefs.remove(_draftKey(bizId));
                          if (ctx.mounted) Navigator.pop(ctx, false);
                        },
                        child: const Text('Discard Draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Resume Draft'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (resume == true && mounted) {
        final restored = <_LineEdit>[];
        for (final item in draftLines) {
          final pId = item['productId'] as int?;
          Product? prod;
          if (pId != null && products != null) {
            for (final p in products!) {
              if (p.id == pId) {
                prod = p;
                break;
              }
            }
          }
          prod ??= Product(
            id: pId,
            name: (item['productName'] as String?) ?? 'Item',
            salePrice: (item['price'] as num?)?.toInt() ?? 0,
            gstRate: (item['gstRate'] as num?)?.toInt() ?? 0,
            taxIncluded: item['taxIncluded'] == true,
          );

          restored.add(_LineEdit(
            product: prod,
            qty: (item['qty'] as num?)?.toDouble() ?? 1.0,
            price: (item['price'] as num?)?.toInt() ?? 0,
            discountPercent: (item['discountPercent'] as num?)?.toDouble() ?? 0.0,
            gstRate: (item['gstRate'] as num?)?.toInt() ?? 0,
            taxIncluded: item['taxIncluded'] == true,
            batch: item['batch'] as String?,
            serial: item['serial'] as String?,
          ));
        }

        setState(() {
          lines = restored;
          customerId = decoded['customerId'] as int?;
          customerName = decoded['customerName'] as String?;
          customerState = decoded['customerState'] as String?;
          dueDate = decoded['dueDate'] as String?;
          invoiceDiscountType = (decoded['invoiceDiscountType'] as String?) ?? 'percent';
          invoiceDiscountValue = (decoded['invoiceDiscountValue'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {
      await prefs.remove(_draftKey(bizId));
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
      if (c.paymentTermsDays > 0) {
        dueDate = isoDate(DateTime.now().add(Duration(days: c.paymentTermsDays)));
      } else {
        dueDate = null;
      }
    });
    _saveDraft();
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

  Future<void> _scanBarcode() async {
    final product = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (product == null || !mounted) return;

    _refreshProducts();

    setState(() {
      final existingIndex = lines.indexWhere((l) => l.product.id != null && l.product.id == product.id);
      if (existingIndex >= 0) {
        lines[existingIndex].qty += 1;
        showAppMessage(context, 'Incremented ${product.name} (Qty: ${_trimNum(lines[existingIndex].qty)})');
      } else {
        lines.add(_LineEdit(
          product: product,
          qty: 1,
          price: product.salePrice,
          discountPercent: 0,
          gstRate: product.gstRate,
          taxIncluded: product.taxIncluded,
        ));
        showAppMessage(context, 'Added ${product.name} to bill');
      }
    });
    _saveDraft();
  }

  void _addItem() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductPickerSheet(
        products: products ?? const [],
        onPick: (product) {
          Navigator.pop(context);
          _editLine(_LineEdit(
            product: product,
            qty: 1,
            price: product.salePrice,
            discountPercent: 0,
            gstRate: product.gstRate,
            taxIncluded: product.taxIncluded,
          ));
        },
        onAddNew: () async {
          Navigator.pop(context);
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _refreshProducts,
              onSavedProduct: (p) => _editLine(_LineEdit(
                product: p,
                qty: 1,
                price: p.salePrice,
                discountPercent: 0,
                gstRate: p.gstRate,
                taxIncluded: p.taxIncluded,
              )),
              businessId: context.read<Session>().businessId!,
            ),
          );
        },
        onScanBarcode: () {
          Navigator.pop(context);
          _scanBarcode();
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
        _saveDraft();
      }),
    );
  }

  void _removeLine(_LineEdit line) {
    setState(() => lines.remove(line));
    _saveDraft();
  }

  Future<void> _checkout() async {
    final q = quote;
    final biz = business;
    if (q == null || biz == null) return;
    String invoiceDate = todayIso();
    String? checkoutDueDate = dueDate;
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
                  suffixIcon: TextButton(
                    onPressed: () {
                      final totalRupees = q.total.paise / 100.0;
                      paidController.text = totalRupees == totalRupees.roundToDouble()
                          ? totalRupees.round().toString()
                          : totalRupees.toStringAsFixed(2);
                      setSheetState(() {});
                    },
                    child: const Text('Full', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
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
                        label: Text('Date: $invoiceDate', overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final dt = checkoutDueDate != null ? dateTimeFor(checkoutDueDate!) : DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dt,
                            firstDate: DateTime(dt.year - 1),
                            lastDate: DateTime(dt.year + 2),
                          );
                          if (picked != null) setSheetState(() => checkoutDueDate = isoDate(picked));
                        },
                        icon: const Icon(Icons.event_available_rounded, size: 16),
                        label: Text(checkoutDueDate != null ? 'Due: $checkoutDueDate' : 'Set due date', overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  ],
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
    if (commit != true || !mounted) return;
    final finalQuote = _quoteFor(intraStateOverride: gstType == 'intra') ?? q;
    final total = finalQuote.total.paise;
    final amountPaid = _toPaise(paidController.text);
    final unpaid = total - amountPaid;

    if (customerId != null && unpaid > 0) {
      if (!mounted) return;
      final session = context.read<Session>();
      final bizId = session.businessId!;
      Customer? cust;
      if (customers != null) {
        for (final c in customers!) {
          if (c.id == customerId) {
            cust = c;
            break;
          }
        }
      }
      if (cust != null && cust.creditLimit > 0) {
        final currentBal = await Repository.instance.partyBalance(bizId, 'customer', customerId!);
        final projectedBal = currentBal + unpaid;
        if (projectedBal > cust.creditLimit) {
          if (!mounted) return;
          final overage = projectedBal - cust.creditLimit;
          final allow = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StitchColors.warning.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: StitchColors.warning, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Credit Limit Exceeded', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cust!.name} has an approved credit limit of ${formatPaise(cust.creditLimit)}. This transaction pushes their balance past the credit limit.',
                    style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StitchColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _creditLimitRow('Current Outstanding', formatPaise(currentBal)),
                        const SizedBox(height: 6),
                        _creditLimitRow('New Credit (Unpaid)', formatPaise(unpaid)),
                        const Divider(height: 14),
                        _creditLimitRow('Projected Balance', formatPaise(projectedBal), isBold: true),
                        const SizedBox(height: 6),
                        _creditLimitRow('Approved Credit Limit', formatPaise(cust.creditLimit)),
                        const SizedBox(height: 6),
                        _creditLimitRow('Limit Exceeded By', formatPaise(overage), valueColor: StitchColors.error, isBold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Do you want to authorize and proceed anyway?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel & Adjust'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: StitchColors.warning),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Authorize & Proceed'),
                ),
              ],
            ),
          );
          if (allow != true) return;
        }
      }
    }

    await _save(
      finalQuote,
      biz,
      date: invoiceDate,
      dueDate: checkoutDueDate,
      gstType: gstType,
      mode: mode,
      paidController: paidController,
      notesController: notesController,
    );
  }

  Future<void> _save(
    QuoteResult q,
    Business biz, {
    required String date,
    String? dueDate,
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
        dueDate: dueDate,
        gstType: gstType,
        quote: q,
        lines: invoiceLines,
        paymentMode: amountPaid > 0 ? (mode ?? 'Cash') : null,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        amountPaid: amountPaid,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey(businessId));

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

  Widget _creditLimitRow(String label, String value, {bool isBold = false, Color? valueColor}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: StitchColors.textSecondary, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600, color: valueColor ?? StitchColors.textPrimary)),
        ],
      );

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
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scanBarcode,
          ),
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
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20, color: StitchColors.primary),
            onPressed: _scanBarcode,
          ),
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

  Widget _invoiceDiscountRow(QuoteResult q) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Invoice discount', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
            if (invoiceDiscountValue <= 0.0)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                onPressed: () => _setDiscount(),
                child: const Text('Add'),
              )
            else
              InkWell(
                onTap: () => _setDiscount(),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_outlined, size: 14, color: StitchColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '-${formatPaise(q.invoiceDiscount.paise)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: StitchColors.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
                        _saveDraft();
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

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({
    required this.products,
    required this.onPick,
    required this.onAddNew,
    this.onScanBarcode,
  });
  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onAddNew;
  final VoidCallback? onScanBarcode;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _qty(num q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  List<String> _getCategories() {
    final cats = <String>['All'];
    for (final p in widget.products) {
      final c = p.category?.trim();
      if (c != null && c.isNotEmpty && !cats.contains(c)) {
        cats.add(c);
      }
    }
    return cats;
  }

  List<Product> _getFilteredProducts() {
    final query = _searchController.text.trim().toLowerCase();
    return widget.products.where((p) {
      final matchesCategory = _selectedCategory == 'All' ||
          (p.category != null && p.category!.trim() == _selectedCategory);
      if (!matchesCategory) return false;

      if (query.isEmpty) return true;
      final name = p.name.toLowerCase();
      final sku = (p.sku ?? '').toLowerCase();
      final barcode = (p.barcode ?? '').toLowerCase();
      final hsn = (p.hsn ?? '').toLowerCase();
      final brand = (p.brand ?? '').toLowerCase();

      return name.contains(query) ||
          sku.contains(query) ||
          barcode.contains(query) ||
          hsn.contains(query) ||
          brand.contains(query);
    }).toList();
  }

  Widget _buildStockBadge(num stock) {
    if (stock <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: StitchColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Out of stock',
          style: TextStyle(
            color: StitchColors.error,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (stock <= 5) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: StitchColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Low stock (${_qty(stock)})',
          style: const TextStyle(
            color: StitchColors.warning,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: StitchColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${_qty(stock)} in stock',
          style: const TextStyle(
            color: StitchColors.success,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _getCategories();
    final filtered = _getFilteredProducts();
    final isSearching = _searchController.text.trim().isNotEmpty;
    final topSellers = widget.products.take(6).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Add Item to Bill',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.onAddNew,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New Product'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by name, SKU, or barcode...',
                      hintStyle: const TextStyle(fontSize: 13, color: StitchColors.textTertiary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: StitchColors.textSecondary),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSearching)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          if (widget.onScanBarcode != null)
                            IconButton(
                              tooltip: 'Scan Barcode',
                              icon: const Icon(Icons.qr_code_scanner_rounded, color: StitchColors.primary),
                              onPressed: widget.onScanBarcode,
                            ),
                        ],
                      ),
                      filled: true,
                      fillColor: StitchColors.surfaceVariant.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (categories.length > 1)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final cat = categories[i];
                    final isSelected = cat == _selectedCategory;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? StitchColors.primary : StitchColors.textPrimary,
                      ),
                      selectedColor: StitchColors.primary.withValues(alpha: 0.12),
                      backgroundColor: StitchColors.surfaceVariant.withValues(alpha: 0.5),
                      side: BorderSide(
                        color: isSelected ? StitchColors.primary : Colors.transparent,
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            if (!isSearching && _selectedCategory == 'All' && topSellers.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 16, color: StitchColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'QUICK ADD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: topSellers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final p = topSellers[i];
                    return InkWell(
                      onTap: () => widget.onPick(p),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 135,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: StitchColors.surfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatPaise(p.salePrice),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: StitchColors.primary),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: StitchColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
            ],
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              isSearching ? 'No products match "${_searchController.text}"' : 'No products found',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: widget.onAddNew,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Create This Product'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        final details = <String>[];
                        if (p.category != null && p.category!.isNotEmpty) details.add(p.category!);
                        if (p.sku != null && p.sku!.isNotEmpty) details.add('SKU: ${p.sku}');
                        if (p.barcode != null && p.barcode!.isNotEmpty) details.add('BC: ${p.barcode}');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: InitialsAvatar(p.name, size: 40),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (details.isNotEmpty)
                                Text(
                                  details.join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                ),
                              const SizedBox(height: 3),
                              _buildStockBadge(p.stock),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatPaise(p.salePrice),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '+ Add',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: StitchColors.primary,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => widget.onPick(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
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
  late final TextEditingController batchController;
  late final TextEditingController serialController;
  late int gstRate;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    qtyController = TextEditingController(text: _qty(line.qty));
    priceController = TextEditingController(text: line.price == 0 ? '' : (line.price / 100).toStringAsFixed(2));
    discountController = TextEditingController(text: line.discountPercent == 0 ? '' : _qty(line.discountPercent));
    batchController = TextEditingController(text: line.batch ?? '');
    serialController = TextEditingController(text: line.serial ?? '');
    gstRate = line.gstRate;
  }

  @override
  void dispose() {
    qtyController.dispose();
    priceController.dispose();
    discountController.dispose();
    batchController.dispose();
    serialController.dispose();
    super.dispose();
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
      batch: batchController.text.trim().isEmpty ? null : batchController.text.trim(),
      serial: serialController.text.trim().isEmpty ? null : serialController.text.trim(),
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
                controller: batchController,
                label: 'Batch number',
              ),
              const SizedBox(height: 12),
            ],
            if (line.product.hasSerial) ...[
              AppTextField(
                controller: serialController,
                label: 'Serial / IMEI',
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
