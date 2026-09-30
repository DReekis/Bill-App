import 'package:flutter/material.dart';
import '../theme/stitch_theme.dart';

class AppUnit {
  const AppUnit({
    required this.code,
    required this.name,
    required this.category,
    this.uqc,
  });

  final String code;
  final String name;
  final String category;
  final String? uqc;

  String get displayName => '$code ($name)';
}

const List<AppUnit> kStandardUnits = [
  // Count / Numbers
  AppUnit(code: 'PCS', name: 'Pieces', category: 'Count', uqc: 'PCS'),
  AppUnit(code: 'NOS', name: 'Numbers', category: 'Count', uqc: 'NOS'),
  AppUnit(code: 'UNT', name: 'Units', category: 'Count', uqc: 'UNT'),
  AppUnit(code: 'SET', name: 'Sets', category: 'Count', uqc: 'SET'),
  AppUnit(code: 'PRS', name: 'Pairs', category: 'Count', uqc: 'PRS'),
  AppUnit(code: 'DOZ', name: 'Dozens', category: 'Count', uqc: 'DOZ'),
  AppUnit(code: 'THD', name: 'Thousands', category: 'Count', uqc: 'THD'),
  AppUnit(code: 'HND', name: 'Hundreds', category: 'Count', uqc: 'HND'),

  // Packages / Containers
  AppUnit(code: 'BOX', name: 'Boxes', category: 'Packages', uqc: 'BOX'),
  AppUnit(code: 'PAC', name: 'Packs', category: 'Packages', uqc: 'PAC'),
  AppUnit(code: 'PKT', name: 'Packets', category: 'Packages', uqc: 'PKT'),
  AppUnit(code: 'BAG', name: 'Bags', category: 'Packages', uqc: 'BAG'),
  AppUnit(code: 'BTL', name: 'Bottles', category: 'Packages', uqc: 'BTL'),
  AppUnit(code: 'CAN', name: 'Cans', category: 'Packages', uqc: 'CAN'),
  AppUnit(code: 'CAS', name: 'Cases', category: 'Packages', uqc: 'CAS'),
  AppUnit(code: 'CTN', name: 'Cartons', category: 'Packages', uqc: 'CTN'),
  AppUnit(code: 'DRM', name: 'Drums', category: 'Packages', uqc: 'DRM'),
  AppUnit(code: 'JAR', name: 'Jars', category: 'Packages', uqc: 'JAR'),
  AppUnit(code: 'ROL', name: 'Rolls', category: 'Packages', uqc: 'ROL'),
  AppUnit(code: 'STR', name: 'Strips', category: 'Packages', uqc: 'STR'),
  AppUnit(code: 'TUB', name: 'Tubes', category: 'Packages', uqc: 'TUB'),
  AppUnit(code: 'TIN', name: 'Tins', category: 'Packages', uqc: 'TIN'),
  AppUnit(code: 'BDL', name: 'Bundles', category: 'Packages', uqc: 'BDL'),
  AppUnit(code: 'BAL', name: 'Bales', category: 'Packages', uqc: 'BAL'),
  AppUnit(code: 'CRT', name: 'Crates', category: 'Packages', uqc: 'CRT'),
  AppUnit(code: 'VIL', name: 'Vials', category: 'Packages', uqc: 'VIL'),

  // Weight
  AppUnit(code: 'KGS', name: 'Kilograms', category: 'Weight', uqc: 'KGS'),
  AppUnit(code: 'GMS', name: 'Grams', category: 'Weight', uqc: 'GMS'),
  AppUnit(code: 'QTL', name: 'Quintals', category: 'Weight', uqc: 'QTL'),
  AppUnit(code: 'TON', name: 'Tonnes', category: 'Weight', uqc: 'TON'),
  AppUnit(code: 'MTS', name: 'Metric Tons', category: 'Weight', uqc: 'MTS'),
  AppUnit(code: 'MGM', name: 'Milligrams', category: 'Weight', uqc: 'MGM'),
  AppUnit(code: 'LBS', name: 'Pounds', category: 'Weight', uqc: 'LBS'),
  AppUnit(code: 'OUN', name: 'Ounces', category: 'Weight', uqc: 'OUN'),

  // Volume / Liquid
  AppUnit(code: 'LTR', name: 'Litres', category: 'Volume', uqc: 'LTR'),
  AppUnit(code: 'MLT', name: 'Millilitres', category: 'Volume', uqc: 'MLT'),
  AppUnit(code: 'CCM', name: 'Cubic Centimeters', category: 'Volume', uqc: 'CCM'),
  AppUnit(code: 'CBM', name: 'Cubic Meters', category: 'Volume', uqc: 'CBM'),
  AppUnit(code: 'GAL', name: 'Gallons', category: 'Volume', uqc: 'GAL'),
  AppUnit(code: 'BBL', name: 'Barrels', category: 'Volume', uqc: 'BBL'),

  // Length / Distance
  AppUnit(code: 'MTR', name: 'Meters', category: 'Length', uqc: 'MTR'),
  AppUnit(code: 'CMS', name: 'Centimeters', category: 'Length', uqc: 'CMS'),
  AppUnit(code: 'MMT', name: 'Millimeters', category: 'Length', uqc: 'MMT'),
  AppUnit(code: 'INC', name: 'Inches', category: 'Length', uqc: 'INC'),
  AppUnit(code: 'FTS', name: 'Feet', category: 'Length', uqc: 'FTS'),
  AppUnit(code: 'YDS', name: 'Yards', category: 'Length', uqc: 'YDS'),
  AppUnit(code: 'KME', name: 'Kilometers', category: 'Length', uqc: 'KME'),

  // Area
  AppUnit(code: 'SQF', name: 'Square Feet', category: 'Area', uqc: 'SQF'),
  AppUnit(code: 'SQM', name: 'Square Meters', category: 'Area', uqc: 'SQM'),
  AppUnit(code: 'SQY', name: 'Square Yards', category: 'Area', uqc: 'SQY'),
  AppUnit(code: 'ACR', name: 'Acres', category: 'Area', uqc: 'ACR'),
  AppUnit(code: 'HEC', name: 'Hectares', category: 'Area', uqc: 'HEC'),

  // Time / Services
  AppUnit(code: 'HRS', name: 'Hours', category: 'Services', uqc: 'HRS'),
  AppUnit(code: 'DAY', name: 'Days', category: 'Services', uqc: 'DAY'),
  AppUnit(code: 'MTH', name: 'Months', category: 'Services', uqc: 'MTH'),
  AppUnit(code: 'JOB', name: 'Jobs', category: 'Services', uqc: 'JOB'),
  AppUnit(code: 'SER', name: 'Services', category: 'Services', uqc: 'SER'),
  AppUnit(code: 'VIS', name: 'Visits', category: 'Services', uqc: 'VIS'),
  AppUnit(code: 'TRP', name: 'Trips', category: 'Services', uqc: 'TRP'),

  // Others
  AppUnit(code: 'OTH', name: 'Others', category: 'Others', uqc: 'OTH'),
];

const List<String> kUnitCategories = [
  'All',
  'Count',
  'Packages',
  'Weight',
  'Volume',
  'Length',
  'Area',
  'Services',
  'Others',
];

AppUnit? matchAppUnit(String? unit) {
  if (unit == null || unit.trim().isEmpty) return null;
  final clean = unit.trim().toUpperCase();
  for (final u in kStandardUnits) {
    if (u.code == clean || u.name.toUpperCase() == clean) return u;
  }
  final lower = unit.trim().toLowerCase();
  switch (lower) {
    case 'pc':
    case 'piece':
    case 'pieces':
      return kStandardUnits.firstWhere((u) => u.code == 'PCS');
    case 'kg':
    case 'kgs':
    case 'kilo':
    case 'kilogram':
      return kStandardUnits.firstWhere((u) => u.code == 'KGS');
    case 'g':
    case 'gm':
    case 'gram':
    case 'grams':
      return kStandardUnits.firstWhere((u) => u.code == 'GMS');
    case 'l':
    case 'ltr':
    case 'litre':
    case 'litres':
      return kStandardUnits.firstWhere((u) => u.code == 'LTR');
    case 'ml':
    case 'millilitre':
      return kStandardUnits.firstWhere((u) => u.code == 'MLT');
    case 'm':
    case 'mtr':
    case 'meter':
    case 'meters':
      return kStandardUnits.firstWhere((u) => u.code == 'MTR');
    case 'cm':
      return kStandardUnits.firstWhere((u) => u.code == 'CMS');
    case 'mm':
      return kStandardUnits.firstWhere((u) => u.code == 'MMT');
    case 'box':
    case 'boxes':
      return kStandardUnits.firstWhere((u) => u.code == 'BOX');
    case 'pack':
    case 'packs':
      return kStandardUnits.firstWhere((u) => u.code == 'PAC');
    case 'pkt':
    case 'packet':
    case 'packets':
      return kStandardUnits.firstWhere((u) => u.code == 'PKT');
    case 'bottle':
    case 'bottles':
      return kStandardUnits.firstWhere((u) => u.code == 'BTL');
    case 'dozen':
    case 'dozens':
      return kStandardUnits.firstWhere((u) => u.code == 'DOZ');
    case 'sqft':
      return kStandardUnits.firstWhere((u) => u.code == 'SQF');
    case 'sqm':
      return kStandardUnits.firstWhere((u) => u.code == 'SQM');
    case 'hr':
    case 'hour':
      return kStandardUnits.firstWhere((u) => u.code == 'HRS');
  }
  return null;
}

String formatUnitDisplay(String? unit) {
  if (unit == null || unit.trim().isEmpty) return 'PCS (Pieces)';
  final matched = matchAppUnit(unit);
  if (matched != null) return matched.displayName;
  return unit.trim();
}

Future<String?> showUnitPicker(BuildContext context, {String? currentUnit}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      String query = '';
      String selectedCategory = 'All';
      const categories = kUnitCategories;

      return StatefulBuilder(
        builder: (context, setModalState) {
          final q = query.trim().toLowerCase();
          final filtered = kStandardUnits.where((u) {
            final matchesCat = selectedCategory == 'All' || u.category == selectedCategory;
            if (!matchesCat) return false;
            if (q.isEmpty) return true;
            return u.code.toLowerCase().contains(q) ||
                u.name.toLowerCase().contains(q) ||
                (u.uqc != null && u.uqc!.toLowerCase().contains(q));
          }).toList();

          final currentClean = currentUnit?.trim().toUpperCase();
          final hasExactCode = kStandardUnits.any((u) => u.code.toLowerCase() == q);

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
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Unit',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Standard commercial and GST units',
                                style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search unit e.g. PCS, BOX, KGS...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setModalState(() => query = ''),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (val) => setModalState(() => query = val),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Category Chips
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final cat = categories[i];
                        final isSel = selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat, style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? Colors.white : StitchColors.textPrimary,
                          )),
                          selected: isSel,
                          selectedColor: StitchColors.primary,
                          backgroundColor: Colors.grey.shade100,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          showCheckmark: false,
                          onSelected: (selected) {
                            if (selected) setModalState(() => selectedCategory = cat);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  // Custom Unit Banner if user typed something new
                  if (query.trim().isNotEmpty && !hasExactCode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: InkWell(
                        onTap: () => Navigator.pop(context, query.trim()),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: StitchColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StitchColors.primary.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, color: StitchColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: StitchColors.textPrimary),
                                    children: [
                                      const TextSpan(text: 'Use custom unit: '),
                                      TextSpan(
                                        text: '"${query.trim()}"',
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: StitchColors.primary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: StitchColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Units List
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'No standard unit matching "$query"',
                                  style: const TextStyle(color: StitchColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () => Navigator.pop(context, query.trim()),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text('Use "${query.trim()}" as unit'),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                            itemBuilder: (context, i) {
                              final u = filtered[i];
                              final isSelected = currentClean == u.code ||
                                  (currentUnit != null && matchAppUnit(currentUnit)?.code == u.code);

                              return ListTile(
                                leading: Container(
                                  width: 44,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? StitchColors.primary.withValues(alpha: 0.15)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? StitchColors.primary.withValues(alpha: 0.3)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    u.code,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? StitchColors.primary : StitchColors.textPrimary,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  u.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  '${u.category}${u.uqc != null ? ' • UQC: ${u.uqc}' : ''}',
                                  style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle_rounded, color: StitchColors.primary, size: 20)
                                    : null,
                                onTap: () => Navigator.pop(context, u.code),
                              );
                            },
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
