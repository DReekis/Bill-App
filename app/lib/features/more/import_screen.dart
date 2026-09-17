import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

enum ImportEntity {
  products('Products', 'Import catalog with prices, stock & HSN codes'),
  customers('Customers', 'Import client directory with phone & GSTIN'),
  suppliers('Suppliers', 'Import vendor directory with contact info'),
  openingBalances('Opening Balances', 'Set initial receivables and payables');

  const ImportEntity(this.label, this.description);
  final String label;
  final String description;
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportEntity selectedEntity = ImportEntity.products;
  bool parsing = false;
  bool importing = false;
  double importProgress = 0.0;
  String? statusMessage;

  List<String> detectedHeaders = [];
  List<List<dynamic>> parsedRows = [];
  Map<String, int> columnMapping = {}; // Canonical field name -> column index

  void _onEntityChanged(ImportEntity entity) {
    setState(() {
      selectedEntity = entity;
      parsedRows = [];
      detectedHeaders = [];
      columnMapping = {};
      statusMessage = null;
    });
  }

  void _downloadSampleTemplate() {
    String csvContent = '';
    String filename = '';

    switch (selectedEntity) {
      case ImportEntity.products:
        filename = 'products_sample_template.csv';
        csvContent = 'Product Name,Sale Price,Purchase Price,Opening Stock,HSN Code,GST Rate,Unit\n'
            'Samsung Galaxy S24 Ultra,129999.00,105000.00,25,8517,18,PCS\n'
            'Sony WH-1000XM5 Headphones,28990.00,21500.00,40,8518,18,PCS\n'
            'Apple 20W USB-C Adapter,1900.00,1300.00,100,8504,18,PCS\n';
      case ImportEntity.customers:
        filename = 'customers_sample_template.csv';
        csvContent = 'Customer Name,Mobile Phone,GSTIN,Address,State,Opening Balance,Credit Limit\n'
            'Rajesh Electronics,9876543210,27AABCU9603R1ZM,Shop 14 Lamington Rd,Maharashtra,25000.00,100000.00\n'
            'Modern Retail Store,9811223344,,Block B Connaught Place,Delhi,0.00,50000.00\n'
            'Pooja Sharma,9988776655,,Indira Nagar,Karnataka,5400.00,0.00\n';
      case ImportEntity.suppliers:
        filename = 'suppliers_sample_template.csv';
        csvContent = 'Supplier Name,Mobile Phone,GSTIN,Address,State,Opening Balance\n'
            'TechCorp India Distributors,9820011223,27AABCT3421A1Z9,MIDC Andheri East Mumbai,Maharashtra,125000.00\n'
            'Global Components Ltd,9845012345,29ABCDE1234F1Z5,Electronic City,Karnataka,45000.00\n';
      case ImportEntity.openingBalances:
        filename = 'opening_balances_template.csv';
        csvContent = 'Party Name,Party Type,Amount,Balance Type\n'
            'Rajesh Electronics,customer,25000.00,Debit\n'
            'TechCorp India Distributors,supplier,125000.00,Credit\n';
    }

    Share.share(csvContent, subject: filename);
  }

  Future<void> _pickCsvFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() {
      parsing = true;
      statusMessage = 'Reading CSV file...';
      parsedRows = [];
      detectedHeaders = [];
      columnMapping = {};
    });

    try {
      final file = File(result.files.single.path!);
      final input = await file.readAsString();
      final rows = const CsvToListConverter(shouldParseNumbers: false).convert(input);

      if (rows.length < 2) {
        throw 'CSV file must contain a header row and at least one data row';
      }

      final headers = rows[0].map((e) => e.toString().trim()).toList();
      final dataRows = rows.sublist(1).where((r) => r.any((c) => c.toString().trim().isNotEmpty)).toList();

      final mapping = _autoMapColumns(headers, selectedEntity);

      setState(() {
        parsing = false;
        detectedHeaders = headers;
        parsedRows = dataRows;
        columnMapping = mapping;
        statusMessage = 'Found ${dataRows.length} rows. Review mappings below before importing.';
      });
    } catch (e) {
      setState(() {
        parsing = false;
        statusMessage = 'Failed to parse CSV: $e';
      });
    }
  }

  Map<String, int> _autoMapColumns(List<String> headers, ImportEntity entity) {
    final Map<String, int> map = {};
    final lowerHeaders = headers.map((h) => h.toLowerCase()).toList();

    int? findCol(List<String> aliases) {
      for (final alias in aliases) {
        for (var i = 0; i < lowerHeaders.length; i++) {
          final h = lowerHeaders[i];
          if (h == alias || h.contains(alias)) {
            return i;
          }
        }
      }
      return null;
    }

    switch (entity) {
      case ImportEntity.products:
        final nameIdx = findCol(['product name', 'item name', 'name', 'item', 'title', 'description']);
        final salePriceIdx = findCol(['sale price', 'selling price', 'price', 'rate', 'mrp', 'sale']);
        final purPriceIdx = findCol(['purchase price', 'cost price', 'cost', 'purchase', 'buy price']);
        final stockIdx = findCol(['stock', 'quantity', 'qty', 'opening stock', 'units']);
        final hsnIdx = findCol(['hsn', 'hsn code', 'sac']);
        final gstIdx = findCol(['gst', 'gst rate', 'tax', 'tax rate', 'gst %']);
        final unitIdx = findCol(['unit', 'uom', 'uqc']);

        if (nameIdx != null) map['name'] = nameIdx;
        if (salePriceIdx != null) map['sale_price'] = salePriceIdx;
        if (purPriceIdx != null) map['purchase_price'] = purPriceIdx;
        if (stockIdx != null) map['stock'] = stockIdx;
        if (hsnIdx != null) map['hsn'] = hsnIdx;
        if (gstIdx != null) map['gst_rate'] = gstIdx;
        if (unitIdx != null) map['unit'] = unitIdx;

      case ImportEntity.customers:
        final nameIdx = findCol(['customer name', 'name', 'party name', 'client']);
        final phoneIdx = findCol(['phone', 'mobile', 'contact', 'telephone', 'mobile number']);
        final gstinIdx = findCol(['gstin', 'gst no', 'gst number', 'tax id']);
        final addrIdx = findCol(['address', 'billing address', 'street', 'city']);
        final stateIdx = findCol(['state', 'state name', 'place']);
        final opBalIdx = findCol(['opening balance', 'balance', 'due']);
        final limitIdx = findCol(['credit limit', 'limit']);

        if (nameIdx != null) map['name'] = nameIdx;
        if (phoneIdx != null) map['phone'] = phoneIdx;
        if (gstinIdx != null) map['gstin'] = gstinIdx;
        if (addrIdx != null) map['address'] = addrIdx;
        if (stateIdx != null) map['state'] = stateIdx;
        if (opBalIdx != null) map['opening_balance'] = opBalIdx;
        if (limitIdx != null) map['credit_limit'] = limitIdx;

      case ImportEntity.suppliers:
        final nameIdx = findCol(['supplier name', 'name', 'vendor name', 'party name', 'vendor']);
        final phoneIdx = findCol(['phone', 'mobile', 'contact', 'mobile number']);
        final gstinIdx = findCol(['gstin', 'gst no', 'gst number']);
        final addrIdx = findCol(['address', 'city', 'location']);
        final stateIdx = findCol(['state']);
        final opBalIdx = findCol(['opening balance', 'balance']);

        if (nameIdx != null) map['name'] = nameIdx;
        if (phoneIdx != null) map['phone'] = phoneIdx;
        if (gstinIdx != null) map['gstin'] = gstinIdx;
        if (addrIdx != null) map['address'] = addrIdx;
        if (stateIdx != null) map['state'] = stateIdx;
        if (opBalIdx != null) map['opening_balance'] = opBalIdx;

      case ImportEntity.openingBalances:
        final nameIdx = findCol(['party name', 'name', 'party']);
        final typeIdx = findCol(['party type', 'type', 'entity']);
        final amtIdx = findCol(['amount', 'balance', 'opening balance']);

        if (nameIdx != null) map['name'] = nameIdx;
        if (typeIdx != null) map['type'] = typeIdx;
        if (amtIdx != null) map['amount'] = amtIdx;
    }

    return map;
  }

  Future<void> _executeImport() async {
    if (parsedRows.isEmpty) return;
    if (!columnMapping.containsKey('name')) {
      showAppMessage(context, 'Name column must be mapped', error: true);
      return;
    }

    setState(() {
      importing = true;
      importProgress = 0.0;
      statusMessage = 'Importing 0 of ${parsedRows.length}...';
    });

    int success = 0;
    int errors = 0;

    String getVal(List<dynamic> row, String key) {
      final idx = columnMapping[key];
      if (idx == null || idx >= row.length) return '';
      return row[idx].toString().trim();
    }

    int parsePaise(String val) {
      final clean = val.replaceAll('₹', '').replaceAll(',', '').trim();
      final d = double.tryParse(clean) ?? 0.0;
      return (d * 100).round();
    }

    for (var i = 0; i < parsedRows.length; i++) {
      final row = parsedRows[i];
      try {
        final name = getVal(row, 'name');
        if (name.isEmpty) {
          errors++;
          continue;
        }

        switch (selectedEntity) {
          case ImportEntity.products:
            final salePrice = parsePaise(getVal(row, 'sale_price'));
            final purPrice = parsePaise(getVal(row, 'purchase_price'));
            final stock = double.tryParse(getVal(row, 'stock'))?.toInt() ?? 0;
            final hsn = getVal(row, 'hsn');
            final gstClean = getVal(row, 'gst_rate').replaceAll('%', '').trim();
            final gstRate = int.tryParse(gstClean) ?? 0;
            final unit = getVal(row, 'unit');

            await Repository.instance.upsertProduct(Product(
              name: name,
              salePrice: salePrice,
              purchasePrice: purPrice,
              stock: stock,
              hsn: hsn.isNotEmpty ? hsn : null,
              gstRate: gstRate,
              unit: unit.isNotEmpty ? unit : 'pc',
            ));

          case ImportEntity.customers:
            final phone = getVal(row, 'phone');
            final gstin = getVal(row, 'gstin');
            final addr = getVal(row, 'address');
            final state = getVal(row, 'state');
            final opBal = parsePaise(getVal(row, 'opening_balance'));
            final limit = parsePaise(getVal(row, 'credit_limit'));

            await Repository.instance.upsertCustomer(Customer(
              name: name,
              phone: phone.isNotEmpty ? phone : null,
              gstin: gstin.isNotEmpty ? gstin : null,
              billingAddress: addr.isNotEmpty ? addr : null,
              state: state.isNotEmpty ? state : null,
              openingBalance: opBal,
              creditLimit: limit,
            ));

          case ImportEntity.suppliers:
            final phone = getVal(row, 'phone');
            final gstin = getVal(row, 'gstin');
            final addr = getVal(row, 'address');
            final state = getVal(row, 'state');
            final opBal = parsePaise(getVal(row, 'opening_balance'));

            await Repository.instance.upsertSupplier(Supplier(
              name: name,
              phone: phone.isNotEmpty ? phone : null,
              gstin: gstin.isNotEmpty ? gstin : null,
              address: addr.isNotEmpty ? addr : null,
              state: state.isNotEmpty ? state : null,
              openingBalance: opBal,
            ));

          case ImportEntity.openingBalances:
            final type = getVal(row, 'type').toLowerCase();
            final amt = parsePaise(getVal(row, 'amount'));
            if (type.contains('supp') || type == 'supplier') {
              await Repository.instance.upsertSupplier(Supplier(
                name: name,
                openingBalance: amt,
              ));
            } else {
              await Repository.instance.upsertCustomer(Customer(
                name: name,
                openingBalance: amt,
              ));
            }
        }

        success++;
      } catch (_) {
        errors++;
      }

      if ((i + 1) % 5 == 0 || i == parsedRows.length - 1) {
        if (!mounted) return;
        setState(() {
          importProgress = (i + 1) / parsedRows.length;
          statusMessage = 'Importing ${i + 1} of ${parsedRows.length}... ($success success, $errors errors)';
        });
      }
    }

    if (!mounted) return;
    setState(() {
      importing = false;
      parsedRows = [];
      detectedHeaders = [];
      columnMapping = {};
      statusMessage = 'Completed: $success ${selectedEntity.label.toLowerCase()} imported successfully'
          '${errors > 0 ? ', $errors skipped' : ''}.';
    });
    showAppMessage(context, statusMessage!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Bulk Import Data', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Download Sample CSV',
            icon: const Icon(Icons.download_rounded, color: StitchColors.primary),
            onPressed: _downloadSampleTemplate,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          // Entity Selector Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entity in ImportEntity.values) ...[
                  InkWell(
                    onTap: () => _onEntityChanged(entity),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedEntity == entity ? StitchColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selectedEntity == entity ? StitchColors.primary : StitchColors.outline,
                        ),
                      ),
                      child: Text(
                        entity.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: selectedEntity == entity ? Colors.white : StitchColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Entity Description Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StitchColors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Import ${selectedEntity.label}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _downloadSampleTemplate,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('Sample Template', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  selectedEntity.description,
                  style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: StitchColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: importing || parsing ? null : _pickCsvFile,
                    icon: const Icon(Icons.upload_file_rounded, color: StitchColors.primary),
                    label: Text(
                      parsedRows.isEmpty ? 'Select CSV File' : 'Pick Another CSV File',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: StitchColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status & Progress Indicator
          if (statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: StitchColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusMessage!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (importing) ...[
            LinearProgressIndicator(
              value: importProgress,
              backgroundColor: const Color(0xFFE2E8F0),
              color: StitchColors.primary,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 14),
          ],

          // Column Mapping Preview
          if (columnMapping.isNotEmpty) ...[
            const Text(
              'Column Auto-Mapping',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StitchColors.outline),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in columnMapping.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.key.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: StitchColors.primary),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 10, color: StitchColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            detectedHeaders[entry.value],
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Preview Table
          if (parsedRows.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data Preview (${parsedRows.length} rows)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const Text(
                  'First 5 rows shown',
                  style: TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StitchColors.outline),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: [
                    for (final header in detectedHeaders)
                      DataColumn(
                        label: Text(
                          header,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                  ],
                  rows: [
                    for (final row in parsedRows.take(5))
                      DataRow(
                        cells: [
                          for (final cell in row)
                            DataCell(
                              Text(cell.toString(), style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Proceed Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: StitchColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: importing ? null : _executeImport,
                icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                label: Text(
                  importing ? 'Importing...' : 'Proceed with Import (${parsedRows.length} items)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
