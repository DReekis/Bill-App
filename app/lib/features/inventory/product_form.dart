import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class ProductFormSheet extends StatefulWidget {
  const ProductFormSheet({
    super.key,
    required this.onSaved,
    required this.onSavedProduct,
    required this.businessId,
    this.product,
    this.initialBarcode,
  });
  final Future<void> Function() onSaved;
  final ValueChanged<Product> onSavedProduct;
  final int businessId;
  final Product? product;
  final String? initialBarcode;
  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _category = TextEditingController();
  final _hsn = TextEditingController();
  final _barcode = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _salePrice = TextEditingController();
  final _wholesale = TextEditingController();
  final _retail = TextEditingController();
  final _mrp = TextEditingController();
  final _minSelling = TextEditingController();
  final _brand = TextEditingController();
  final _description = TextEditingController();
  final _openingStock = TextEditingController(text: '0');
  final _addStock = TextEditingController();
  final _lowStockThreshold = TextEditingController(text: '5');
  String? unit;
  int gstRate = 0;
  bool taxIncluded = false;
  bool hasBatch = false;
  bool hasSerial = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    unit = widget.product?.unit ?? 'pc';
    gstRate = widget.product?.gstRate ?? 0;
    taxIncluded = widget.product?.taxIncluded ?? false;
    hasBatch = widget.product?.hasBatch ?? false;
    hasSerial = widget.product?.hasSerial ?? false;
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _sku.text = p.sku ?? '';
      _brand.text = p.brand ?? '';
      _category.text = p.category ?? '';
      _hsn.text = p.hsn ?? '';
      _barcode.text = p.barcode ?? '';
      _purchasePrice.text = _rupees(p.purchasePrice);
      _salePrice.text = _rupees(p.salePrice);
      _wholesale.text = _rupees(p.wholesalePrice);
      _retail.text = _rupees(p.retailPrice);
      _mrp.text = _rupees(p.mrp);
      _minSelling.text = _rupees(p.minSellingPrice);
      _description.text = p.description ?? '';
      _lowStockThreshold.text = p.lowStockThreshold.toString();
    } else if (widget.initialBarcode != null && widget.initialBarcode!.isNotEmpty) {
      _barcode.text = widget.initialBarcode!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _category.dispose();
    _hsn.dispose();
    _barcode.dispose();
    _purchasePrice.dispose();
    _salePrice.dispose();
    _wholesale.dispose();
    _retail.dispose();
    _mrp.dispose();
    _minSelling.dispose();
    _brand.dispose();
    _description.dispose();
    _openingStock.dispose();
    _addStock.dispose();
    _lowStockThreshold.dispose();
    super.dispose();
  }

  static String _rupees(int paise) => paise == 0 ? '' : (paise / 100).toStringAsFixed(2);
  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppMessage(context, 'Product name is required', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      final currentStock = widget.product?.stock ?? 0;
      final addedStock = int.tryParse(_addStock.text.trim()) ?? 0;
      final openingStock = int.tryParse(_openingStock.text.trim()) ?? 0;
      final finalStock = widget.product != null ? (currentStock + addedStock) : openingStock;
      final lowStock = int.tryParse(_lowStockThreshold.text.trim()) ?? 5;

      final product = Product(
        id: widget.product?.id,
        name: _name.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim().toUpperCase(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        hsn: _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        unit: unit ?? 'pc',
        gstRate: gstRate,
        purchasePrice: _toPaise(_purchasePrice.text),
        salePrice: _toPaise(_salePrice.text),
        wholesalePrice: _toPaise(_wholesale.text),
        retailPrice: _toPaise(_retail.text),
        mrp: _toPaise(_mrp.text),
        minSellingPrice: _toPaise(_minSelling.text),
        taxIncluded: taxIncluded,
        hasBatch: hasBatch,
        hasSerial: hasSerial,
        description: _description.text.trim(),
        stock: finalStock,
        costAverage: widget.product?.costAverage ?? _toPaise(_purchasePrice.text),
        lowStockThreshold: lowStock,
      );
      await Repository.instance.upsertProduct(product, businessIdOverride: widget.businessId);
      if (mounted) Navigator.of(context).pop();
      await widget.onSaved();
      widget.onSavedProduct(product);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(editing ? 'Edit product' : 'Add product',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 6),
            AppTextField(controller: _name, label: 'Product / item name *'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppTextField(controller: _brand, label: 'Brand')),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(controller: _sku, label: 'SKU')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppTextField(controller: _category, label: 'Category')),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(controller: _barcode, label: 'Barcode')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppTextField(controller: _hsn, label: 'HSN code')),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: inputDecoration('Unit'),
                  items: ['pc', 'kg', 'g', 'l', 'ml', 'm', 'box', 'dozen', 'bottle', 'pack']
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => unit = v,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
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
                    onChanged: (v) => gstRate = v ?? 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CheckboxListTile(
                    value: taxIncluded,
                    onChanged: (v) => setState(() => taxIncluded = v ?? false),
                    title: const Text('Tax-incl.', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppAmountField(controller: _purchasePrice, label: 'Purchase price')),
              const SizedBox(width: 12),
              Expanded(child: AppAmountField(controller: _salePrice, label: 'Sale price')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppAmountField(controller: _wholesale, label: 'Wholesale price')),
              const SizedBox(width: 12),
              Expanded(child: AppAmountField(controller: _retail, label: 'Retail price')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppAmountField(controller: _mrp, label: 'MRP')),
              const SizedBox(width: 12),
              Expanded(child: AppAmountField(controller: _minSelling, label: 'Min. selling price')),
            ]),
            const SizedBox(height: 12),
            if (editing)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18, color: StitchColors.success),
                        const SizedBox(width: 8),
                        Text(
                          'Current Stock: ${widget.product!.stock} ${widget.product!.unit}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: StitchColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _addStock,
                            label: 'Add to stock (+ units)',
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            controller: _lowStockThreshold,
                            label: 'Low stock alert at',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    if ((int.tryParse(_addStock.text.trim()) ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Additive Update: ${widget.product!.stock} + ${_addStock.text.trim()} = ${widget.product!.stock + (int.tryParse(_addStock.text.trim()) ?? 0)} ${widget.product!.unit}',
                        style: const TextStyle(color: StitchColors.success, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: AppTextField(
                    controller: _openingStock,
                    label: 'Opening stock',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _lowStockThreshold,
                    label: 'Low stock alert at',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  value: hasBatch,
                  onChanged: (v) => setState(() => hasBatch = v ?? false),
                  title: const Text('Batch/Expiry', style: TextStyle(fontSize: 13)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  value: hasSerial,
                  onChanged: (v) => setState(() => hasSerial = v ?? false),
                  title: const Text('Serial/IMEI', style: TextStyle(fontSize: 13)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            AppTextField(controller: _description, label: 'Description', maxLines: 2),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AsyncButton(loading: saving, label: editing ? 'Save changes' : 'Add product', onPressed: _save),
            ),
          ]),
        ),
      ),
    );
  }
}
