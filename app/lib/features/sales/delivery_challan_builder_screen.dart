import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../inventory/multi_product_picker_sheet.dart';
import 'delivery_challan_detail_screen.dart';

class DeliveryChallanBuilderScreen extends StatefulWidget {
  const DeliveryChallanBuilderScreen({super.key, this.fromInvoice, this.customerId});

  final Invoice? fromInvoice;
  final int? customerId;

  @override
  State<DeliveryChallanBuilderScreen> createState() => _DeliveryChallanBuilderScreenState();
}

class _ChallanLineItem {
  _ChallanLineItem({
    required this.name,
    this.productId,
    required this.qty,
    this.unit = 'pc',
    this.price = 0,
    this.included = true,
  });

  final String name;
  final int? productId;
  double qty;
  String unit;
  int price;
  bool included;
}

class _DeliveryChallanBuilderScreenState extends State<DeliveryChallanBuilderScreen> {
  final List<_ChallanLineItem> lines = [];
  List<Customer>? customers;
  List<Product>? products;
  int? customerId;
  String? customerName;
  Customer? selectedCustomer;

  final TextEditingController _numberCtrl = TextEditingController();
  final TextEditingController _vehicleCtrl = TextEditingController();
  final TextEditingController _transportCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  String challanDate = todayIso();
  bool saving = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initDraft();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _vehicleCtrl.dispose();
    _transportCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDraft() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final repo = Repository.instance;

    try {
      final custs = await repo.customers(businessId);
      final prods = await repo.products(businessId);
      final biz = await repo.getBusiness(businessId);
      final nextNum = await repo.peekNextChallanNumber(businessId);

      _numberCtrl.text = nextNum;
      _notesCtrl.text = biz?.termsChallan ?? 'Goods dispatched at consignee risk.';

      if (widget.fromInvoice != null) {
        final inv = widget.fromInvoice!;
        customerId = inv.customerId;
        customerName = inv.customerName;

        if (customerId != null && custs.any((c) => c.id == customerId)) {
          selectedCustomer = custs.firstWhere((c) => c.id == customerId);
        }

        // Prefill delivery address from invoice or customer
        _addressCtrl.text = inv.shipToAddress ?? selectedCustomer?.shippingAddress ?? selectedCustomer?.billingAddress ?? '';
        if (inv.vehicleNumber != null && inv.vehicleNumber!.isNotEmpty) {
          _vehicleCtrl.text = inv.vehicleNumber!;
        }
        if (inv.lrRrNumber != null && inv.lrRrNumber!.isNotEmpty) {
          _transportCtrl.text = inv.lrRrNumber!;
        }

        // Prefill items from invoice
        for (final item in inv.lines) {
          lines.add(_ChallanLineItem(
            name: item.name,
            productId: item.productId,
            qty: item.quantity,
            unit: item.unit ?? 'pc',
            price: item.price,
            included: true,
          ));
        }
      } else if (widget.customerId != null) {
        customerId = widget.customerId;
        if (custs.any((c) => c.id == customerId)) {
          selectedCustomer = custs.firstWhere((c) => c.id == customerId);
          customerName = selectedCustomer?.name;
          _addressCtrl.text = selectedCustomer?.shippingAddress ?? selectedCustomer?.billingAddress ?? '';
        }
      }

      if (mounted) {
        setState(() {
          customers = custs;
          products = prods;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(challanDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() => challanDate = isoDate(picked));
    }
  }

  void _openAddCustomerSheet() {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerFormSheet(
        businessId: bizId,
        onSaved: () async {
          final custs = await Repository.instance.customers(bizId);
          if (mounted) {
            setState(() {
              customers = custs;
              if (custs.isNotEmpty) {
                selectedCustomer = custs.first;
                customerId = selectedCustomer?.id;
                customerName = selectedCustomer?.name;
                _addressCtrl.text = selectedCustomer?.shippingAddress ?? selectedCustomer?.billingAddress ?? '';
              }
            });
          }
        },
      ),
    );
  }

  void _showProductPicker() {
    final all = products ?? const <Product>[];
    if (all.isEmpty) {
      showAppMessage(context, 'No products found. Add products in inventory first', error: true);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultiProductPickerSheet(
        products: all,
        title: 'Select Challan Items',
        actionLabel: 'Add to Challan',
        onItemsSelected: (selectedItems) {
          setState(() {
            for (final sel in selectedItems) {
              final existingIndex = lines.indexWhere((l) => l.productId == sel.product.id);
              if (existingIndex >= 0) {
                lines[existingIndex].qty += sel.quantity;
                lines[existingIndex].included = true;
              } else {
                lines.add(_ChallanLineItem(
                  name: sel.product.name,
                  productId: sel.product.id,
                  qty: sel.quantity,
                  unit: sel.product.unit,
                  price: sel.product.salePrice,
                  included: true,
                ));
              }
            }
          });
        },
      ),
    );
  }

  Future<void> _save() async {
    final validLines = lines.where((l) => l.included && l.qty > 0).toList();
    if (validLines.isEmpty) {
      showAppMessage(context, 'Please include at least one item to dispatch', error: true);
      return;
    }

    final finalNumber = _numberCtrl.text.trim();
    if (finalNumber.isEmpty) {
      showAppMessage(context, 'Challan number is required', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final bizId = context.read<Session>().businessId!;
      final challan = DeliveryChallan(
        businessId: bizId,
        number: finalNumber,
        customerId: customerId,
        customerName: customerName ?? selectedCustomer?.name,
        date: challanDate,
        address: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
        transportDetails: _transportCtrl.text.trim().isNotEmpty ? _transportCtrl.text.trim() : null,
        status: 'Pending',
        invoiceId: widget.fromInvoice?.id,
        invoiceNumber: widget.fromInvoice?.number,
        vehicleNo: _vehicleCtrl.text.trim().isNotEmpty ? _vehicleCtrl.text.trim().toUpperCase() : null,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        lines: validLines
            .map((l) => InvoiceLine(
                  productId: l.productId,
                  name: l.name,
                  quantity: l.qty,
                  price: l.price,
                  unit: l.unit,
                ))
            .toList(),
      );

      final challanId = await Repository.instance.finalizeDeliveryChallan(challan);
      if (!mounted) return;

      showAppMessage(context, 'Delivery Challan $finalNumber created successfully ✓');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryChallanDetailScreen(challanId: challanId),
        ),
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Delivery Challan')),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: const Text('Create Delivery Challan', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'About Delivery Challan',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: StitchColors.primary),
                      SizedBox(width: 8),
                      Text('Delivery Challan (Rule 55)'),
                    ],
                  ),
                  content: const Text(
                    'Under GST Rule 55, a Delivery Challan is issued for transportation of goods without immediate sale (or as proof of dispatch/goods delivery for an invoice). Enter vehicle and transporter details to ensure seamless gate-pass and transit compliance.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                // Linked Invoice Banner
                if (widget.fromInvoice != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dispatching items for Invoice ${widget.fromInvoice!.number}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Document Metadata Card (Challan No & Date)
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _numberCtrl,
                          decoration: InputDecoration(
                            labelText: 'Challan No.',
                            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: StitchColors.outline),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 16, color: StitchColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    displayDate(challanDate),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 12),

                // Vehicle & Transport Card (Core user requirement!)
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: StitchColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.directions_car_filled_rounded, size: 18, color: StitchColors.primary),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'VEHICLE & TRANSPORTATION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: StitchColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Vehicle Number (High priority field)
                      TextFormField(
                        controller: _vehicleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Vehicle Number *',
                          hintText: 'e.g. MH 12 AB 1234 or DL 01 A 9999',
                          prefixIcon: const Icon(Icons.commute_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 10),

                      // Transport Details / LR Number
                      TextFormField(
                        controller: _transportCtrl,
                        decoration: InputDecoration(
                          labelText: 'Transport Details / LR No.',
                          hintText: 'e.g. VRL Logistics • LR-49281 • Road',
                          prefixIcon: const Icon(Icons.local_shipping_outlined, size: 19),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Delivery Address
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: InputDecoration(
                          labelText: 'Delivery / Destination Address',
                          hintText: 'Enter full delivery destination address',
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 19),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Consignee / Customer Card
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CONSIGNEE / CLIENT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: StitchColors.textSecondary,
                            ),
                          ),
                          if (widget.fromInvoice == null)
                            TextButton.icon(
                              onPressed: _openAddCustomerSheet,
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                              label: const Text('Add Client', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (widget.fromInvoice != null) ...[
                        Text(
                          customerName ?? 'Walk-in Customer',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        if (selectedCustomer?.phone != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Phone: ${selectedCustomer!.phone}',
                            style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                          ),
                        ],
                      ] else ...[
                        DropdownButtonFormField<int>(
                          initialValue: customerId,
                          decoration: InputDecoration(
                            hintText: 'Select Client / Consignee',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: customers
                              ?.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              customerId = v;
                              selectedCustomer = customers?.firstWhere((c) => c.id == v);
                              customerName = selectedCustomer?.name;
                              final addr = selectedCustomer?.shippingAddress ?? selectedCustomer?.billingAddress;
                              if (addr != null && addr.isNotEmpty) {
                                _addressCtrl.text = addr;
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Items to Dispatch Card
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'DISPATCH ITEMS (${lines.where((l) => l.included).length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: StitchColors.textSecondary,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showProductPicker,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Items', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const Divider(height: 14),
                      if (lines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No items added to dispatch yet',
                              style: TextStyle(color: StitchColors.textSecondary, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ...lines.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: item.included ? Colors.white : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: item.included ? StitchColors.outline : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: item.included,
                                  onChanged: (val) {
                                    setState(() => item.included = val ?? true);
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          decoration: item.included ? null : TextDecoration.lineThrough,
                                          color: item.included ? Colors.black87 : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Unit: ${item.unit}',
                                        style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.included) ...[
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: item.qty > 1
                                        ? () => setState(() => item.qty -= 1)
                                        : null,
                                  ),
                                  Container(
                                    width: 44,
                                    alignment: Alignment.center,
                                    child: Text(
                                      item.qty == item.qty.roundToDouble()
                                          ? item.qty.round().toString()
                                          : item.qty.toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: () => setState(() => item.qty += 1),
                                  ),
                                ],
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: StitchColors.error),
                                  onPressed: () => setState(() => lines.removeAt(idx)),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Dispatch Notes & Terms
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISPATCH TERMS & CONDITIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: StitchColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesCtrl,
                        decoration: InputDecoration(
                          hintText: 'Enter dispatch terms and delivery instructions...',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sticky Bottom Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: saving ? null : _save,
                icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  saving ? 'Saving Challan...' : 'Generate Delivery Challan',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
