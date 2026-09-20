import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

/// Representation of a product chosen with a specific quantity and unit price.
class SelectedProductItem {
  final Product product;
  final double quantity;
  final int unitPrice;

  const SelectedProductItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  int get totalPaise => (unitPrice * quantity).round();
}

/// A modern, BillBook-style multi-product selection sheet.
///
/// Allows merchants to search, filter by category, pick multiple products,
/// adjust quantities directly with `[ - ] [ qty ] [ + ]` steppers or direct numeric dialogs,
/// and batch-add everything in a single action.
class MultiProductPickerSheet extends StatefulWidget {
  const MultiProductPickerSheet({
    super.key,
    required this.products,
    required this.onItemsSelected,
    this.isPurchase = false,
    this.initialQuantities,
    this.onAddNew,
    this.onScanBarcode,
    this.title = 'Select Items',
    this.actionLabel = 'Add to Bill',
  });

  final List<Product> products;
  final ValueChanged<List<SelectedProductItem>> onItemsSelected;
  final bool isPurchase;
  final Map<int, double>? initialQuantities;
  final VoidCallback? onAddNew;
  final VoidCallback? onScanBarcode;
  final String title;
  final String actionLabel;

  @override
  State<MultiProductPickerSheet> createState() => _MultiProductPickerSheetState();
}

class _MultiProductPickerSheetState extends State<MultiProductPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  late final Map<int, double> _selectedQuantities;

  @override
  void initState() {
    super.initState();
    _selectedQuantities = {};
    if (widget.initialQuantities != null) {
      widget.initialQuantities!.forEach((id, qty) {
        if (qty > 0) {
          _selectedQuantities[id] = qty;
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _formatQty(num q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  int _getPrice(Product p) {
    if (widget.isPurchase) {
      return p.purchasePrice == 0 ? 100 : p.purchasePrice;
    }
    return p.salePrice;
  }

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

  void _updateQuantity(Product p, double qty) {
    if (p.id == null) return;
    setState(() {
      if (qty <= 0) {
        _selectedQuantities.remove(p.id!);
      } else {
        _selectedQuantities[p.id!] = qty;
      }
    });
  }

  void _increment(Product p) {
    final current = _selectedQuantities[p.id] ?? 0;
    _updateQuantity(p, current + 1);
  }

  void _decrement(Product p) {
    final current = _selectedQuantities[p.id] ?? 0;
    if (current > 0) {
      _updateQuantity(p, current - 1);
    }
  }

  Future<void> _showCustomQtyDialog(Product p) async {
    final current = _selectedQuantities[p.id] ?? 1.0;
    final controller = TextEditingController(text: _formatQty(current));

    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Quantity for ${p.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unit: ${p.unit.toUpperCase()} • Price: ${formatPaise(_getPrice(p))}',
              style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Enter Quantity',
                suffixText: p.unit,
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

    if (res != null) {
      _updateQuantity(p, res);
    }
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
          'Low stock (${_formatQty(stock)})',
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
          '${_formatQty(stock)} in stock',
          style: const TextStyle(
            color: StitchColors.success,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
  }

  void _submitSelection() {
    final items = <SelectedProductItem>[];
    _selectedQuantities.forEach((prodId, qty) {
      if (qty <= 0) return;
      Product? found;
      for (final p in widget.products) {
        if (p.id == prodId) {
          found = p;
          break;
        }
      }
      if (found != null) {
        items.add(SelectedProductItem(
          product: found,
          quantity: qty,
          unitPrice: _getPrice(found),
        ));
      }
    });

    widget.onItemsSelected(items);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _getCategories();
    final filtered = _getFilteredProducts();
    final isSearching = _searchController.text.trim().isNotEmpty;
    final topItems = widget.products.take(6).toList();

    int totalItemsSelected = 0;
    double totalUnits = 0;
    int totalAmountPaise = 0;

    _selectedQuantities.forEach((prodId, qty) {
      if (qty > 0) {
        totalItemsSelected++;
        totalUnits += qty;
        for (final p in widget.products) {
          if (p.id == prodId) {
            totalAmountPaise += (_getPrice(p) * qty).round();
            break;
          }
        }
      }
    });

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            // Top Header: Title & Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: StitchColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.checklist_rounded,
                          size: 20,
                          color: StitchColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Select multiple items & quantities',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onAddNew != null)
                        TextButton.icon(
                          onPressed: widget.onAddNew,
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                          label: const Text('New Item', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search item name, SKU, or barcode...',
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

            // Category Filter Chips
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

            const SizedBox(height: 6),

            // Quick Add Carousel for top selling / frequent items
            if (!isSearching && _selectedCategory == 'All' && topItems.isNotEmpty) ...[
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
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: topItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final p = topItems[i];
                    final qty = _selectedQuantities[p.id] ?? 0;
                    final isSelected = qty > 0;

                    return Container(
                      width: 140,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? StitchColors.primary.withValues(alpha: 0.08)
                            : StitchColors.surfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? StitchColors.primary.withValues(alpha: 0.5)
                              : Colors.grey.shade200,
                        ),
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
                                formatPaise(_getPrice(p)),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: StitchColors.primary,
                                ),
                              ),
                              if (!isSelected)
                                InkWell(
                                  onTap: () => _increment(p),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: StitchColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: StitchColors.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_formatQty(qty)}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
            ],

            // Main Product List
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
                            if (widget.onAddNew != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: widget.onAddNew,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Create This Product'),
                              ),
                            ],
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
                        final qty = _selectedQuantities[p.id] ?? 0;
                        final isSelected = qty > 0;
                        final price = _getPrice(p);
                        final itemSubtotal = (price * qty).round();

                        final details = <String>[];
                        if (p.category != null && p.category!.isNotEmpty) details.add(p.category!);
                        if (p.sku != null && p.sku!.isNotEmpty) details.add('SKU: ${p.sku}');
                        if (p.barcode != null && p.barcode!.isNotEmpty) details.add('BC: ${p.barcode}');

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? StitchColors.primary.withValues(alpha: 0.05)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? StitchColors.primary.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              InitialsAvatar(p.name, size: 42),
                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    if (details.isNotEmpty)
                                      Text(
                                        details.join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          formatPaise(price),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: StitchColors.primary,
                                          ),
                                        ),
                                        Text(
                                          ' / ${p.unit}',
                                          style: const TextStyle(fontSize: 11, color: StitchColors.textTertiary),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildStockBadge(p.stock),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Quantity Selector Controls (BillBook Style)
                              if (!isSelected)
                                OutlinedButton.icon(
                                  key: ValueKey('add_btn_${p.id}'),
                                  onPressed: () => _increment(p),
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: StitchColors.primary,
                                    side: const BorderSide(color: StitchColors.primary, width: 1.2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: StitchColors.primary, width: 1.2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: StitchColors.primary.withValues(alpha: 0.12),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Decrement [-]
                                          InkWell(
                                            key: ValueKey('stepper_dec_${p.id}'),
                                            onTap: () => _decrement(p),
                                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              child: const Icon(Icons.remove_rounded, size: 16, color: StitchColors.primary),
                                            ),
                                          ),

                                          // Quantity display with direct-edit tap
                                          InkWell(
                                            key: ValueKey('stepper_qty_${p.id}'),
                                            onTap: () => _showCustomQtyDialog(p),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              color: StitchColors.primary.withValues(alpha: 0.08),
                                              child: Text(
                                                _formatQty(qty),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                  color: StitchColors.primary,
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Increment [+]
                                          InkWell(
                                            key: ValueKey('stepper_inc_${p.id}'),
                                            onTap: () => _increment(p),
                                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              child: const Icon(Icons.add_rounded, size: 16, color: StitchColors.primary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '= ${formatPaise(itemSubtotal)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: StitchColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Sticky Bottom Action Bar (BillBook Style)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
              child: Row(
                children: [
                  // Left stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          totalItemsSelected == 0
                              ? 'No items selected'
                              : '$totalItemsSelected item${totalItemsSelected > 1 ? "s" : ""} (${_formatQty(totalUnits)} units)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: totalItemsSelected > 0 ? StitchColors.textSecondary : Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          formatPaise(totalAmountPaise),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: totalItemsSelected > 0 ? StitchColors.textPrimary : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Primary Action Button
                  FilledButton.icon(
                    onPressed: totalItemsSelected > 0 ? _submitSelection : null,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(
                      totalItemsSelected > 0
                          ? '${widget.actionLabel} ($totalItemsSelected)'
                          : widget.actionLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
}
