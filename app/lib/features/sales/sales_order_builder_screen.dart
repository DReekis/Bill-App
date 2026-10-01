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
import 'sales_order_detail_screen.dart';

class SalesOrderBuilderScreen extends StatefulWidget {
  const SalesOrderBuilderScreen({super.key, this.businessId, this.customerId});

  final int? businessId;
  final int? customerId;

  @override
  State<SalesOrderBuilderScreen> createState() => _SalesOrderBuilderScreenState();
}

class _LineEdit {
  _LineEdit({
    required this.product,
    required this.qty,
    required this.price,
  });
  final Product product;
  double qty;
  int price;

  int get subtotalPaise => (price * qty).round();
}

class _SalesOrderBuilderScreenState extends State<SalesOrderBuilderScreen> {
  final List<_LineEdit> lines = [];
  Business? business;
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  Customer? selectedCustomer;
  final TextEditingController _notesController = TextEditingController();
  bool saving = false;
  String? orderNumber;
  String orderDate = todayIso();
  String? dueDate;

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
      });
      if (orderNumber == null) {
        final nextNum = await repo.peekNextSalesOrderNumber(businessId);
        if (mounted) {
          setState(() => orderNumber = nextNum);
        }
      }
    } catch (_) {}
  }

  void _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final trimmed = code.trim();
    final allProds = products ?? const <Product>[];
    final match = allProds.cast<Product?>().firstWhere(
          (p) => p?.barcode == trimmed || p?.sku == trimmed,
          orElse: () => null,
        );

    if (match == null) {
      if (mounted) showAppMessage(context, 'No product with barcode "$trimmed" found', error: true);
      return;
    }

    final existingIndex = lines.indexWhere((l) => l.product.id == match.id);
    setState(() {
      if (existingIndex >= 0) {
        lines[existingIndex].qty += 1;
      } else {
        lines.add(_LineEdit(
          product: match,
          qty: 1,
          price: match.salePrice,
        ));
      }
    });
    if (mounted) showAppMessage(context, 'Scanned: ${match.name}');
  }

  void _showCustomerPickerSheet() {
    final bizId = widget.businessId ?? context.read<Session>().businessId;
    if (bizId == null) return;

    String searchQuery = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final allCusts = customers ?? const <Customer>[];
          final q = searchQuery.trim().toLowerCase();
          final filtered = q.isEmpty
              ? allCusts
              : allCusts.where((c) {
                  return c.name.toLowerCase().contains(q) ||
                      (c.phone != null && c.phone!.contains(q));
                }).toList();

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        'Select Customer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                // + Add New Customer Button at Top
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (subCtx) => CustomerFormSheet(
                            businessId: bizId,
                            onSaved: _load,
                            onSavedCustomer: (newCust) {
                              setState(() {
                                customerId = newCust.id;
                                customerName = newCust.name;
                                selectedCustomer = newCust;
                              });
                              showAppMessage(context, 'Selected ${newCust.name}');
                            },
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('+ Add New Customer', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => setModalState(() => searchQuery = ''),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setModalState(() => searchQuery = val),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (searchQuery.isEmpty)
                        ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: StitchColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_outline_rounded, color: StitchColors.primary, size: 20),
                          ),
                          title: const Text('Walk-in Customer', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Cash order / unregistered client', style: TextStyle(fontSize: 12)),
                          onTap: () {
                            setState(() {
                              customerId = null;
                              customerName = 'Walk-in Customer';
                              selectedCustomer = null;
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                      ...filtered.map((c) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: StitchColors.primary.withValues(alpha: 0.1),
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: StitchColors.primary),
                              ),
                            ),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              c.phone ?? (c.state != null ? 'State: ${c.state}' : 'Customer'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              setState(() {
                                customerId = c.id;
                                customerName = c.name;
                                selectedCustomer = c;
                              });
                              Navigator.pop(ctx);
                            },
                          )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showProductPicker() async {
    if (products == null || products!.isEmpty) {
      await _load();
    }
    if (!mounted) return;
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'No products found. Add products first', error: true);
      return;
    }

    final initialMap = <int, double>{};
    for (final l in lines) {
      if (l.product.id != null) {
        initialMap[l.product.id!] = l.qty;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MultiProductPickerSheet(
        products: all,
        title: 'Select Sell Order Items',
        actionLabel: 'Add to Order',
        initialQuantities: initialMap,
        onItemsSelected: (selectedItems) {
          setState(() {
            for (final item in selectedItems) {
              final existingIndex = lines.indexWhere((l) => l.product.id == item.product.id);
              if (existingIndex >= 0) {
                lines[existingIndex].qty = item.quantity;
                lines[existingIndex].price = item.unitPrice;
              } else {
                lines.add(_LineEdit(
                  product: item.product,
                  qty: item.quantity,
                  price: item.unitPrice,
                ));
              }
            }
          });
          showAppMessage(
            context,
            selectedItems.length == 1
                ? 'Added ${selectedItems.first.product.name} to order'
                : 'Added ${selectedItems.length} items to order',
          );
        },
        onAddNew: () async {
          Navigator.pop(context);
          final bizId = widget.businessId ?? context.read<Session>().businessId!;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _load,
              onSavedProduct: (p) {
                setState(() {
                  lines.add(_LineEdit(
                    product: p,
                    qty: 1,
                    price: p.salePrice,
                  ));
                });
              },
              businessId: bizId,
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (lines.isEmpty) {
      showAppMessage(context, 'Add at least one item to save the order', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = widget.businessId ?? context.read<Session>().businessId!;
      final repo = Repository.instance;
      final finalNumber = orderNumber ?? await repo.nextSalesOrderNumber(bizId);

      final total = lines.fold(0, (sum, l) => sum + l.subtotalPaise);
      final order = SalesOrder(
        businessId: bizId,
        number: finalNumber,
        customerId: customerId,
        customerName: customerName ?? 'Walk-in Customer',
        date: orderDate,
        dueDate: dueDate,
        status: 'Pending',
        total: total,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        lines: lines
            .map((l) => InvoiceLine(
                  productId: l.product.id,
                  name: l.product.name,
                  quantity: l.qty,
                  price: l.price,
                  unit: l.product.unit,
                  taxable: l.subtotalPaise,
                ))
            .toList(),
      );

      final orderId = await repo.finalizeSalesOrder(order);

      if (mounted) {
        showAppMessage(context, 'Sell Order $finalNumber saved successfully ✓');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SalesOrderDetailScreen(orderId: orderId),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error saving Sell Order: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPaise = lines.fold<int>(0, (sum, l) => sum + l.subtotalPaise);

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: const Text('New Sell Order', style: TextStyle(fontWeight: FontWeight.w700)),
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
          // Order Header Bar (Number & Dates)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final ctrl = TextEditingController(text: orderNumber ?? '');
                      final result = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Edit Order Number'),
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Order No.'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (result != null && result.isNotEmpty) {
                        setState(() => orderNumber = result);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD1C4E9)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF5E35B1)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Order No.', style: TextStyle(fontSize: 10, color: Color(0xFF5E35B1), fontWeight: FontWeight.w600)),
                                Text(
                                  orderNumber ?? 'SO-001',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF5E35B1)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF5E35B1)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final dt = dateTimeFor(orderDate);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dt,
                        firstDate: DateTime(dt.year - 2),
                        lastDate: DateTime(dt.year + 2),
                      );
                      if (picked != null) setState(() => orderDate = isoDate(picked));
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
                                const Text('Order Date', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                                Text(
                                  displayDate(orderDate),
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

          // Customer Selector Card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: InkWell(
              onTap: _showCustomerPickerSheet,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StitchColors.outline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_rounded, color: StitchColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName ?? 'Select Customer / Walk-in',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: customerName != null ? FontWeight.w700 : FontWeight.w500,
                              color: customerName != null ? StitchColors.textPrimary : StitchColors.textSecondary,
                            ),
                          ),
                          if (selectedCustomer?.phone != null && selectedCustomer!.phone!.isNotEmpty)
                            Text(
                              selectedCustomer!.phone!,
                              style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, color: StitchColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // Items List & Add Items
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEDE7F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shopping_basket_outlined, size: 32, color: Color(0xFF5E35B1)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No items added yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Add items to create this Sell Order',
                          style: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _showProductPicker,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Items'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF5E35B1),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: lines.length + 1,
                    itemBuilder: (context, index) {
                      if (index == lines.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: OutlinedButton.icon(
                            onPressed: _showProductPicker,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('+ Add More Items'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        );
                      }

                      final l = lines[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StitchColors.outline),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.product.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${formatPaise(l.price)} / ${l.product.unit}',
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            // Qty controls
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 22, color: StitchColors.error),
                                  onPressed: () {
                                    setState(() {
                                      if (l.qty > 1) {
                                        l.qty -= 1;
                                      } else {
                                        lines.removeAt(index);
                                      }
                                    });
                                  },
                                ),
                                Text(
                                  l.qty == l.qty.roundToDouble() ? '${l.qty.round()}' : '${l.qty}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 22, color: StitchColors.primary),
                                  onPressed: () {
                                    setState(() => l.qty += 1);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatPaise(l.subtotalPaise),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Expected Delivery Date & Notes
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate != null ? dateTimeFor(dueDate!) : DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => dueDate = isoDate(picked));
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 16, color: StitchColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          dueDate != null ? 'Due: ${displayDate(dueDate!)}' : 'Set Due Date',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dueDate != null ? StitchColors.primary : StitchColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      hintText: 'Notes / Instructions...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Bottom Bar (Total & Save)
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lines.length} ${lines.length == 1 ? 'item' : 'items'}',
                      style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      formatPaise(totalPaise),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: StitchColors.primary),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Save Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5E35B1),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
