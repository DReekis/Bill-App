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
import '../suppliers/supplier_form.dart';
import 'note_detail_screen.dart';

class _NoteLine {
  _NoteLine({
    this.productId,
    required this.name,
    this.hsn,
    this.unit,
    required this.qty,
    required this.price,
    this.gstRate = 0,
    this.maxQty,
  });

  final int? productId;
  final String name;
  final String? hsn;
  final String? unit;
  double qty;
  int price; // in paise
  int gstRate;
  final double? maxQty;

  int get subtotalPaise => (price * qty).round();
  int get taxPaise => (subtotalPaise * (gstRate / 100)).round();
  int get totalPaise => subtotalPaise + taxPaise;
}

class NoteBuilderScreen extends StatefulWidget {
  const NoteBuilderScreen({
    super.key,
    this.partyType = 'customer', // 'customer' for Credit Note, 'supplier' for Debit Note
    this.fromInvoice,
    this.fromPurchase,
    this.initialPartyId,
  });

  final String partyType;
  final Invoice? fromInvoice;
  final PurchaseBill? fromPurchase;
  final int? initialPartyId;

  @override
  State<NoteBuilderScreen> createState() => _NoteBuilderScreenState();
}

class _NoteBuilderScreenState extends State<NoteBuilderScreen> {
  late String _partyType;
  final List<_NoteLine> _lines = [];

  Business? _business;
  List<Customer>? _customers;
  List<Supplier>? _suppliers;
  List<Product>? _products;

  Customer? _selectedCustomer;
  Supplier? _selectedSupplier;

  String? _noteNumber;
  String _noteDate = todayIso();
  String _selectedReason = 'Sales Return / Goods Returned';
  final TextEditingController _customReasonController = TextEditingController();
  bool _saving = false;
  bool _loading = true;

  static const List<String> _creditReasons = [
    'Sales Return / Goods Returned',
    'Damaged / Defective Goods',
    'Post-Sale Discount / Rebate',
    'Rate Difference / Price Reduction',
    'Short Delivery / Shortage',
    'Invoice Correction',
    'Other',
  ];

  static const List<String> _debitReasons = [
    'Purchase Return / Goods Returned',
    'Damaged / Defective Goods',
    'Purchase Rebate / Discount Received',
    'Rate Difference / Overcharged',
    'Short Delivery Received',
    'Bill Correction',
    'Other',
  ];

  bool get _isCredit => _partyType == 'customer';
  bool get _isLinked => widget.fromInvoice != null || widget.fromPurchase != null;

  @override
  void initState() {
    super.initState();
    _partyType = widget.partyType;
    if (!_isCredit) {
      _selectedReason = 'Purchase Return / Goods Returned';
    }
    _initData();
  }

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final session = context.read<Session>();
    final bizId = session.businessId;
    if (bizId == null) return;

    final repo = Repository.instance;
    final biz = await repo.getBusiness(bizId);
    final custs = await repo.customers(bizId);
    final supps = await repo.suppliers(bizId);
    final prods = await repo.products(bizId);

    Customer? selC;
    Supplier? selS;

    if (widget.fromInvoice != null) {
      _partyType = 'customer';
      _selectedReason = 'Sales Return / Goods Returned';
      final inv = widget.fromInvoice!;
      if (inv.customerId != null) {
        for (final c in custs) {
          if (c.id == inv.customerId) {
            selC = c;
            break;
          }
        }
      }
      selC ??= Customer(
        id: inv.customerId,
        name: inv.customerName ?? 'Customer',
      );

      _lines.clear();
      for (final l in inv.lines) {
        _lines.add(_NoteLine(
          productId: l.productId,
          name: l.name,
          hsn: l.hsn,
          unit: l.unit,
          qty: l.quantity, // default to returning full invoice line, user can edit
          price: l.price,
          gstRate: l.gstRate,
          maxQty: l.quantity,
        ));
      }
    } else if (widget.fromPurchase != null) {
      _partyType = 'supplier';
      _selectedReason = 'Purchase Return / Goods Returned';
      final pur = widget.fromPurchase!;
      if (pur.supplierId != null) {
        for (final s in supps) {
          if (s.id == pur.supplierId) {
            selS = s;
            break;
          }
        }
      }
      selS ??= Supplier(
        id: pur.supplierId,
        name: pur.supplierName ?? 'Supplier',
        phone: pur.supplierPhone,
        address: pur.supplierAddress,
        gstin: pur.supplierGstin,
      );

      _lines.clear();
      for (final l in pur.lines) {
        _lines.add(_NoteLine(
          productId: l.productId,
          name: l.name,
          hsn: l.hsn,
          unit: l.unit,
          qty: l.quantity,
          price: l.price,
          gstRate: l.gstRate,
          maxQty: l.quantity,
        ));
      }
    } else if (widget.initialPartyId != null) {
      if (_isCredit) {
        for (final c in custs) {
          if (c.id == widget.initialPartyId) {
            selC = c;
            break;
          }
        }
      } else {
        for (final s in supps) {
          if (s.id == widget.initialPartyId) {
            selS = s;
            break;
          }
        }
      }
    }

    final number = _isCredit
        ? await repo.peekNextCreditNoteNumber(bizId)
        : await repo.peekNextDebitNoteNumber(bizId);

    if (!mounted) return;
    setState(() {
      _business = biz;
      _customers = custs;
      _suppliers = supps;
      _products = prods;
      _selectedCustomer = selC;
      _selectedSupplier = selS;
      _noteNumber = number;
      _loading = false;
    });
  }

  Future<void> _switchPartyType(String newType) async {
    if (newType == _partyType) return;
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;

    final repo = Repository.instance;
    final number = newType == 'customer'
        ? await repo.peekNextCreditNoteNumber(bizId)
        : await repo.peekNextDebitNoteNumber(bizId);

    setState(() {
      _partyType = newType;
      _noteNumber = number;
      _selectedReason = _isCredit ? _creditReasons.first : _debitReasons.first;
      _selectedCustomer = null;
      _selectedSupplier = null;
    });
  }

  void _pickParty() {
    if (_isCredit) {
      _pickCustomer();
    } else {
      _pickSupplier();
    }
  }

  void _pickCustomer() {
    final custs = _customers ?? [];
    String query = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = custs.where((c) {
            if (query.isEmpty) return true;
            final q = query.toLowerCase();
            return c.name.toLowerCase().contains(q) || (c.phone?.contains(q) ?? false);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Customer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StitchColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text('Add New Customer', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () async {
                        final bizId = context.read<Session>().businessId!;
                        Navigator.pop(ctx);
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => CustomerFormSheet(
                            businessId: bizId,
                            onSaved: _initData,
                            onSavedCustomer: (newCust) {
                              setState(() => _selectedCustomer = newCust);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: inputDecoration('Search customer by name or phone...', hint: 'Search...'),
                    onChanged: (v) => setSheetState(() => query = v.trim()),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No customers found', style: TextStyle(color: StitchColors.textSecondary)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final c = filtered[index];
                              return ListTile(
                                leading: InitialsAvatar(c.name, size: 36),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                subtitle: Text(
                                  c.phone != null && c.phone!.isNotEmpty ? c.phone! : (c.gstin ?? 'No phone'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: _selectedCustomer?.id == c.id
                                    ? const Icon(Icons.check_circle_rounded, color: StitchColors.primary)
                                    : null,
                                onTap: () {
                                  setState(() => _selectedCustomer = c);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _pickSupplier() {
    final supps = _suppliers ?? [];
    String query = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = supps.where((s) {
            if (query.isEmpty) return true;
            final q = query.toLowerCase();
            return s.name.toLowerCase().contains(q) || (s.phone?.contains(q) ?? false);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Supplier',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5E35B1),
                        side: const BorderSide(color: Color(0xFFD1C4E9)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text('Add New Supplier', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () async {
                        final bizId = context.read<Session>().businessId!;
                        Navigator.pop(ctx);
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => SupplierFormSheet(
                            businessId: bizId,
                            onSaved: _initData,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: inputDecoration('Search supplier by name or phone...', hint: 'Search...'),
                    onChanged: (v) => setSheetState(() => query = v.trim()),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No suppliers found', style: TextStyle(color: StitchColors.textSecondary)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final s = filtered[index];
                              return ListTile(
                                leading: InitialsAvatar(s.name, size: 36),
                                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                subtitle: Text(
                                  s.phone != null && s.phone!.isNotEmpty ? s.phone! : (s.gstin ?? 'No phone'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: _selectedSupplier?.id == s.id
                                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF5E35B1))
                                    : null,
                                onTap: () {
                                  setState(() => _selectedSupplier = s);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openProductPicker() {
    final prods = _products ?? [];
    if (prods.isEmpty) {
      showAppMessage(context, 'No products available. Add items in inventory first.', error: true);
      return;
    }

    final initialMap = <int, double>{};
    for (final l in _lines) {
      if (l.productId != null) {
        initialMap[l.productId!] = l.qty;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultiProductPickerSheet(
        products: prods,
        isPurchase: !_isCredit,
        title: _isCredit ? 'Select Items for Credit Note' : 'Select Items for Debit Note',
        actionLabel: 'Add to Note',
        initialQuantities: initialMap,
        onItemsSelected: (items) {
          setState(() {
            for (final it in items) {
              final existingIdx = _lines.indexWhere((l) => l.productId == it.product.id);
              if (existingIdx >= 0) {
                _lines[existingIdx].qty = it.quantity;
                _lines[existingIdx].price = it.unitPrice;
              } else {
                _lines.add(_NoteLine(
                  productId: it.product.id,
                  name: it.product.name,
                  hsn: it.product.hsn,
                  unit: it.product.unit,
                  qty: it.quantity,
                  price: it.unitPrice,
                  gstRate: it.product.gstRate,
                ));
              }
            }
          });
        },
      ),
    );
  }

  void _editLine(int index) {
    final line = _lines[index];
    final qtyCtrl = TextEditingController(text: _qty(line.qty));
    final priceCtrl = TextEditingController(text: (line.price / 100).toStringAsFixed(2));
    int selectedGst = line.gstRate;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final qVal = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
          final pVal = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
          final subtotalP = (pVal * 100 * qVal).round();
          final taxP = (subtotalP * (selectedGst / 100)).round();
          final totalP = subtotalP + taxP;
          final maxQ = line.maxQty;
          final isExceeding = maxQ != null && qVal > maxQ;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            line.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (line.unit != null)
                          Text(
                            'Unit: ${line.unit}',
                            style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                          ),
                      ],
                    ),
                    if (maxQ != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Original Billed Quantity: ${_qty(maxQ)}',
                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: inputDecoration(
                              'Return Quantity',
                              hint: '1',
                            ).copyWith(
                              errorText: isExceeding ? 'Exceeds billed qty (${_qty(maxQ)})' : null,
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: inputDecoration('Unit Rate (₹)', hint: '0.00'),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('GST Rate (%)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [0, 5, 12, 18, 28].map((rate) {
                        final isSel = selectedGst == rate;
                        final activeColor = _isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1);
                        return ChoiceChip(
                          label: Text('$rate%'),
                          selected: isSel,
                          selectedColor: activeColor.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: isSel ? activeColor : StitchColors.textPrimary,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (val) {
                            if (val) setSheetState(() => selectedGst = rate);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: StitchColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Taxable: ${formatPaise(subtotalP)}', style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                              Text('Tax ($selectedGst%): ${formatPaise(taxP)}', style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                            ],
                          ),
                          Text(
                            formatPaise(totalP),
                            style: moneyStyle(fontSize: 16, weight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final q = double.tryParse(qtyCtrl.text.trim());
                          final p = double.tryParse(priceCtrl.text.trim());
                          if (q == null || q <= 0 || p == null || p < 0) return;
                          setState(() {
                            line.qty = q;
                            line.price = (p * 100).round();
                            line.gstRate = selectedGst;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply Changes'),
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
  }

  String _qty(double q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_noteDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _noteDate = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _saveNote() async {
    final activeLines = _lines.where((l) => l.qty > 0).toList();
    if (activeLines.isEmpty) {
      showAppMessage(context, 'Please add at least one item with quantity > 0', error: true);
      return;
    }

    final bizId = context.read<Session>().businessId;
    if (bizId == null) {
      showAppMessage(context, 'No active business', error: true);
      return;
    }

    final partyId = _isCredit ? _selectedCustomer?.id : _selectedSupplier?.id;
    final partyName = _isCredit
        ? (_selectedCustomer?.name ?? (widget.fromInvoice?.customerName ?? 'Walk-in Customer'))
        : (_selectedSupplier?.name ?? (widget.fromPurchase?.supplierName ?? 'Direct Vendor'));

    final subtotalPaise = activeLines.fold<int>(0, (sum, l) => sum + l.subtotalPaise);
    final taxablePaise = subtotalPaise;
    final taxPaise = activeLines.fold<int>(0, (sum, l) => sum + l.taxPaise);
    final totalPaise = taxablePaise + taxPaise;

    final reason = _selectedReason == 'Other' && _customReasonController.text.trim().isNotEmpty
        ? _customReasonController.text.trim()
        : _selectedReason;

    final refInvoiceId = widget.fromInvoice?.id ?? widget.fromPurchase?.id;

    setState(() => _saving = true);
    try {
      final repo = Repository.instance;
      final finalNumber = _noteNumber ??
          (_isCredit
              ? await repo.nextCreditNoteNumber(bizId)
              : await repo.nextDebitNoteNumber(bizId));

      final ret = TransactionReturn(
        businessId: bizId,
        number: finalNumber,
        invoiceId: refInvoiceId,
        partyId: partyId,
        partyName: partyName,
        partyType: _partyType,
        date: _noteDate,
        subtotal: subtotalPaise,
        taxable: taxablePaise,
        tax: taxPaise,
        total: totalPaise,
        reason: reason,
        status: 'Finalized',
        lines: activeLines
            .map((l) => InvoiceLine(
                  productId: l.productId,
                  name: l.name,
                  hsn: l.hsn,
                  unit: l.unit,
                  quantity: l.qty,
                  price: l.price,
                  gstRate: l.gstRate,
                  taxable: l.subtotalPaise,
                  tax: l.taxPaise,
                ))
            .toList(),
      );

      final noteId = await repo.finalizeReturn(ret);

      if (mounted) {
        final label = _isCredit ? 'Credit Note' : 'Debit Note';
        showAppMessage(context, '$label $finalNumber saved successfully ✓');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NoteDetailScreen(noteId: noteId, autoPreview: true),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Error saving note: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final activeLines = _lines.where((l) => l.qty > 0).toList();
    final subtotalPaise = activeLines.fold<int>(0, (sum, l) => sum + l.subtotalPaise);
    final taxablePaise = subtotalPaise;
    final totalTaxPaise = activeLines.fold<int>(0, (sum, l) => sum + l.taxPaise);
    final grandTotalPaise = taxablePaise + totalTaxPaise;

    // Slabs breakdown
    final Map<int, int> taxByRate = {};
    for (final l in activeLines) {
      if (l.gstRate > 0) {
        taxByRate[l.gstRate] = (taxByRate[l.gstRate] ?? 0) + l.taxPaise;
      }
    }

    final partyState = _isCredit ? _selectedCustomer?.state : _selectedSupplier?.state;
    final bizState = _business?.state;
    final isInterState = partyState != null &&
        partyState.trim().isNotEmpty &&
        bizState != null &&
        bizState.trim().isNotEmpty &&
        partyState.trim().toLowerCase() != bizState.trim().toLowerCase();

    final cgstPaise = isInterState ? 0 : (totalTaxPaise ~/ 2);
    final sgstPaise = isInterState ? 0 : (totalTaxPaise - cgstPaise);
    final igstPaise = isInterState ? totalTaxPaise : 0;

    final themeColor = _isCredit ? const Color(0xFF00897B) : const Color(0xFF5E35B1);
    final noteTitle = _isCredit ? 'Credit Note' : 'Debit Note';

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: Text(
          widget.fromInvoice != null
              ? 'New Credit Note (INV #${widget.fromInvoice!.number})'
              : (widget.fromPurchase != null
                  ? 'New Debit Note (PUR #${widget.fromPurchase!.number})'
                  : 'New $noteTitle'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // If standalone, show SegmentedButton for Credit vs Debit Note
          if (!_isLinked)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'customer',
                      label: Text('Credit Note (Customer)', style: TextStyle(fontWeight: FontWeight.w700)),
                      icon: Icon(Icons.assignment_return_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'supplier',
                      label: Text('Debit Note (Supplier)', style: TextStyle(fontWeight: FontWeight.w700)),
                      icon: Icon(Icons.assignment_returned_outlined, size: 16),
                    ),
                  ],
                  selected: {_partyType},
                  onSelectionChanged: (s) => _switchPartyType(s.first),
                ),
              ),
            ),
          if (!_isLinked) const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Note Meta Card (Number & Date)
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final ctrl = TextEditingController(text: _noteNumber ?? '');
                            final res = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Edit $noteTitle Number'),
                                content: TextField(controller: ctrl, autofocus: true),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                                ],
                              ),
                            );
                            if (res != null && res.isNotEmpty) {
                              setState(() => _noteNumber = res);
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$noteTitle No.', style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(_noteNumber ?? '---', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit_outlined, size: 13, color: StitchColors.textSecondary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 32, color: Colors.grey.shade200),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Date', style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(displayDate(_noteDate), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.calendar_today_outlined, size: 13, color: StitchColors.textSecondary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Party Card
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isCredit ? 'CUSTOMER' : 'SUPPLIER',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: StitchColors.textSecondary, letterSpacing: 0.5),
                          ),
                          if (!_isLinked)
                            InkWell(
                              onTap: _pickParty,
                              child: Text(
                                (_isCredit ? _selectedCustomer : _selectedSupplier) != null ? 'Change' : '+ Select',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: themeColor),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _isLinked ? null : _pickParty,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isCredit ? Icons.person_outline_rounded : Icons.local_shipping_outlined,
                                color: themeColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (_isCredit
                                            ? (_selectedCustomer?.name ?? (widget.fromInvoice?.customerName ?? 'Select Customer'))
                                            : (_selectedSupplier?.name ?? (widget.fromPurchase?.supplierName ?? 'Select Supplier'))),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (_isCredit
                                        ? (_selectedCustomer?.phone ?? 'Tap to choose party')
                                        : (_selectedSupplier?.phone ?? (widget.fromPurchase?.supplierPhone ?? 'Tap to choose party'))),
                                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isLinked)
                              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Reason Card
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'REASON FOR NOTE',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: StitchColors.textSecondary, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedReason,
                        decoration: inputDecoration('Select Reason'),
                        items: (_isCredit ? _creditReasons : _debitReasons)
                            .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedReason = val);
                        },
                      ),
                      if (_selectedReason == 'Other') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _customReasonController,
                          decoration: inputDecoration('Enter specific reason'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Items Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'RETURNED ITEMS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: StitchColors.textSecondary, letterSpacing: 0.5),
                    ),
                    if (!_isLinked)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: themeColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        onPressed: _openProductPicker,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_lines.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text('No items added yet', style: TextStyle(fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openProductPicker,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Items'),
                        ),
                      ],
                    ),
                  )
                else
                  ..._lines.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => _editLine(idx),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.gstRate > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('${item.gstRate}% GST', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_qty(item.qty)} ${item.unit ?? 'pcs'} × ${formatPaise(item.price)}',
                                      style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                                    ),
                                    if (item.maxQty != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Billed: ${_qty(item.maxQty!)}',
                                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatPaise(item.totalPaise),
                                    style: moneyStyle(fontSize: 14, weight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('Tap to edit', style: TextStyle(fontSize: 10.5, color: StitchColors.primary)),
                                ],
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    if (_isLinked) {
                                      item.qty = 0; // set qty to 0 for linked items
                                    } else {
                                      _lines.removeAt(idx);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 14),

                // BillBook-Grade Purchase Tax Breakdown Card (Feature 1 & Feature 4)
                if (activeLines.isNotEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TAX BREAKDOWN',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: StitchColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isInterState ? const Color(0xFF673AB7) : const Color(0xFF00897B))
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isInterState ? 'INTER-STATE (IGST)' : 'INTRA-STATE (CGST + SGST)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isInterState ? const Color(0xFF673AB7) : const Color(0xFF00897B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        _taxRow('Subtotal', formatPaise(subtotalPaise)),
                        const SizedBox(height: 6),
                        _taxRow('Taxable Amount', formatPaise(taxablePaise)),
                        if (taxByRate.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          ...taxByRate.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('GST @ ${e.key}% slab', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                                  Text(formatPaise(e.value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 6),
                        if (isInterState) ...[
                          _taxRow('IGST', formatPaise(igstPaise)),
                        ] else ...[
                          _taxRow('CGST', formatPaise(cgstPaise)),
                          const SizedBox(height: 4),
                          _taxRow('SGST', formatPaise(sgstPaise)),
                        ],
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$noteTitle Total',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              formatPaise(grandTotalPaise),
                              style: moneyStyle(fontSize: 18, weight: FontWeight.w900, color: themeColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Action Bar
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
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${activeLines.length} items',
                          style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          formatPaise(grandTotalPaise),
                          style: moneyStyle(fontSize: 18, weight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _saving ? null : _saveNote,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Save $noteTitle', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taxRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: StitchColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
