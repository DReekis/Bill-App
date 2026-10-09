import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/billing_engine.dart';
import '../../core/dates.dart';
import '../../core/gst_service.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../inventory/product_form.dart';
import '../inventory/multi_product_picker_sheet.dart';
import 'barcode_scanner_screen.dart';
import '../../core/subscription_service.dart';
import '../subscription/upgrade_paywall_sheet.dart';

class InvoiceBuilderScreen extends StatefulWidget {
  const InvoiceBuilderScreen({super.key, this.customerId, this.existingInvoiceId});
  final int? customerId;
  final int? existingInvoiceId;
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
    this.unit,
    this.batch,
    this.serial,
  });
  Product product;
  double qty;
  int price;
  double discountPercent;
  int gstRate;
  bool taxIncluded;
  String? unit;
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
  String? invoiceNumber;
  String invoiceDate = todayIso();
  int? initialAmountPaid;
  String? initialPaymentMode;
  String? existingNotes;

  // Shipping Address ("Ship To")
  bool shipToDifferent = false;
  final shipToNameController = TextEditingController();
  final shipToAddressController = TextEditingController();
  String? shipToState;
  final shipToPincodeController = TextEditingController();

  // Transport & Statutory Metadata
  String? placeOfSupply;
  bool manualPosOverride = false;
  final vehicleNoController = TextEditingController();
  final ewayBillNoController = TextEditingController();
  final lrRrNoController = TextEditingController();
  final poNumberController = TextEditingController();
  String? poDate;

  // Tax Mode & Reverse Charge
  bool reverseCharge = false;
  bool? manualIntraStateOverride;

  @override
  void dispose() {
    shipToNameController.dispose();
    shipToAddressController.dispose();
    shipToPincodeController.dispose();
    vehicleNoController.dispose();
    ewayBillNoController.dispose();
    lrRrNoController.dispose();
    poNumberController.dispose();
    super.dispose();
  }

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
            customerState: _clean(placeOfSupply ?? (shipToDifferent ? shipToState : customerState)),
            intraStateOverride: manualIntraStateOverride ?? intraStateOverride,
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

    if (widget.existingInvoiceId != null) {
      final inv = await repo.invoice(businessId, widget.existingInvoiceId!);
      if (inv != null && mounted) {
        Customer? matchedCust;
        if (inv.customerId != null && custs.isNotEmpty) {
          for (final c in custs) {
            if (c.id == inv.customerId) {
              matchedCust = c;
              break;
            }
          }
        }

        final existingLines = <_LineEdit>[];
        for (final l in inv.lines) {
          Product? prod;
          if (l.productId != null && prods.isNotEmpty) {
            for (final p in prods) {
              if (p.id == l.productId) {
                prod = p;
                break;
              }
            }
          }
          prod ??= Product(
            id: l.productId,
            name: l.name,
            hsn: l.hsn,
            salePrice: l.price,
            gstRate: l.gstRate,
            taxIncluded: false,
          );

          existingLines.add(_LineEdit(
            product: prod,
            qty: l.quantity,
            price: l.price,
            discountPercent: l.discountPercent,
            gstRate: l.gstRate,
            taxIncluded: false,
            unit: l.unit ?? prod.unit,
            batch: l.batchNumber,
            serial: l.serialNumber,
          ));
        }

        setState(() {
          invoiceNumber = inv.number;
          invoiceDate = inv.date;
          dueDate = inv.dueDate;
          customerId = inv.customerId;
          customerName = inv.customerName;
          customerState = _clean(matchedCust?.state);
          shipToNameController.text = inv.shipToName ?? '';
          shipToAddressController.text = inv.shipToAddress ?? '';
          shipToState = inv.shipToState;
          shipToPincodeController.text = inv.shipToPincode ?? '';
          shipToDifferent = (inv.shipToName != null && inv.shipToName!.isNotEmpty) ||
              (inv.shipToAddress != null && inv.shipToAddress!.isNotEmpty);
          placeOfSupply = inv.placeOfSupply;
          manualPosOverride = inv.placeOfSupply != null;
          vehicleNoController.text = inv.vehicleNumber ?? '';
          ewayBillNoController.text = inv.ewayBillNumber ?? '';
          lrRrNoController.text = inv.lrRrNumber ?? '';
          poNumberController.text = inv.poNumber ?? '';
          poDate = inv.poDate;
          reverseCharge = inv.reverseCharge;
          invoiceDiscountType = inv.discountType ?? (inv.discountRate > 0 ? 'percent' : 'flat');
          invoiceDiscountValue = inv.discountRate > 0 ? inv.discountRate : (inv.discount / 100.0);
          initialAmountPaid = inv.amountPaid;
          initialPaymentMode = inv.paymentMode;
          existingNotes = inv.notes;
          lines = existingLines;
        });
        return;
      }
    }

    if (widget.existingInvoiceId == null && (invoiceNumber == null || invoiceNumber!.isEmpty)) {
      if (biz != null) {
        final nextNum = await repo.peekNextInvoiceNumber(businessId, biz.invoicePrefix);
        setState(() {
          invoiceNumber = nextNum;
        });
      }
    }

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

  Future<void> _editInvoiceNumber() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final controller = TextEditingController(text: invoiceNumber ?? '');
    String? validationError;

    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: StitchColors.primary),
              SizedBox(width: 8),
              Text('Edit Invoice Number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a custom invoice number for this bill:', style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: inputDecoration('Invoice Number', hint: 'e.g. INV-0042 or BILL/24/01').copyWith(
                  errorText: validationError,
                ),
                onChanged: (val) async {
                  if (val.trim().isEmpty) {
                    setDialogState(() => validationError = 'Cannot be empty');
                    return;
                  }
                  final available = await Repository.instance.isInvoiceNumberAvailable(
                    businessId,
                    val.trim(),
                    excludeInvoiceId: widget.existingInvoiceId,
                  );
                  setDialogState(() {
                    validationError = available ? null : 'Invoice number already exists!';
                  });
                },
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
                if (text.isEmpty || validationError != null) return;
                Navigator.pop(ctx, text);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (updated != null && updated.isNotEmpty && mounted) {
      setState(() => invoiceNumber = updated);
      _saveDraft();
    }
  }

  static String _draftKey(int bizId) => 'draft_invoice_$bizId';

  Future<void> _saveDraft() async {
    if (widget.existingInvoiceId != null) return;
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
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate,
      'shipToDifferent': shipToDifferent,
      'shipToName': shipToNameController.text,
      'shipToAddress': shipToAddressController.text,
      'shipToState': shipToState,
      'shipToPincode': shipToPincodeController.text,
      'placeOfSupply': placeOfSupply,
      'manualPosOverride': manualPosOverride,
      'vehicleNumber': vehicleNoController.text,
      'ewayBillNumber': ewayBillNoController.text,
      'lrRrNumber': lrRrNoController.text,
      'poNumber': poNumberController.text,
      'poDate': poDate,
      'reverseCharge': reverseCharge,
      'lines': lines.map((l) => {
        'productId': l.product.id,
        'productName': l.product.name,
        'qty': l.qty,
        'price': l.price,
        'discountPercent': l.discountPercent,
        'gstRate': l.gstRate,
        'taxIncluded': l.taxIncluded,
        'unit': l.unit ?? l.product.unit,
        'batch': l.batch,
        'serial': l.serial,
      }).toList(),
    };
    await prefs.setString(_draftKey(businessId), jsonEncode(data));
  }

  Future<void> _checkDraft(int bizId) async {
    if (widget.existingInvoiceId != null || widget.customerId != null || lines.isNotEmpty) return;
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
            unit: item['unit'] as String?,
            batch: item['batch'] as String?,
            serial: item['serial'] as String?,
          ));
        }

        String? resolvedDraftNum;
        if (decoded['invoiceNumber'] != null) {
          final draftNum = decoded['invoiceNumber'] as String;
          final isAvail = await Repository.instance.isInvoiceNumberAvailable(bizId, draftNum);
          if (isAvail) {
            resolvedDraftNum = draftNum;
          } else {
            resolvedDraftNum = await Repository.instance.peekNextInvoiceNumber(bizId, business?.invoicePrefix ?? 'INV');
          }
        }

        setState(() {
          lines = restored;
          customerId = decoded['customerId'] as int?;
          customerName = decoded['customerName'] as String?;
          customerState = decoded['customerState'] as String?;
          dueDate = decoded['dueDate'] as String?;
          invoiceDiscountType = (decoded['invoiceDiscountType'] as String?) ?? 'percent';
          invoiceDiscountValue = (decoded['invoiceDiscountValue'] as num?)?.toDouble() ?? 0.0;
          if (resolvedDraftNum != null) {
            invoiceNumber = resolvedDraftNum;
          }
          if (decoded['invoiceDate'] != null) {
            invoiceDate = decoded['invoiceDate'] as String;
          }
          shipToDifferent = decoded['shipToDifferent'] == true;
          shipToNameController.text = (decoded['shipToName'] as String?) ?? '';
          shipToAddressController.text = (decoded['shipToAddress'] as String?) ?? '';
          shipToState = decoded['shipToState'] as String?;
          shipToPincodeController.text = (decoded['shipToPincode'] as String?) ?? '';
          placeOfSupply = decoded['placeOfSupply'] as String?;
          manualPosOverride = decoded['manualPosOverride'] == true;
          vehicleNoController.text = (decoded['vehicleNumber'] as String?) ?? '';
          ewayBillNoController.text = (decoded['ewayBillNumber'] as String?) ?? '';
          lrRrNoController.text = (decoded['lrRrNumber'] as String?) ?? '';
          poNumberController.text = (decoded['poNumber'] as String?) ?? '';
          poDate = decoded['poDate'] as String?;
          reverseCharge = decoded['reverseCharge'] == true;
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
    if (mounted) {
      setState(() {
        products = prods;
        for (final line in lines) {
          if (line.product.id != null) {
            final match = prods.cast<Product?>().firstWhere(
              (p) => p?.id == line.product.id,
              orElse: () => null,
            );
            if (match != null) {
              line.product = match;
            }
          }
        }
      });
    }
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
      if (!manualPosOverride) {
        placeOfSupply = shipToDifferent ? (shipToState ?? customerState) : customerState;
      }
      if (c.paymentTermsDays > 0) {
        dueDate = isoDate(DateTime.now().add(Duration(days: c.paymentTermsDays)));
      } else {
        dueDate = null;
      }
    });
    _saveDraft();
  }

  void _onToggleShipTo(bool val) {
    setState(() {
      shipToDifferent = val;
      if (!manualPosOverride) {
        placeOfSupply = shipToDifferent ? (shipToState ?? customerState) : customerState;
      }
    });
    _saveDraft();
  }

  void _onShipToStateChanged(String? newState) {
    setState(() {
      shipToState = newState;
      if (shipToDifferent && !manualPosOverride && newState != null) {
        placeOfSupply = newState;
      }
    });
    _saveDraft();
  }

  void _copyFromBillTo() {
    Customer? c;
    if (customerId != null && customers != null) {
      for (final cust in customers!) {
        if (cust.id == customerId) {
          c = cust;
          break;
        }
      }
    }
    setState(() {
      shipToNameController.text = customerName ?? '';
      shipToAddressController.text = c?.billingAddress ?? '';
      shipToState = c?.state ?? customerState;
      shipToPincodeController.text = c?.pin ?? '';
      if (!manualPosOverride && shipToState != null) {
        placeOfSupply = shipToState;
      }
    });
    showAppMessage(context, 'Copied billing details to Ship To');
    _saveDraft();
  }

  void _pickCustomer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final all = customers ?? const <Customer>[];
            final businessId = context.read<Session>().businessId!;
            final q = searchQuery.trim().toLowerCase();

            final filtered = q.isEmpty
                ? all
                : all.where((c) {
                    final name = c.name.toLowerCase();
                    final phone = (c.phone ?? '').toLowerCase();
                    final gstin = (c.gstin ?? '').toLowerCase();
                    return name.contains(q) || phone.contains(q) || gstin.contains(q);
                  }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select Customer',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await showModalBottomSheet<void>(
                              context: this.context,
                              isScrollControlled: true,
                              builder: (ctx) => CustomerFormSheet(
                                businessId: businessId,
                                onSaved: _load,
                                onSavedCustomer: (newCust) {
                                  _selectCustomer(newCust);
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
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Search customer by name or phone...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    setModalState(() => searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
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
                              title: const Text('Walk-in customer', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Cash sale / unregistered customer', style: TextStyle(fontSize: 12)),
                              onTap: () {
                                setState(() {
                                  customerId = null;
                                  customerName = null;
                                  customerState = null;
                                });
                                Navigator.pop(context);
                              },
                            ),
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                              child: Column(
                                children: [
                                  Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No customer found matching "$searchQuery"',
                                    style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await showModalBottomSheet<void>(
                                        context: this.context,
                                        isScrollControlled: true,
                                        builder: (ctx) => CustomerFormSheet(
                                          businessId: businessId,
                                          onSaved: _load,
                                          onSavedCustomer: (newCust) {
                                            _selectCustomer(newCust);
                                          },
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.person_add_rounded, size: 18),
                                    label: Text('Create "$searchQuery" as new customer'),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...filtered.map((c) => ListTile(
                                  leading: InitialsAvatar(c.name, size: 38),
                                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    [c.phone, if (c.gstin != null && c.gstin!.isNotEmpty) 'GST: ${c.gstin}']
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join(' • '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () {
                                    _selectCustomer(c);
                                    Navigator.pop(context);
                                  },
                                )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

  Future<void> _addItem() async {
    await _refreshProducts();
    if (!mounted) return;
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
        products: products ?? const [],
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
                  discountPercent: 0,
                  gstRate: item.product.gstRate,
                  taxIncluded: item.product.taxIncluded,
                ));
              }
            }
          });
          _saveDraft();
          showAppMessage(
            context,
            selectedItems.length == 1
                ? 'Added ${selectedItems.first.product.name} to bill'
                : 'Added ${selectedItems.length} items to bill',
          );
        },
        onAddNew: () async {
          Navigator.pop(context);
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => ProductFormSheet(
              onSaved: _refreshProducts,
              onSavedProduct: (p) {
                setState(() {
                  lines.add(_LineEdit(
                    product: p,
                    qty: 1,
                    price: p.salePrice,
                    discountPercent: 0,
                    gstRate: p.gstRate,
                    taxIncluded: p.taxIncluded,
                  ));
                });
                _saveDraft();
              },
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
        showAppMessage(context, 'Updated ${updated.product.name}');
      }),
    );
  }

  void _removeLine(_LineEdit line) {
    setState(() => lines.remove(line));
    _saveDraft();
  }

  Future<void> _addCharge() async {
    final nameController = TextEditingController(text: 'Delivery / Shipping');
    final amountController = TextEditingController();
    final hsnController = TextEditingController(text: '9965');
    int gstRate = 18;
    String selectedPreset = 'Delivery / Shipping';
    String? amountError;

    final presets = [
      {'name': 'Delivery / Shipping', 'hsn': '9965', 'gst': 18},
      {'name': 'TCS (Tax Collected at Source)', 'hsn': '9999', 'gst': 0},
      {'name': 'Packaging & Forwarding', 'hsn': '9968', 'gst': 18},
      {'name': 'Installation / Labour', 'hsn': '9987', 'gst': 18},
      {'name': 'Handling Fee', 'hsn': '9997', 'gst': 18},
      {'name': 'Custom Charge', 'hsn': '', 'gst': 0},
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                        child: const Icon(Icons.toll_outlined, color: StitchColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Add Charge / TCS / Service',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Quick Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final isSelected = selectedPreset == p['name'];
                      return ChoiceChip(
                        label: Text(p['name'] as String, style: TextStyle(fontSize: 11.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            setSheetState(() {
                              selectedPreset = p['name'] as String;
                              if (selectedPreset == 'Custom Charge') {
                                nameController.text = '';
                                hsnController.text = '';
                                gstRate = 0;
                              } else {
                                nameController.text = p['name'] as String;
                                hsnController.text = p['hsn'] as String;
                                gstRate = p['gst'] as int;
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: inputDecoration('Charge / Description', hint: 'e.g. Delivery Charge, TCS @ 0.1%'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          autofocus: true,
                          onChanged: (_) {
                            if (amountError != null) {
                              setSheetState(() => amountError = null);
                            }
                          },
                          decoration: inputDecoration('Amount (₹)', hint: '0.00').copyWith(
                            errorText: amountError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('charge-gst-$gstRate'),
                          initialValue: gstRate,
                          decoration: inputDecoration('GST %'),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('0% (Exempt/TCS)')),
                            DropdownMenuItem(value: 5, child: Text('5%')),
                            DropdownMenuItem(value: 12, child: Text('12%')),
                            DropdownMenuItem(value: 18, child: Text('18%')),
                            DropdownMenuItem(value: 28, child: Text('28%')),
                          ],
                          onChanged: (v) => setSheetState(() => gstRate = v ?? 0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: hsnController,
                    decoration: inputDecoration('HSN / SAC Code (optional)', hint: 'e.g. 9965'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final rawName = nameController.text.trim();
                            final effectiveName = rawName.isNotEmpty
                                ? rawName
                                : (selectedPreset != 'Custom Charge' ? selectedPreset : 'Extra Charge');
                            final cleanAmtStr = amountController.text
                                .replaceAll('₹', '')
                                .replaceAll(',', '')
                                .replaceAll(' ', '')
                                .trim();
                            final amt = double.tryParse(cleanAmtStr);
                            if (amt == null || amt <= 0) {
                              setSheetState(() {
                                amountError = 'Enter a valid amount';
                              });
                              return;
                            }
                            final pricePaise = (amt * 100).round();
                            setState(() {
                              lines.add(_LineEdit(
                                product: Product(
                                  id: null,
                                  name: effectiveName,
                                  hsn: hsnController.text.trim().isEmpty ? null : hsnController.text.trim(),
                                  salePrice: pricePaise,
                                  gstRate: gstRate,
                                  taxIncluded: false,
                                ),
                                qty: 1,
                                price: pricePaise,
                                discountPercent: 0,
                                gstRate: gstRate,
                                taxIncluded: false,
                              ));
                            });
                            _saveDraft();
                            Navigator.pop(ctx);
                            showAppMessage(context, 'Added $effectiveName (${formatPaise(pricePaise)})');
                          },
                          child: const Text('Add Charge'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkout() async {
    final q = quote;
    final biz = business;
    if (q == null || biz == null) return;
    String invoiceDate = this.invoiceDate;
    String? checkoutDueDate = dueDate;
    String gstType = q.intraState ? 'intra' : 'inter';
    String? mode = initialPaymentMode ?? 'Cash';
    final initialPaid = initialAmountPaid;
    final paidController = TextEditingController(
      text: initialPaid != null && initialPaid > 0
          ? (initialPaid / 100.0 == (initialPaid / 100.0).roundToDouble()
              ? (initialPaid ~/ 100).toString()
              : (initialPaid / 100.0).toStringAsFixed(2))
          : '',
    );
    final notesController = TextEditingController(text: existingNotes ?? (biz.termsSales ?? ''));
    final isEditing = widget.existingInvoiceId != null;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isEditing ? 'Update invoice — ${q.total}' : 'Save invoice — ${q.total}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    InkWell(
                      onTap: () async {
                        Navigator.pop(context);
                        await _editInvoiceNumber();
                        _checkout();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: StitchColors.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(invoiceNumber ?? 'INV-0001',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: StitchColors.primary)),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_rounded, size: 12, color: StitchColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AppAmountField(
                  controller: paidController,
                  label: 'Amount paid now',
                  suffix: '0 for credit / unpaid',
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
                    label: isEditing ? 'Save Changes' : 'Save & finalize',
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
      var number = (invoiceNumber != null && invoiceNumber!.trim().isNotEmpty)
          ? invoiceNumber!.trim()
          : (widget.existingInvoiceId != null
              ? 'INV-0001'
              : await Repository.instance.nextInvoiceNumber(businessId, biz.invoicePrefix));

      if (widget.existingInvoiceId == null) {
        final currentCount = await Repository.instance.getInvoicesCount(businessId);
        if (!SubscriptionService.instance.canCreateSalesInvoice(currentCount)) {
          setState(() => saving = false);
          if (mounted) {
            UpgradePaywallSheet.show(
              context,
              featureName: 'Free Plan Invoice Limit Reached',
              description:
                  'You have created $currentCount sales invoices. The Free tier includes 10 sales invoices per year.\n\nUpgrade to Starter or Silver for unlimited billing.',
              requiredTier: SubscriptionTier.starter,
              bulletPoints: const [
                'Unlimited Sales & Purchase Invoices',
                'Sales & Purchase Returns + Quotes',
                '500 Customers & 1,000 Items Catalog',
              ],
            );
          }
          return;
        }

        final isAvail = await Repository.instance.isInvoiceNumberAvailable(businessId, number);
        if (!isAvail) {
          final freshNumber = await Repository.instance.peekNextInvoiceNumber(businessId, biz.invoicePrefix);
          number = freshNumber;
          if (mounted) {
            setState(() => invoiceNumber = freshNumber);
          }
        }
      }
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
          unit: l.unit ?? l.product.unit,
          batchNumber: l.batch,
          serialNumber: l.serial,
        ));
      }
      final amountPaid = _toPaise(paidController.text);
      final effectivePos = placeOfSupply ?? (shipToDifferent ? shipToState : customerState);

      if (widget.existingInvoiceId != null) {
        await Repository.instance.updateSale(
          businessId: businessId,
          invoiceId: widget.existingInvoiceId!,
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
          shipToName: shipToDifferent ? shipToNameController.text.trim() : null,
          shipToAddress: shipToDifferent ? shipToAddressController.text.trim() : null,
          shipToState: shipToDifferent ? shipToState : null,
          shipToPincode: shipToDifferent ? shipToPincodeController.text.trim() : null,
          placeOfSupply: effectivePos,
          poNumber: poNumberController.text.trim().isEmpty ? null : poNumberController.text.trim(),
          poDate: poDate,
          vehicleNumber: vehicleNoController.text.trim().isEmpty ? null : vehicleNoController.text.trim(),
          ewayBillNumber: ewayBillNoController.text.trim().isEmpty ? null : ewayBillNoController.text.trim(),
          lrRrNumber: lrRrNoController.text.trim().isEmpty ? null : lrRrNoController.text.trim(),
          reverseCharge: reverseCharge,
        );

        if (mounted) {
          showAppMessage(context, 'Invoice $number updated');
          Navigator.of(context).pop(true);
        }
      } else {
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
          shipToName: shipToDifferent ? shipToNameController.text.trim() : null,
          shipToAddress: shipToDifferent ? shipToAddressController.text.trim() : null,
          shipToState: shipToDifferent ? shipToState : null,
          shipToPincode: shipToDifferent ? shipToPincodeController.text.trim() : null,
          placeOfSupply: effectivePos,
          poNumber: poNumberController.text.trim().isEmpty ? null : poNumberController.text.trim(),
          poDate: poDate,
          vehicleNumber: vehicleNoController.text.trim().isEmpty ? null : vehicleNoController.text.trim(),
          ewayBillNumber: ewayBillNoController.text.trim().isEmpty ? null : ewayBillNoController.text.trim(),
          lrRrNumber: lrRrNoController.text.trim().isEmpty ? null : lrRrNoController.text.trim(),
          reverseCharge: reverseCharge,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_draftKey(businessId));

        if (mounted) {
          showAppMessage(context, '$number saved');
          Navigator.of(context).pop(true);
        }
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

  Widget _buildShipToCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: StitchColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.local_shipping_outlined, size: 18, color: StitchColors.primary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ship to different address', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text('Deliver goods to separate address/consignee', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: shipToDifferent,
                onChanged: _onToggleShipTo,
              ),
            ],
          ),
          if (shipToDifferent) ...[
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Shipping Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                TextButton.icon(
                  onPressed: _copyFromBillTo,
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy from Bill To', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: shipToNameController,
              decoration: inputDecoration('Ship-to Recipient / Firm Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: shipToAddressController,
              maxLines: 2,
              decoration: inputDecoration('Shipping Address'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('ship-to-state-$shipToState'),
                    initialValue: shipToState,
                    decoration: inputDecoration('State'),
                    isDense: true,
                    items: GstService.stateCodes.keys
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: _onShipToStateChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: shipToPincodeController,
                    keyboardType: TextInputType.number,
                    decoration: inputDecoration('PIN Code'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransportAndStatutoryCard() {
    final effectivePos = placeOfSupply ?? (shipToDifferent ? (shipToState ?? customerState) : customerState);
    final hasDetails = vehicleNoController.text.isNotEmpty ||
        ewayBillNoController.text.isNotEmpty ||
        lrRrNoController.text.isNotEmpty ||
        poNumberController.text.isNotEmpty ||
        manualPosOverride;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: StitchColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.receipt_long_outlined, size: 18, color: StitchColors.primary),
          ),
          title: const Text('Transport & PO Details', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          subtitle: Text(
            hasDetails
                ? 'POS: ${effectivePos ?? "Default"}${vehicleNoController.text.isNotEmpty ? " • Veh: ${vehicleNoController.text}" : ""}'
                : 'POS, Vehicle No, E-Way Bill, PO Ref',
            style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Place of Supply (POS)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Override', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                          Switch.adaptive(
                            value: manualPosOverride,
                            onChanged: (v) {
                              setState(() {
                                manualPosOverride = v;
                                if (!v) {
                                  placeOfSupply = shipToDifferent ? (shipToState ?? customerState) : customerState;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    key: ValueKey('pos-$effectivePos-$manualPosOverride'),
                    initialValue: GstService.stateCodes.containsKey(effectivePos) ? effectivePos : null,
                    decoration: inputDecoration(manualPosOverride ? 'Manual Place of Supply' : 'Auto POS (Sec 10 IGST Act)'),
                    isDense: true,
                    items: GstService.stateCodes.keys
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: manualPosOverride
                        ? (v) {
                            setState(() => placeOfSupply = v);
                            _saveDraft();
                          }
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: vehicleNoController,
                          decoration: inputDecoration('Vehicle No.', hint: 'e.g. MH12AB1234'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: ewayBillNoController,
                          keyboardType: TextInputType.number,
                          decoration: inputDecoration('E-Way Bill No.', hint: '12-digit number'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lrRrNoController,
                          decoration: inputDecoration('LR / RR / B/L No.', hint: 'Transport doc #'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: poNumberController,
                          decoration: inputDecoration('PO Number', hint: 'Buyer PO #'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final dt = poDate != null ? dateTimeFor(poDate!) : DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dt,
                        firstDate: DateTime(dt.year - 2),
                        lastDate: DateTime(dt.year + 2),
                      );
                      if (picked != null) {
                        setState(() => poDate = isoDate(picked));
                        _saveDraft();
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_outlined, size: 18, color: StitchColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              poDate != null ? 'PO Date: ${displayDate(poDate!)}' : 'Set Purchase Order Date (Optional)',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: poDate != null ? StitchColors.textPrimary : StitchColors.textSecondary,
                                fontWeight: poDate != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (poDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                setState(() => poDate = null);
                                _saveDraft();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxModeAndRcmCard() {
    final q = quote;
    final isTaxReg = business?.taxRegistered ?? false;
    final isInterState = (q?.igst.paise ?? 0) > 0;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: StitchColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.account_balance_outlined, size: 18, color: StitchColors.primary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reverse Charge (RCM)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('Tax payable by recipient under Sec 9(3)/9(4)', style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: reverseCharge,
                onChanged: (v) {
                  setState(() => reverseCharge = v);
                  _saveDraft();
                },
              ),
            ],
          ),
          if (isTaxReg) ...[
            const Divider(height: 12),
            Row(
              children: [
                const Text('GST Mode: ', style: TextStyle(fontSize: 11.5, color: StitchColors.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isInterState ? const Color(0xFF6366F1) : StitchColors.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    isInterState ? 'Inter-state (IGST)' : 'Intra-state (CGST + SGST)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isInterState ? const Color(0xFF4338CA) : StitchColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  onPressed: () {
                    setState(() {
                      manualIntraStateOverride = !(manualIntraStateOverride ?? !isInterState);
                    });
                  },
                  child: Text(
                    manualIntraStateOverride == null
                        ? 'Override Mode'
                        : (manualIntraStateOverride! ? 'Mode: Intra (Forced)' : 'Mode: Inter (Forced)'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingInvoiceId != null
            ? (invoiceNumber != null ? 'Edit Invoice $invoiceNumber' : 'Edit Invoice')
            : 'New sale'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scanBarcode,
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        // Top Document Meta: Invoice Number & Date
        Row(
          children: [
            Expanded(
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: InkWell(
                  onTap: _editInvoiceNumber,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: StitchColors.primaryContainer,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.tag_rounded, size: 16, color: StitchColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Invoice No.', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                            Text(
                              invoiceNumber ?? 'INV-0001',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StitchColors.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_outlined, size: 14, color: StitchColors.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: InkWell(
                  onTap: () async {
                    final dt = dateTimeFor(invoiceDate);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dt,
                      firstDate: DateTime(dt.year - 2),
                      lastDate: DateTime(dt.year + 2),
                    );
                    if (picked != null) setState(() => invoiceDate = isoDate(picked));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.calendar_today_rounded, size: 16, color: StitchColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Invoice Date', style: TextStyle(fontSize: 10, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
                            Text(
                              displayDate(invoiceDate),
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
        _buildShipToCard(),
        const SizedBox(height: 10),
        _buildTransportAndStatutoryCard(),
        const SizedBox(height: 10),
        _buildTaxModeAndRcmCard(),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Items & Charges', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20, color: StitchColors.primary),
            onPressed: _scanBarcode,
          ),
          TextButton.icon(
            onPressed: _addCharge,
            icon: const Icon(Icons.toll_outlined, size: 16),
            label: const Text('Add charge'),
          ),
          TextButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add item'),
          ),
        ]),
        if (lines.isEmpty)
          AppEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'No items yet',
            subtitle: 'Choose a product from inventory, scan barcode, or add charges/TCS',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Product'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF335C8D),
                    side: BorderSide(color: const Color(0xFF335C8D).withValues(alpha: 0.4)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addCharge,
                  icon: const Icon(Icons.toll_outlined, size: 16),
                  label: const Text('Add Charge / TCS'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: StitchColors.primary,
                    side: BorderSide(color: StitchColors.primary.withValues(alpha: 0.5)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                  label: const Text('Scan Barcode'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: StitchColors.textSecondary,
                    side: BorderSide(color: StitchColors.outline.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
          )
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
                Text(
                  lines.isEmpty
                      ? 'No items added'
                      : '${lines.length} ${lines.length == 1 ? "item" : "items"}',
                  style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                ),
              ]),
            ),
            Expanded(
              child: AsyncButton(
                loading: saving,
                icon: lines.isEmpty
                    ? Icons.add_rounded
                    : (widget.existingInvoiceId != null ? Icons.save_rounded : Icons.receipt_long_rounded),
                label: lines.isEmpty
                    ? 'Add items'
                    : (widget.existingInvoiceId != null ? 'Update invoice' : 'Save & checkout'),
                backgroundColor: lines.isEmpty ? const Color(0xFF4A6DA7) : StitchColors.primary,
                onPressed: lines.isEmpty ? _addItem : _checkout,
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
    final isCustomCharge = line.product.id == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Flexible(
                    child: Text(line.product.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isCustomCharge) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: StitchColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('CHARGE / TCS',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: StitchColors.primary)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Builder(builder: (context) {
                final unitStr = line.unit ?? line.product.unit;
                final qtyWithUnit = unitStr.isNotEmpty
                    ? '${_qty(line.qty)} $unitStr'
                    : _qty(line.qty);
                return Text('$qtyWithUnit × ${formatPaise(line.price)}  ${line.discountPercent > 0 ? '· ${_qty(line.discountPercent)}% off  ' : ''}${line.gstRate > 0 ? '· GST ${line.gstRate}%' : '· GST 0%'}',
                    style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary));
              }),
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

class _LineEditorSheet extends StatefulWidget {
  const _LineEditorSheet({required this.line, required this.onSave});
  final _LineEdit line;
  final ValueChanged<_LineEdit> onSave;
  @override
  State<_LineEditorSheet> createState() => _LineEditorSheetState();
}

class _LineEditorSheetState extends State<_LineEditorSheet> {
  late final TextEditingController nameController;
  late final TextEditingController qtyController;
  late final TextEditingController priceController;
  late final TextEditingController discountController;
  late final TextEditingController batchController;
  late final TextEditingController serialController;
  late int gstRate;
  String? unit;
  String? qtyError;
  String? priceError;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    nameController = TextEditingController(text: line.product.name);
    qtyController = TextEditingController(text: _qty(line.qty));
    priceController = TextEditingController(text: line.price == 0 ? '' : (line.price / 100).toStringAsFixed(2));
    discountController = TextEditingController(text: line.discountPercent == 0 ? '' : _qty(line.discountPercent));
    batchController = TextEditingController(text: line.batch ?? '');
    serialController = TextEditingController(text: line.serial ?? '');
    gstRate = line.gstRate;
    unit = line.unit ?? line.product.unit;
  }

  @override
  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    discountController.dispose();
    batchController.dispose();
    serialController.dispose();
    super.dispose();
  }

  void _apply() {
    final cleanQty = qtyController.text.replaceAll(',', '').trim();
    final qty = double.tryParse(cleanQty);
    final price = _toPaise(priceController.text);
    var hasError = false;
    if (qty == null || qty <= 0) {
      setState(() => qtyError = 'Enter valid qty');
      hasError = true;
    }
    if (price <= 0) {
      setState(() => priceError = 'Enter valid price/amount');
      hasError = true;
    }
    if (hasError) return;

    final updatedProduct = widget.line.product.id == null
        ? Product(
            id: null,
            name: nameController.text.trim().isEmpty ? widget.line.product.name : nameController.text.trim(),
            hsn: widget.line.product.hsn,
            salePrice: price,
            gstRate: gstRate,
            taxIncluded: widget.line.taxIncluded,
          )
        : widget.line.product;
    final update = _LineEdit(
      product: updatedProduct,
      qty: qty!,
      price: price,
      discountPercent: double.tryParse(discountController.text.replaceAll('%', '').trim()) ?? 0,
      gstRate: gstRate,
      taxIncluded: widget.line.taxIncluded,
      unit: unit,
      batch: batchController.text.trim().isEmpty ? null : batchController.text.trim(),
      serial: serialController.text.trim().isEmpty ? null : serialController.text.trim(),
    );
    widget.onSave(update);
    Navigator.of(context).pop();
  }

  static int _toPaise(String s) {
    final clean = s.replaceAll('₹', '').replaceAll(',', '').replaceAll(' ', '').trim();
    final v = double.tryParse(clean);
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
            if (line.product.id == null) ...[
              TextField(controller: nameController, decoration: inputDecoration('Charge / Description')),
              const SizedBox(height: 12),
            ] else ...[
              Text(line.product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
            ],
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
              Expanded(
                flex: 3,
                child: TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    if (qtyError != null) setState(() => qtyError = null);
                  },
                  decoration: inputDecoration('Quantity').copyWith(errorText: qtyError),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('unit-$unit'),
                  initialValue: (unit != null && kStandardUnits.any((u) => u.code == unit)) ? unit : null,
                  decoration: inputDecoration('Unit'),
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None', style: TextStyle(fontSize: 12))),
                    ...kStandardUnits.map((u) => DropdownMenuItem(
                          value: u.code,
                          child: Text('${u.code} (${u.name})', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) => setState(() => unit = val),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (priceError != null) setState(() => priceError = null);
                  },
                  decoration: inputDecoration(line.product.id == null ? 'Amount (₹)' : 'Unit price').copyWith(errorText: priceError),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: discountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: inputDecoration('Discount %'))),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('edit-line-gst-$gstRate'),
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
