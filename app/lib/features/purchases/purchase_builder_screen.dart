import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../inventory/multi_product_picker_sheet.dart';
import '../inventory/product_form.dart';
import '../suppliers/supplier_form.dart';

class _PurchaseLine {
  _PurchaseLine({required this.product, required this.qty, required this.price, required this.tax});
  final Product? product;
  double qty;
  int price;
  int tax;
  String get label => product?.name ?? 'Item';
}

class PurchaseBuilderScreen extends StatefulWidget {
  const PurchaseBuilderScreen({super.key, this.initialSupplierId});
  final int? initialSupplierId;
  @override
  State<PurchaseBuilderScreen> createState() => _PurchaseBuilderScreenState();
}

class _PurchaseBuilderScreenState extends State<PurchaseBuilderScreen> {
  List<_PurchaseLine> lines = [];
  List<Product>? products;
  List<Supplier>? suppliers;
  int? supplierId;
  String? supplierName;
  bool directVendor = false;
  double total = 0;
  bool saving = false;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final prods = await repo.products(businessId);
    final supps = await repo.suppliers(businessId);
    if (!mounted) return;
    setState(() {
      products = prods;
      suppliers = supps;
      if (supplierId == null && widget.initialSupplierId != null) {
        for (final s in supps) {
          if (s.id == widget.initialSupplierId) {
            supplierId = s.id;
            supplierName = s.name;
            break;
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _pickSupplier() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final all = suppliers ?? const <Supplier>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select supplier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Direct / cash vendor', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() {
                  supplierId = null;
                  supplierName = 'Direct / cash vendor';
                  directVendor = true;
                });
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ...all.map((s) => ListTile(
                  leading: InitialsAvatar(s.name, size: 36),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.phone ?? ''),
                  onTap: () {
                    setState(() {
                      supplierId = s.id;
                      supplierName = s.name;
                      directVendor = false;
                    });
                    Navigator.pop(context);
                  },
                )),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => SupplierFormSheet(
                    onSaved: _load,
                    businessId: context.read<Session>().businessId!,
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add new party'),
            ),
          ]),
        );
      },
    );
  }

  void _addLine() {
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'Add products first from the Stock tab', error: true);
      return;
    }

    final initialMap = <int, double>{};
    for (final l in lines) {
      if (l.product?.id != null) {
        initialMap[l.product!.id!] = l.qty;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MultiProductPickerSheet(
        products: all,
        isPurchase: true,
        title: 'Select Purchase Items',
        actionLabel: 'Add to Purchase',
        initialQuantities: initialMap,
        onItemsSelected: (selectedItems) {
          setState(() {
            for (final item in selectedItems) {
              final existingIndex = lines.indexWhere((l) => l.product?.id == item.product.id);
              if (existingIndex >= 0) {
                lines[existingIndex].qty = item.quantity;
                lines[existingIndex].price = item.unitPrice;
              } else {
                lines.add(_PurchaseLine(
                  product: item.product,
                  qty: item.quantity,
                  price: item.unitPrice,
                  tax: item.product.gstRate,
                ));
              }
            }
          });
          showAppMessage(
            context,
            selectedItems.length == 1
                ? 'Added ${selectedItems.first.product.name} to purchase'
                : 'Added ${selectedItems.length} items to purchase',
          );
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
                  lines.add(_PurchaseLine(
                    product: p,
                    qty: 1,
                    price: p.purchasePrice == 0 ? 100 : p.purchasePrice,
                    tax: p.gstRate,
                  ));
                });
              },
              businessId: context.read<Session>().businessId!,
            ),
          );
        },
      ),
    );
  }

  void _editLine(int index) {
    final line = lines[index];
    final qty = TextEditingController(text: _qty(line.qty));
    final price = TextEditingController(text: (line.price / 100).toStringAsFixed(2));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: inputDecoration('Quantity'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: inputDecoration('Unit cost'))),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final q = double.tryParse(qty.text.trim());
                    final p = double.tryParse(price.text.trim());
                    if (q == null || q <= 0 || p == null || p <= 0) return;
                    setState(() {
                      line.qty = q;
                      line.price = (p * 100).round();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _checkout() async {
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item', error: true);
      return;
    }
    final businessId = context.read<Session>().businessId;
    if (businessId == null) {
      showAppMessage(context, 'No active business', error: true);
      return;
    }

    // Payment Type: 0 = Credit, 1 = Advance / Partial, 2 = Paid in Full
    int paymentType = (supplierId != null && !directVendor) ? 0 : 2;

    final paid = TextEditingController(
      text: paymentType == 0
          ? '0'
          : (paymentType == 2 ? (total / 100).toStringAsFixed(2) : ''),
    );
    String date = todayIso();
    String? mode = 'Cash';
    final notes = TextEditingController();
    final vendorSearchController = TextEditingController(
      text: (supplierId != null && !directVendor) ? (supplierName ?? '') : '',
    );
    final newVendorPhone = TextEditingController();
    bool isCreatingNewVendor = false;

    final commit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final totalPaise = total.toInt();
          final currentPaidPaise = _toPaise(paid.text);
          final balanceDuePaise = (totalPaise - currentPaidPaise).clamp(0, totalPaise);
          final allSupps = suppliers ?? const <Supplier>[];
          final query = vendorSearchController.text.trim().toLowerCase();
          final filteredSupps = allSupps.where((s) {
            if (query.isEmpty) return true;
            return s.name.toLowerCase().contains(query) || (s.phone?.contains(query) ?? false);
          }).toList();
          final bool exactMatch = allSupps.any((s) => s.name.trim().toLowerCase() == query);

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header with Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Purchase Payment',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: StitchColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatPaise(totalPaise),
                            style: const TextStyle(
                              color: StitchColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Segmented Payment Type Selector: Credit vs Advance vs Full
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('Credit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('Advance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          icon: Icon(Icons.payments_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 2,
                          label: Text('Paid in Full', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          icon: Icon(Icons.check_circle_outline_rounded, size: 16),
                        ),
                      ],
                      selected: {paymentType},
                      onSelectionChanged: (s) {
                        setSheetState(() {
                          paymentType = s.first;
                          if (paymentType == 0) {
                            paid.text = '0';
                            mode = 'Credit';
                          } else if (paymentType == 2) {
                            paid.text = (total / 100).toStringAsFixed(2);
                            if (mode == 'Credit') mode = 'Cash';
                          } else if (paymentType == 1) {
                            if (paid.text == '0' || paid.text == (total / 100).toStringAsFixed(2)) {
                              paid.text = '';
                            }
                            if (mode == 'Credit') mode = 'Cash';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // If Credit or Partial -> Supplier Search & Selection
                    if (paymentType == 0 || paymentType == 1) ...[
                      if (supplierId != null && !directVendor) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F8F4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFA5D6A7)),
                          ),
                          child: Row(
                            children: [
                              InitialsAvatar(supplierName ?? 'Supplier', size: 36),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      supplierName ?? 'Supplier',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                    const Text(
                                      'Selected Supplier for Credit',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  setSheetState(() {
                                    supplierId = null;
                                    supplierName = null;
                                    directVendor = false;
                                    vendorSearchController.clear();
                                    isCreatingNewVendor = false;
                                  });
                                },
                                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                label: const Text('Change'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFF1B8A4C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFE082)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.person_search_rounded, size: 18, color: Color(0xFFE65100)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Select Supplier for Credit *',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: vendorSearchController,
                                decoration: InputDecoration(
                                  hintText: 'Search or enter supplier name...',
                                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                  suffixIcon: vendorSearchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          onPressed: () {
                                            setSheetState(() {
                                              vendorSearchController.clear();
                                              isCreatingNewVendor = false;
                                            });
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: StitchColors.primary, width: 1.5),
                                  ),
                                ),
                                onChanged: (v) {
                                  setSheetState(() {
                                    isCreatingNewVendor = false;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              if (filteredSupps.isNotEmpty || query.isNotEmpty)
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 150),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: ListView(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    children: [
                                      ...filteredSupps.map((s) => ListTile(
                                            dense: true,
                                            leading: InitialsAvatar(s.name, size: 28),
                                            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                            subtitle: s.phone != null && s.phone!.isNotEmpty
                                                ? Text(s.phone!, style: const TextStyle(fontSize: 11))
                                                : null,
                                            trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
                                            onTap: () {
                                              setSheetState(() {
                                                supplierId = s.id;
                                                supplierName = s.name;
                                                directVendor = false;
                                                isCreatingNewVendor = false;
                                                vendorSearchController.text = s.name;
                                              });
                                            },
                                          )),
                                      if (query.isNotEmpty && !exactMatch)
                                        ListTile(
                                          dense: true,
                                          leading: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                                            child: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF2E7D32)),
                                          ),
                                          title: Text(
                                            '+ Add "${vendorSearchController.text.trim()}"',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2E7D32), fontSize: 13),
                                          ),
                                          subtitle: const Text('Add and select as new supplier', style: TextStyle(fontSize: 11)),
                                          onTap: () {
                                            setSheetState(() {
                                              isCreatingNewVendor = true;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                )
                              else if (allSupps.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'Type supplier name above to add them automatically',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                  ),
                                ),

                              if (isCreatingNewVendor || (query.isNotEmpty && !exactMatch && filteredSupps.isEmpty)) ...[
                                const SizedBox(height: 8),
                                AppTextField(
                                  controller: newVendorPhone,
                                  label: 'Phone Number (Optional)',
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],

                    // Advance field for Partial
                    if (paymentType == 1) ...[
                      AppAmountField(
                        controller: paid,
                        label: 'Advance Amount Paid Now',
                      ),
                      const SizedBox(height: 8),
                      // Quick Chips for Advance
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (totalPaise > 200000)
                              _quickChip('₹1,000', 1000, paid, setSheetState),
                            if (totalPaise > 400000)
                              _quickChip('₹2,000', 2000, paid, setSheetState),
                            if (totalPaise > 1000000)
                              _quickChip('₹5,000', 5000, paid, setSheetState),
                            _quickChip('50%', (total / 200).round(), paid, setSheetState),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Payment Mode (for Advance or Full)
                    if (paymentType != 0) ...[
                      DropdownButtonFormField<String>(
                        initialValue: (mode != null && mode != 'Credit') ? mode : 'Cash',
                        decoration: inputDecoration(paymentType == 1 ? 'Advance Payment Mode' : 'Payment Mode'),
                        items: paymentModes
                            .where((m) => m != 'Credit')
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) => setSheetState(() => mode = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Live Balance Status Card
                    if (paymentType == 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF4F4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFCDD2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFEBEE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFC62828), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Balance to pay: ${formatPaise(totalPaise)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: Color(0xFFC62828),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'This entire purchase will be added to "To Pay"',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (paymentType == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Bill:', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                                Text(formatPaise(totalPaise), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Advance Paid (${mode ?? 'Cash'}):', style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
                                Text('- ${formatPaise(currentPaidPaise)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.success)),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Balance to pay (To Pay):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFC62828))),
                                Text(formatPaise(balanceDuePaise), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFC62828))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA5D6A7)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Paid in Full • No balance owed',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF2E7D32)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    AppTextField(controller: notes, label: 'Notes (optional)'),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: AsyncButton(
                        label: 'Save purchase',
                        onPressed: () {
                          if (paymentType == 0 || paymentType == 1) {
                            final hasExisting = supplierId != null && !directVendor;
                            final hasTyped = vendorSearchController.text.trim().isNotEmpty;
                            if (!hasExisting && !hasTyped) {
                              showAppMessage(context, 'Please select or enter a supplier for credit purchase', error: true);
                              return;
                            }
                          }
                          Navigator.pop(context, true);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (commit != true) return;
    setState(() => saving = true);
    try {
      // If vendor was entered by name, auto-create the supplier!
      if ((paymentType == 0 || paymentType == 1) && (supplierId == null || directVendor) && vendorSearchController.text.trim().isNotEmpty) {
        final name = vendorSearchController.text.trim();
        final phone = newVendorPhone.text.trim().isEmpty ? null : newVendorPhone.text.trim();
        final newId = await Repository.instance.upsertSupplier(Supplier(
          name: name,
          phone: phone,
        ));
        supplierId = newId;
        supplierName = name;
        directVendor = false;
      }

      final items = lines
          .map((l) => (
                l.product?.id,
                l.label,
                l.qty,
                l.price,
                l.tax,
              ))
          .toList();
      final paidAmount = paymentType == 0 ? 0 : _toPaise(paid.text);
      await Repository.instance.createPurchase(
        businessId: businessId,
        supplierId: supplierId,
        supplierName: supplierName ?? 'Direct vendor',
        date: date,
        items: items,
        amountPaid: paidAmount,
        paymentMode: paidAmount > 0 ? (mode ?? 'Cash') : 'Credit',
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      if (mounted) {
        showAppMessage(context, 'Purchase saved · stock updated');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _quickChip(String label, int amountRupees, TextEditingController paid, StateSetter setSheetState) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        onPressed: () {
          setSheetState(() {
            paid.text = amountRupees.toString();
          });
        },
      ),
    );
  }

  void _recomputeTotal() {
    total = lines.fold<double>(0, (sum, l) =>
        sum + (l.price * l.qty).round() + ((l.price * l.qty * l.tax / 100).round()));
  }

  @override
  Widget build(BuildContext context) {
    _recomputeTotal();
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        AppCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            onTap: _pickSupplier,
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              if (supplierName != null)
                InitialsAvatar(supplierName!, size: 38)
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: StitchColors.surfaceVariant, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.storefront_outlined, color: StitchColors.primary, size: 20),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(supplierName ?? 'Select supplier',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: supplierName == null ? StitchColors.textSecondary : StitchColors.textPrimary)),
                  const Text('Direct vendor if none', style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: StitchColors.textTertiary),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add item')),
        ]),
        if (lines.isEmpty)
          AppEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'No items yet',
            subtitle: 'Add products to record the purchase',
            action: OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Item'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF335C8D),
                side: BorderSide(color: const Color(0xFF335C8D).withValues(alpha: 0.4)),
              ),
            ),
          )
        else
          ...lines.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _editLine(e.key),
                  borderRadius: BorderRadius.circular(12),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.value.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('${_qty(e.value.qty)} × ${formatPaise(e.value.price)} ${e.value.tax > 0 ? "· GST ${e.value.tax}%" : ""}',
                              style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                        ]),
                      ),
                      Text(formatPaise((e.value.price * e.value.qty * (1 + e.value.tax / 100)).round()),
                          style: moneyStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => lines.removeAt(e.key)),
                        icon: const Icon(Icons.close_rounded, size: 17),
                        color: StitchColors.textTertiary,
                      ),
                    ]),
                  ),
                ),
              )),
        if (lines.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total cost', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(formatPaise(total.round()), style: moneyStyle(fontSize: 15)),
            ]),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AsyncButton(
            loading: saving,
            icon: lines.isEmpty ? Icons.add_rounded : Icons.local_shipping_rounded,
            label: lines.isEmpty ? 'Add items' : 'Save purchase ${formatPaise(total.round())}',
            backgroundColor: lines.isEmpty ? const Color(0xFF4A6DA7) : StitchColors.primary,
            onPressed: lines.isEmpty ? _addLine : _checkout,
          ),
        ),
      ),
    );
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
}