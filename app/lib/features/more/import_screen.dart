import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../utils/widgets.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool importing = false;
  String? status;

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return;

    setState(() {
      importing = true;
      status = 'Reading file...';
    });

    try {
      final file = File(result.files.single.path!);
      final input = await file.readAsString();
      final rows = const CsvToListConverter().convert(input);

      if (rows.length < 2) throw 'File is empty';

      int success = 0;
      int errors = 0;

      for (var i = 1; i < rows.length; i++) {
        final r = rows[i];
        try {
          if (r.length < 3) continue;
          final name = r[0].toString();
          final salePrice = (double.tryParse(r[1].toString()) ?? 0 * 100).round();
          final stock = (double.tryParse(r[2].toString()) ?? 0).toInt();

          await Repository.instance.upsertProduct(Product(
            name: name,
            salePrice: salePrice,
            stock: stock,
          ));
          success++;
        } catch (e) {
          errors++;
        }
        setState(() => status = 'Importing: $success success, $errors errors');
      }

      setState(() {
        importing = false;
        status = 'Completed: $success products imported, $errors errors';
      });
    } catch (e) {
      setState(() {
        importing = false;
        status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('Import products from a CSV file. Format: Name, Sale Price, Stock', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 24),
          if (status != null) Text(status!, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: AsyncButton(
              loading: importing,
              label: 'Select CSV File',
              onPressed: _pickAndImport,
            ),
          ),
        ]),
      ),
    );
  }
}
