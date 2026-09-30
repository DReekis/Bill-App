import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../data/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/widgets.dart';

class ExpenseFormSheet extends StatefulWidget {
  const ExpenseFormSheet({
    super.key,
    required this.onSaved,
    required this.businessId,
    this.initialCategory,
  });

  final Future<void> Function() onSaved;
  final int businessId;
  final String? initialCategory;

  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _vendor = TextEditingController();
  final _customCategory = TextEditingController();
  String? category;
  String? mode;
  String date = todayIso();
  bool saving = false;
  bool isCustom = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialCategory;
    if (init != null) {
      if (init == 'Custom') {
        category = 'Custom';
        isCustom = true;
      } else if (expenseCategories.contains(init)) {
        category = init;
      } else {
        // Unknown or custom category passed
        category = 'Custom';
        isCustom = true;
        _customCategory.text = init;
      }
    } else {
      category = 'Rent';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _vendor.dispose();
    _customCategory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = _toPaise(_amount.text);
    if (amount <= 0) {
      showAppMessage(context, 'Enter a valid amount', error: true);
      return;
    }

    String finalCategory = category ?? 'Other';
    if (finalCategory == 'Custom' || isCustom) {
      final customName = _customCategory.text.trim();
      if (customName.isEmpty) {
        showAppMessage(context, 'Enter a custom category name', error: true);
        return;
      }
      finalCategory = customName;
    }

    setState(() => saving = true);
    try {
      await Repository.instance.recordExpense(
        businessId: widget.businessId,
        category: finalCategory,
        amount: amount,
        mode: mode ?? 'Cash',
        date: date,
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
      await widget.onSaved();
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static int _toPaise(String s) {
    final v = double.tryParse(s.trim());
    return v == null ? 0 : (v * 100).round();
  }

  void _selectCategory(String cat) {
    setState(() {
      category = cat;
      isCustom = (cat == 'Custom');
    });
  }

  Widget _buildQuickCategoryChip(String label, IconData icon, Color color) {
    final isSelected = category == label || (label == 'Custom' && isCustom);
    return InkWell(
      onTap: () => _selectCategory(label),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.grey.shade700),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCategory = (category != null && expenseCategories.contains(category))
        ? category
        : (isCustom ? 'Custom' : 'Other');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Record expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 8),
            AppAmountField(controller: _amount, label: 'Amount (₹) *'),
            const SizedBox(height: 14),

            // Quick Category Shortcuts
            const Text(
              'Quick Categories',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickCategoryChip('Rent', Icons.apartment_rounded, const Color(0xFF3949AB)),
                _buildQuickCategoryChip('Staff Salary', Icons.badge_outlined, const Color(0xFF00897B)),
                _buildQuickCategoryChip('Maintenance', Icons.build_outlined, const Color(0xFFE65100)),
                _buildQuickCategoryChip('Custom', Icons.edit_note_rounded, const Color(0xFF8E24AA)),
              ],
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              key: ValueKey(effectiveCategory),
              initialValue: effectiveCategory,
              decoration: inputDecoration('Category *'),
              items: expenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _selectCategory(v);
              },
            ),
            if (isCustom || category == 'Custom') ...[
              const SizedBox(height: 12),
              AppTextField(
                controller: _customCategory,
                label: 'Custom Category Name *',
                autofocus: widget.initialCategory == 'Custom',
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: 'Cash',
                  decoration: inputDecoration('Paid via'),
                  items: paymentModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => mode = v,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDateField(
                  date: date,
                  label: 'Date',
                  onDateSelected: (d) => setState(() => date = d),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            AppTextField(controller: _description, label: 'Description'),
            const SizedBox(height: 12),
            AppTextField(controller: _vendor, label: 'Vendor / party (optional)'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AsyncButton(loading: saving, label: 'Save expense', onPressed: _save),
            ),
          ]),
        ),
      ),
    );
  }
}

class ExpenseCategoryPickerSheet extends StatelessWidget {
  const ExpenseCategoryPickerSheet({
    super.key,
    required this.businessId,
    required this.onDone,
  });

  final int businessId;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFE53935), size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('add_expense'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Choose a category to record business expense',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.1,
              children: [
                _categoryTile(
                  context,
                  title: l10n.text('rent'),
                  subtitle: 'Shop, office & godown',
                  icon: Icons.apartment_rounded,
                  color: const Color(0xFF3949AB),
                  category: 'Rent',
                ),
                _categoryTile(
                  context,
                  title: l10n.text('staff_salary'),
                  subtitle: 'Employee payroll & wages',
                  icon: Icons.badge_outlined,
                  color: const Color(0xFF00897B),
                  category: 'Staff Salary',
                ),
                _categoryTile(
                  context,
                  title: l10n.text('maintenance'),
                  subtitle: 'Repairs & store upkeep',
                  icon: Icons.build_outlined,
                  color: const Color(0xFFE65100),
                  category: 'Maintenance',
                ),
                _categoryTile(
                  context,
                  title: l10n.text('custom'),
                  subtitle: 'Type your own category',
                  icon: Icons.edit_note_rounded,
                  color: const Color(0xFF8E24AA),
                  category: 'Custom',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Other Categories',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Electricity',
                'Internet',
                'Transport',
                'Marketing',
                'Packaging',
                'Office',
                'Bank charges',
                'Other',
              ].map((c) => ActionChip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.grey.shade100,
                onPressed: () => _openForm(context, c),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String category,
  }) {
    return InkWell(
      onTap: () => _openForm(context, category),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(BuildContext context, String category) {
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExpenseFormSheet(
        onSaved: onDone,
        businessId: businessId,
        initialCategory: category,
      ),
    );
  }
}

void showExpenseCategoryPicker(BuildContext context, {required int businessId, required Future<void> Function() onSaved}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ExpenseCategoryPickerSheet(
      businessId: businessId,
      onDone: onSaved,
    ),
  );
}