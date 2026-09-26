import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class StaffFormSheet extends StatefulWidget {
  final StaffMember? staff;
  final int? businessId;
  final VoidCallback onSaved;

  const StaffFormSheet({
    super.key,
    this.staff,
    this.businessId,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    StaffMember? staff,
    int? businessId,
    required VoidCallback onSaved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StaffFormSheet(
        staff: staff,
        businessId: businessId ?? Repository.instance.session.businessId,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<StaffFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _pinController;
  late UserRole _selectedRole;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.staff;
    _nameController = TextEditingController(text: s?.name ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _pinController = TextEditingController(text: s?.pin ?? '');
    _selectedRole = s?.role ?? UserRole.cashier;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'Full unrestricted access to all business features, profits, and staff.';
      case UserRole.admin:
        return 'Can manage all billing, inventory, reports, and staff members.';
      case UserRole.cashier:
        return 'Can create sales bills & collect payments. Cost prices and profit & loss are hidden.';
      case UserRole.salesman:
        return 'Can create orders for assigned customers. Purchase costs and banking are hidden.';
      case UserRole.deliveryBoy:
        return 'Can view delivery orders and record Cash-on-Delivery payments.';
      case UserRole.accountant:
        return 'Full access to ledgers, Daybook, P&L, balance sheet, and Tally Prime XML export.';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final bizId = widget.businessId ??
        widget.staff?.businessId ??
        Repository.instance.session.businessId ??
        (context.mounted ? context.read<Session>().businessId : null);
    if (bizId == null) {
      showAppMessage(context, 'No active business selected', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final staff = StaffMember(
        id: widget.staff?.id,
        businessId: bizId,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        role: _selectedRole,
        pin: _pinController.text.trim().isEmpty ? null : _pinController.text.trim(),
        isActive: widget.staff?.isActive ?? true,
        createdAt: widget.staff?.createdAt ?? DateTime.now().toIso8601String(),
      );

      await Repository.instance.upsertStaffMember(staff);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      showAppMessage(
        context,
        widget.staff == null ? 'Staff member added' : 'Staff details updated',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showAppMessage(context, 'Error saving staff: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.staff != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Staff Member' : 'Add Staff Member',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Full Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name *',
                  hintText: 'e.g. Ramesh Kumar',
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter name' : null,
              ),
              const SizedBox(height: 12),

              // Phone Field
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Number *',
                  hintText: '10-digit mobile number',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => (v == null || v.trim().length < 10) ? 'Enter valid 10-digit mobile' : null,
              ),
              const SizedBox(height: 16),

              // Role Selection
              const Text(
                'Assign Role & Permissions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: UserRole.values.map((role) {
                  final isSelected = _selectedRole == role;
                  return ChoiceChip(
                    label: Text(role.label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedRole = role),
                    selectedColor: StitchColors.primary,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF475569),
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Role description card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_rounded, size: 16, color: StitchColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getRoleDescription(_selectedRole),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Optional 4-Digit Quick PIN
              TextFormField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Quick Counter PIN (Optional)',
                  hintText: '4-digit PIN for quick till lock',
                  prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Save Action Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StitchColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Add Staff Member',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
