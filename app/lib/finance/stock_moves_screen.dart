import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

import '../features/inventory/product_form.dart';

class StockMovesScreen extends StatefulWidget {
  const StockMovesScreen({super.key, required this.productId});
  final int productId;
  @override
  State<StockMovesScreen> createState() => _StockMovesScreenState();
}

class _StockMovesScreenState extends State<StockMovesScreen> {
  Product? product;
  List<StockMove>? moves;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final products = await repo.products(businessId, includeInactive: true);
    Product? found;
    for (final x in products) {
      if (x.id == widget.productId) found = x;
    }
    final m = await repo.stockMoves(businessId, widget.productId);
    if (!mounted) return;
    setState(() {
      product = found;
      moves = m;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _adjust() async {
    final p = product;
    if (p == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StockAdjustmentSheet(product: p),
    );
    if (result == null) return;
    final change = (result['change'] as num).toDouble();
    if (change == 0 && result['moveType'] != 'stock_audit') return;
    final reason = result['reason'] as String?;
    final moveType = result['moveType'] as String? ?? 'adjustment';
    try {
      await Repository.instance.adjustStock(
        p,
        change,
        moveType,
        reason: reason,
      );
      await _load();
      if (mounted) {
        showAppMessage(context, 'Stock updated: ${p.stock} ${p.unit} in stock');
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not update: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final m = moves;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? 'Product'),
        actions: [
          if (p != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit product',
              onPressed: () {
                final bId = context.read<Session>().businessId;
                if (bId == null) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ProductFormSheet(
                    businessId: bId,
                    product: p,
                    onSaved: _load,
                    onSavedProduct: (_) => _load(),
                  ),
                );
              },
            ),
          TextButton.icon(
            onPressed: _adjust,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Adjust'),
          ),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    InitialsAvatar(p.name, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text([p.sku, p.category].whereType<String>().where((e) => e.isNotEmpty).join('  •  '),
                            style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      ]),
                    ),
                  ]),
                  const Divider(height: 20),
                  Row(children: [
                    Expanded(child: _stat('In stock', _qty(p.stock), p.outOfStock ? StitchColors.error : p.low ? StitchColors.warning : StitchColors.success)),
                    Expanded(child: _stat('Sale price', formatPaise(p.salePrice), StitchColors.textPrimary)),
                    Expanded(child: _stat('Purchase price', formatPaise(p.purchasePrice), StitchColors.textPrimary)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _stat('MRP', formatPaise(p.mrp), StitchColors.textSecondary)),
                    Expanded(child: _stat('GST', '${p.gstRate}%', StitchColors.textSecondary)),
                    Expanded(child: _stat('Unit', p.unit, StitchColors.textSecondary)),
                  ]),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _adjust,
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                          label: const Text('Add / Adjust Stock'),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              const Text('Stock history', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (m == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (m.isEmpty)
                const AppEmptyState(icon: Icons.receipt_long_rounded, title: 'No stock movements yet')
              else
                ...m.map((move) => _MoveTile(move: move)),
            ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]);

  static String _qty(num stock) => stock == stock.roundToDouble() ? stock.round().toString() : stock.toStringAsFixed(2);
}

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.move});
  final StockMove move;
  @override
  Widget build(BuildContext context) {
    final inQty = move.changeQty >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: inQty ? const Color(0xFFE8F5EF) : const Color(0xFFFFECE9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(inQty ? Icons.add_rounded : Icons.remove_rounded, size: 17, color: inQty ? StitchColors.success : StitchColors.error),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(move.moveType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(displayDate(move.date), style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${inQty ? '+' : ''}${_qty(move.changeQty)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: inQty ? StitchColors.success : StitchColors.error)),
            const SizedBox(height: 2),
            Text('after: ${_qty(move.qtyAfter)}', style: const TextStyle(fontSize: 10.5, color: StitchColors.textSecondary)),
          ]),
        ]),
      ),
    );
  }

  static String _qty(num stock) => stock == stock.roundToDouble() ? stock.round().toString() : stock.toStringAsFixed(2);
}

enum StockAdjustmentMode { add, reduce, set }

class _StockAdjustmentSheet extends StatefulWidget {
  const _StockAdjustmentSheet({required this.product});
  final Product product;

  @override
  State<_StockAdjustmentSheet> createState() => _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends State<_StockAdjustmentSheet> {
  StockAdjustmentMode _mode = StockAdjustmentMode.add;
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  String? _selectedReason;

  static const _addReasons = [
    'Stock Received',
    'Surplus Found',
    'Customer Return',
    'Correction',
    'Other'
  ];

  static const _reduceReasons = [
    'Damaged / Broken',
    'Expired',
    'Theft / Lost',
    'Internal Use',
    'Correction',
    'Other'
  ];

  static const _setReasons = [
    'Physical Audit',
    'Stocktake Count',
    'Correction'
  ];

  @override
  void initState() {
    super.initState();
    _selectedReason = _addReasons.first;
    _qtyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onModeChanged(StockAdjustmentMode mode) {
    setState(() {
      _mode = mode;
      _qtyController.clear();
      switch (mode) {
        case StockAdjustmentMode.add:
          _selectedReason = _addReasons.first;
          break;
        case StockAdjustmentMode.reduce:
          _selectedReason = _reduceReasons.first;
          break;
        case StockAdjustmentMode.set:
          _selectedReason = _setReasons.first;
          break;
      }
    });
  }

  void _applyQuickChip(int amount) {
    final current = int.tryParse(_qtyController.text.trim()) ?? 0;
    final next = current == 0 ? amount : (current + amount);
    _qtyController.text = next.toString();
    _qtyController.selection = TextSelection.fromPosition(
      TextPosition(offset: _qtyController.text.length),
    );
    setState(() {});
  }

  void _submit() {
    final entered = double.tryParse(_qtyController.text.trim());
    if (entered == null) {
      showAppMessage(context, 'Please enter a valid quantity', error: true);
      return;
    }
    if (_mode != StockAdjustmentMode.set && entered <= 0) {
      showAppMessage(context, 'Quantity must be greater than 0', error: true);
      return;
    }
    if (_mode == StockAdjustmentMode.set && entered < 0) {
      showAppMessage(context, 'Stock count cannot be negative', error: true);
      return;
    }

    final current = widget.product.stock.toDouble();
    double change;
    String moveType;

    switch (_mode) {
      case StockAdjustmentMode.add:
        change = entered;
        moveType = 'adjustment_in';
        break;
      case StockAdjustmentMode.reduce:
        change = -entered;
        moveType = 'adjustment_out';
        break;
      case StockAdjustmentMode.set:
        change = entered - current;
        moveType = 'stock_audit';
        break;
    }

    final reasonParts = <String>[];
    if (_selectedReason != null && _selectedReason!.isNotEmpty) {
      reasonParts.add(_selectedReason!);
    }
    if (_noteController.text.trim().isNotEmpty) {
      reasonParts.add(_noteController.text.trim());
    }

    Navigator.of(context).pop({
      'change': change,
      'moveType': moveType,
      'reason': reasonParts.isEmpty ? null : reasonParts.join(' - '),
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.product.stock;
    final enteredVal = double.tryParse(_qtyController.text.trim()) ?? 0.0;
    final enteredInt = enteredVal.round();

    int newTotal;
    int changeVal;
    switch (_mode) {
      case StockAdjustmentMode.add:
        newTotal = current + enteredInt;
        changeVal = enteredInt;
        break;
      case StockAdjustmentMode.reduce:
        newTotal = current - enteredInt;
        changeVal = -enteredInt;
        break;
      case StockAdjustmentMode.set:
        newTotal = enteredInt;
        changeVal = enteredInt - current;
        break;
    }

    final reasons = switch (_mode) {
      StockAdjustmentMode.add => _addReasons,
      StockAdjustmentMode.reduce => _reduceReasons,
      StockAdjustmentMode.set => _setReasons,
    };

    final isAdd = _mode == StockAdjustmentMode.add;
    final isReduce = _mode == StockAdjustmentMode.reduce;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stock Adjustment',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.product.name,
                          style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: StitchColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 14, color: StitchColors.primary),
                        const SizedBox(width: 5),
                        Text(
                          'Current: $current ${widget.product.unit}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<StockAdjustmentMode>(
                segments: const [
                  ButtonSegment(
                    value: StockAdjustmentMode.add,
                    label: Text('Add Stock (+)'),
                    icon: Icon(Icons.add_circle_outline_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: StockAdjustmentMode.reduce,
                    label: Text('Reduce (-)'),
                    icon: Icon(Icons.remove_circle_outline_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: StockAdjustmentMode.set,
                    label: Text('Set Total (=)'),
                    icon: Icon(Icons.pin_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (val) {
                  if (val.isNotEmpty) _onModeChanged(val.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isAdd
                      ? const Color(0xFFF0FDF4)
                      : (isReduce ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAdd
                        ? const Color(0xFFBBF7D0)
                        : (isReduce ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isAdd
                            ? const Color(0xFFDCFCE7)
                            : (isReduce ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAdd
                            ? Icons.add_rounded
                            : (isReduce ? Icons.remove_rounded : Icons.calculate_outlined),
                        size: 20,
                        color: isAdd
                            ? StitchColors.success
                            : (isReduce ? StitchColors.error : StitchColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAdd
                                ? 'Additive Calculation ($current + $enteredInt)'
                                : isReduce
                                    ? 'Deduction Calculation ($current - $enteredInt)'
                                    : 'Direct Count Reconciliation',
                            style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: StitchColors.textPrimary, fontSize: 13),
                              children: [
                                const TextSpan(text: 'New Total: '),
                                TextSpan(
                                  text: '$newTotal ${widget.product.unit}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: isAdd
                                        ? StitchColors.success
                                        : (isReduce && newTotal < 0
                                            ? StitchColors.error
                                            : StitchColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (changeVal >= 0 ? StitchColors.success : StitchColors.error).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${changeVal >= 0 ? '+' : ''}$changeVal',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: changeVal >= 0 ? StitchColors.success : StitchColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isAdd
                      ? 'Quantity to add (+)'
                      : (isReduce ? 'Quantity to reduce (-)' : 'New total count (=)'),
                  hintText: isAdd ? 'e.g. 20' : (isReduce ? 'e.g. 5' : 'e.g. 50'),
                  suffixText: widget.product.unit,
                  prefixIcon: Icon(
                    isAdd
                        ? Icons.add_circle_outline
                        : (isReduce ? Icons.remove_circle_outline : Icons.pin_outlined),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Quick:', style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                    const SizedBox(width: 8),
                    if (isAdd) ...[
                      ...[5, 10, 20, 50, 100].map((val) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text('+$val'),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () => _applyQuickChip(val),
                            ),
                          )),
                    ] else if (isReduce) ...[
                      ...[1, 2, 5, 10, 20].map((val) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text('-$val'),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () => _applyQuickChip(val),
                            ),
                          )),
                    ] else ...[
                      ...[0, 10, 25, 50, 100].map((val) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text('$val'),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () {
                                _qtyController.text = val.toString();
                                setState(() {});
                              },
                            ),
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                decoration: const InputDecoration(labelText: 'Adjustment Reason'),
                items: reasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedReason = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Remarks / Reference (optional)',
                  hintText: 'e.g. Batch ref, supplier invoice #',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(
                        isAdd
                            ? (enteredInt > 0 ? 'Add $enteredInt (➔ $newTotal)' : 'Add Stock (+)')
                            : isReduce
                                ? (enteredInt > 0 ? 'Reduce $enteredInt (➔ $newTotal)' : 'Reduce Stock (-)')
                                : 'Update Stock ($newTotal)',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}