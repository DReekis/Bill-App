import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../inventory/multi_product_picker_sheet.dart';
import '../inventory/product_form.dart';
import 'barcode_scanner_screen.dart';

class QuotationBuilderScreen extends StatefulWidget {
  const QuotationBuilderScreen({super.key, this.businessId, this.customerId});

  final int? businessId;
  final int? customerId;

  @override
  State<QuotationBuilderScreen> createState() => _QuotationBuilderScreenState();
}

class _LineEdit {
  _LineEdit({
    required this.product,
    required this.qty,
    required this.price,
    required this.discountPercent,
    required this.gstRate,
  });

  final Product product;
  double qty;
  int price;
  double discountPercent;
  int gstRate;

  int get subtotalPaise => (price * qty).round();
  int get discountPaise => (subtotalPaise * (discountPercent / 100)).round();
  int get taxablePaise => subtotalPaise - discountPaise;
  int get taxPaise => (taxablePaise * (gstRate / 100)).round();
  int get totalPaise => taxablePaise + taxPaise;
}

class _QuotationBuilderScreenState extends State<QuotationBuilderScreen> {
  final List<_LineEdit> lines = [];
  Business? business;
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  Customer? selectedCustomer;
  final TextEditingController _notesController = TextEditingController();
  bool saving = false;
  String? quotationNumber;
  String quotationDate = todayIso();

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) {
      customerId = widget.customerId;
    }
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final businessId = widget.businessId ?? context.read<Session>().businessId;
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
        if (customerId != null && custs.any((c) => c.id == customerId)) {
          selectedCustomer = custs.firstWhere((c) => c.id == customerId);
          customerName = selectedCustomer?.name;
        }
        if (quotationNumber == null && biz != null) {
          quotationNumber = InvoiceNumbering.format(biz.quotationPrefix, biz.quotationSequence + 1);
        }
        if (_notesController.text.trim().isEmpty && biz?.termsQuotation != null) {
          _notesController.text = biz!.termsQuotation!;
        }
      });
    } catch (_) {}
  }

  Future<void> _editQuotationNumber() async {
    final controller = TextEditingController(text: quotationNumber ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Text('Edit Estimate Number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a custom estimate number:', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: inputDecoration('Estimate Number', hint: 'e.g. EST-0001'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (updated != null && updated.isNotEmpty && mounted) {
      setState(() => quotationNumber = updated);
    }
  }

  /// Adds a product to the estimate draft or merges and auto-increments quantity
  /// if the product already exists in the current draft.
  void _addOrMergeProduct(
    Product product, {
    double quantity = 1,
    int? price,
    int? gstRate,
    double? discountPercent,
  }) {
    final existingIndex = lines.indexWhere((l) =>
        (l.product.id != null && product.id != null && l.product.id == product.id) ||
        (l.product.name.trim().toLowerCase() == product.name.trim().toLowerCase() &&
            l.product.name.trim().isNotEmpty));

    if (existingIndex >= 0) {
      lines[existingIndex].qty += quantity;
      if (price != null) {
        lines[existingIndex].price = price;
      }
    } else {
      lines.add(_LineEdit(
        product: product,
        qty: quantity,
        price: price ?? product.salePrice,
        discountPercent: discountPercent ?? 0,
        gstRate: gstRate ?? product.gstRate,
      ));
    }
  }

  static String _formatQty(num q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  int _subtotal() {
    int total = 0;
    for (final l in lines) {
      total += l.taxablePaise;
    }
    return total;
  }

  int _totalTax() {
    int tax = 0;
    for (final l in lines) {
      tax += l.taxPaise;
    }
    return tax;
  }

  int _total() => _subtotal() + _totalTax();

  Future<void> _showAddCustomerSheet() async {
    final bizId = widget.businessId ?? context.read<Session>().businessId;
    if (bizId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomerFormSheet(
        businessId: bizId,
        onSaved: () async {
          await _load();
        },
        onSavedCustomer: (newCustomer) async {
          await _load();
          if (mounted) {
            setState(() {
              customerId = newCustomer.id;
              customerName = newCustomer.name;
              selectedCustomer = newCustomer;
            });
            showAppMessage(context, 'Customer "${newCustomer.name}" added and selected');
          }
        },
      ),
    );
  }

  Future<void> _showProductPicker() async {
    if (products == null || products!.isEmpty) {
      await _load();
    }
    if (!mounted) return;
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'No products found. Add products first', error: true);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MultiProductPickerSheet(
        products: all,
        title: 'Select Estimate Items',
        actionLabel: 'Add to Estimate',
        onScanBarcode: _scanBarcode,
        onItemsSelected: (selectedItems) {
          int addedCount = 0;
          int mergedCount = 0;

          setState(() {
            for (final item in selectedItems) {
              final existingIndex = lines.indexWhere((l) =>
                  (l.product.id != null && item.product.id != null && l.product.id == item.product.id) ||
                  (l.product.name.trim().toLowerCase() == item.product.name.trim().toLowerCase() &&
                      l.product.name.trim().isNotEmpty));

              if (existingIndex >= 0) {
                lines[existingIndex].qty += item.quantity;
                lines[existingIndex].price = item.unitPrice;
                mergedCount++;
              } else {
                lines.add(_LineEdit(
                  product: item.product,
                  qty: item.quantity,
                  price: item.unitPrice,
                  discountPercent: 0,
                  gstRate: item.product.gstRate,
                ));
                addedCount++;
              }
            }
          });

          if (mergedCount > 0 && addedCount > 0) {
            showAppMessage(
              context,
              'Added $addedCount item(s) and merged $mergedCount existing item(s)',
            );
          } else if (mergedCount > 0) {
            showAppMessage(
              context,
              'Merged and incremented quantity for $mergedCount item(s)',
            );
          } else if (addedCount > 0) {
            showAppMessage(
              context,
              addedCount == 1
                  ? 'Added ${selectedItems.first.product.name} to estimate'
                  : 'Added $addedCount items to estimate',
            );
          }
        },
        onAddNew: () async {
          Navigator.pop(context);
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _load,
              onSavedProduct: (p) {
                setState(() {
                  _addOrMergeProduct(p, quantity: 1, price: p.salePrice);
                });
                showAppMessage(context, 'Added ${p.name} to estimate');
              },
              businessId: widget.businessId ?? context.read<Session>().businessId!,
            ),
          );
        },
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final product = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (product == null || !mounted) return;

    setState(() {
      _addOrMergeProduct(product, quantity: 1);
    });
    showAppMessage(context, 'Added ${product.name} to estimate');
  }

  Future<void> _showCustomQtyDialog(int index) async {
    final l = lines[index];
    final controller = TextEditingController(text: _formatQty(l.qty));

    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Quantity for ${l.product.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unit: ${l.product.unit.toUpperCase()} • Price: ${formatPaise(l.price)}',
              style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Enter Quantity',
                suffixText: l.product.unit,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, val);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (res != null && res > 0 && mounted) {
      setState(() => l.qty = res);
    }
  }

  Future<void> _save() async {
    if (customerId == null) {
      showAppMessage(context, 'Please select or add a customer', error: true);
      return;
    }
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item to the estimate', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = widget.businessId ?? context.read<Session>().businessId!;
      final subtotal = _subtotal();
      final totalTax = _totalTax();
      final grandTotal = subtotal + totalTax;

      final isInterState = business?.state != null &&
          selectedCustomer?.state != null &&
          business!.state!.trim().toLowerCase() != selectedCustomer!.state!.trim().toLowerCase();

      final cgst = isInterState ? 0 : (totalTax / 2).round();
      final sgst = isInterState ? 0 : (totalTax - cgst);
      final igst = isInterState ? totalTax : 0;

      final quoteNumber = (quotationNumber != null && quotationNumber!.trim().isNotEmpty)
          ? quotationNumber!.trim()
          : await Repository.instance.nextQuotationNumber(bizId, business?.quotationPrefix ?? 'EST');

      final quote = Quotation(
        businessId: bizId,
        number: quoteNumber,
        customerId: customerId,
        customerName: customerName,
        date: quotationDate,
        subtotal: subtotal,
        taxable: subtotal,
        cgst: cgst,
        sgst: sgst,
        igst: igst,
        total: grandTotal,
        status: 'Open',
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        lines: lines
            .map((l) => InvoiceLine(
                  productId: l.product.id,
                  name: l.product.name,
                  hsn: l.product.hsn,
                  quantity: l.qty,
                  price: l.price,
                  gstRate: l.gstRate,
                  discount: l.discountPaise,
                  discountPercent: l.discountPercent,
                  taxable: l.taxablePaise,
                  tax: l.taxPaise,
                  unit: l.product.unit,
                ))
            .toList(),
      );

      await Repository.instance.finalizeQuotation(quote);

      if (mounted) {
        showAppMessage(context, 'Estimate $quoteNumber saved successfully');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error saving estimate: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validCustomerId = (customers != null && customerId != null && customers!.any((c) => c.id == customerId))
        ? customerId
        : null;

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: const Text('New Estimate', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Scan Barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scanBarcode,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Document Meta: Estimate Number & Date
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _editQuotationNumber,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.request_quote_rounded, size: 16, color: Color(0xFFD97706)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Estimate No.', style: TextStyle(fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
                                Text(
                                  quotationNumber ?? 'EST-0001',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 14, color: Color(0xFFB45309)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final dt = dateTimeFor(quotationDate);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dt,
                        firstDate: DateTime(dt.year - 2),
                        lastDate: DateTime(dt.year + 2),
                      );
                      if (picked != null) setState(() => quotationDate = isoDate(picked));
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: StitchColors.outline),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: StitchColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Estimate Date', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                                Text(
                                  displayDate(quotationDate),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Customer Selection Card with Inline Add Customer button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: StitchColors.outline.withValues(alpha: 0.8))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 16, color: StitchColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'CLIENT / CUSTOMER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(validCustomerId),
                        initialValue: validCustomerId,
                        decoration: InputDecoration(
                          hintText: customers == null ? 'Loading clients...' : 'Select Client',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                        ),
                        isExpanded: true,
                        items: customers?.map((c) {
                          return DropdownMenuItem<int>(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            customerId = v;
                            selectedCustomer = customers?.firstWhere((c) => c.id == v);
                            customerName = selectedCustomer?.name;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _showAddCustomerSheet,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
                if (selectedCustomer != null && selectedCustomer!.phone != null && selectedCustomer!.phone!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Phone: ${selectedCustomer!.phone}${selectedCustomer!.state != null ? ' • State: ${selectedCustomer!.state}' : ''}',
                      style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),

          // Items Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'ITEMS (${lines.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: StitchColors.textSecondary,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showProductPicker,
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: const Text('Add Items'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // Line Items List or Empty State
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: StitchColors.primary.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.playlist_add_rounded, size: 40, color: StitchColors.primary),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'No items added to estimate',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Check off multiple products at once with bulk addition.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _showProductPicker,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add Items from Catalog'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final l = lines[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.product.name,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${formatPaise(l.price)} / ${l.product.unit}${l.gstRate > 0 ? ' • GST ${l.gstRate}%' : ''}',
                                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: StitchColors.error),
                                  onPressed: () => setState(() => lines.removeAt(index)),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                // Stepper controls: [-] [qty] [+]
                                Container(
                                  decoration: BoxDecoration(
                                    color: StitchColors.surfaceVariant.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: StitchColors.outline.withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            if (l.qty > 1) {
                                              l.qty -= 1;
                                            } else {
                                              lines.removeAt(index);
                                            }
                                          });
                                        },
                                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Icon(
                                            l.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                            size: 16,
                                            color: l.qty <= 1 ? StitchColors.error : StitchColors.primary,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _showCustomQtyDialog(index),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          child: Text(
                                            '${_formatQty(l.qty)} ${l.product.unit}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => setState(() => l.qty += 1),
                                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Icon(Icons.add_rounded, size: 16, color: StitchColors.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatPaise(l.totalPaise),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: StitchColors.primary,
                                      ),
                                    ),
                                    if (l.taxPaise > 0)
                                      Text(
                                        'Tax: ${formatPaise(l.taxPaise)}',
                                        style: const TextStyle(fontSize: 10, color: StitchColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Total Summary & Save Action Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: StitchColors.outline.withValues(alpha: 0.8))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, -2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${lines.length} item(s) • Tax: ${formatPaise(_totalTax())}',
                          style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                        ),
                        Text(
                          'Total: ${formatPaise(_total())}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: StitchColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 44,
                      child: AsyncButton(
                        label: 'Save Estimate',
                        expand: false,
                        loading: saving,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

