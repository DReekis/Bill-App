import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import 'staff_form_sheet.dart';

class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  List<StaffMember> _staff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => _isLoading = true);
    final items = await Repository.instance.staffMembers(bizId);
    if (!mounted) return;
    setState(() {
      _staff = items;
      _isLoading = false;
    });
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return const Color(0xFF7C3AED); // Purple
      case UserRole.admin:
        return StitchColors.primary; // Indigo
      case UserRole.cashier:
        return const Color(0xFF0F766E); // Teal
      case UserRole.salesman:
        return const Color(0xFFD97706); // Amber
      case UserRole.deliveryBoy:
        return const Color(0xFF16A34A); // Green
      case UserRole.accountant:
        return const Color(0xFF2563EB); // Blue
    }
  }

  Future<void> _deleteStaff(StaffMember s) async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Staff Member?'),
        content: Text('Are you sure you want to deactivate ${s.name}? They will lose access to billing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StitchColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true && s.id != null) {
      await Repository.instance.deleteStaffMember(bizId, s.id!);
      _loadStaff();
      if (!mounted) return;
      showAppMessage(context, '${s.name} deactivated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final currentRole = session.role;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Staff & Permissions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          // Role Simulation / Quick Preview Bar
          _buildRoleSimulationCard(session, currentRole),
          const SizedBox(height: 16),

          // Header for Staff Directory
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Staff Directory (${_staff.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
              ),
              TextButton.icon(
                onPressed: () => StaffFormSheet.show(
                  context,
                  businessId: context.read<Session>().businessId,
                  onSaved: _loadStaff,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Staff', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_staff.isEmpty)
            _buildEmptyState()
          else
            ..._staff.map((s) => _buildStaffCard(s)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => StaffFormSheet.show(
          context,
          businessId: context.read<Session>().businessId,
          onSaved: _loadStaff,
        ),
        backgroundColor: StitchColors.primary,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white, size: 20),
        label: const Text('Add Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildRoleSimulationCard(Session session, UserRole currentRole) {
    final isSimulating = currentRole != UserRole.owner;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSimulating ? const Color(0xFFFEF3C7) : Colors.white, // Light amber if simulating
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSimulating ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isSimulating ? Icons.visibility_rounded : Icons.admin_panel_settings_outlined,
                    size: 18,
                    color: isSimulating ? const Color(0xFFB45309) : StitchColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isSimulating ? 'Active Role: ${currentRole.label}' : 'Test Role Permissions',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isSimulating ? const Color(0xFF92400E) : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              if (isSimulating)
                TextButton(
                  onPressed: () => session.setRole(UserRole.owner),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Reset to Owner', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isSimulating
                ? 'App is currently previewing restricted views for ${currentRole.label}. Profits & costs adapt accordingly.'
                : 'Tap a role to test how your cashiers or salesmen experience the app with restricted permissions:',
            style: TextStyle(fontSize: 11.5, color: isSimulating ? const Color(0xFF78350F) : const Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                UserRole.owner,
                UserRole.cashier,
                UserRole.salesman,
                UserRole.accountant,
              ].map((role) {
                final isSelected = currentRole == role;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(role.label),
                    selected: isSelected,
                    onSelected: (_) => session.setRole(role),
                    selectedColor: _getRoleColor(role),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(StaffMember s) {
    final roleColor = _getRoleColor(s.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: roleColor.withValues(alpha: 0.12),
            foregroundColor: roleColor,
            radius: 22,
            child: Text(
              s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      s.phone,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.role.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: roleColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
            onPressed: () => StaffFormSheet.show(
              context,
              staff: s,
              businessId: context.read<Session>().businessId,
              onSaved: _loadStaff,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: StitchColors.error),
            onPressed: () => _deleteStaff(s),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.badge_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No Staff Members Added',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add cashiers, salesmen, or delivery agents to assign permissions and secure your billing.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
