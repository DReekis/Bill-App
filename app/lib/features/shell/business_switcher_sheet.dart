import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import 'business_edit_screen.dart';

/// Shows a professional bottom sheet enabling multi-business switching and management.
Future<bool?> showBusinessSwitcher(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BusinessSwitcherSheet(),
  );
}

class BusinessSwitcherSheet extends StatefulWidget {
  const BusinessSwitcherSheet({super.key});

  @override
  State<BusinessSwitcherSheet> createState() => _BusinessSwitcherSheetState();
}

class _BusinessSwitcherSheetState extends State<BusinessSwitcherSheet> {
  List<Business>? _businesses;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    setState(() => _loading = true);
    try {
      final list = await Repository.instance.allBusinesses();
      if (mounted) {
        setState(() {
          _businesses = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectBusiness(Business b) async {
    final session = context.read<Session>();
    if (session.businessId == b.id) {
      Navigator.pop(context, false);
      return;
    }
    await session.switchBusiness(b.id!);
    if (mounted) {
      showAppMessage(context, 'Switched to ${b.name}');
      Navigator.pop(context, true);
    }
  }

  void _addNewBusiness() {
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => const BusinessEditScreen(isNew: true),
      ),
    ).then((created) {
      if (!mounted) return;
      if (created == true) {
        nav.pop(true);
      } else {
        _loadBusinesses();
      }
    });
  }

  void _editBusiness(Business b) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessEditScreen(businessId: b.id),
      ),
    ).then((_) {
      if (mounted) _loadBusinesses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentBusinessId = context.watch<Session>().businessId;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Business',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Switch workspace or manage company profiles',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: StitchColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addNewBusiness,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add New'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),

          // Business list
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : (_businesses == null || _businesses!.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                'No businesses configured',
                                style: TextStyle(fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _addNewBusiness,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Create First Business'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _businesses!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final b = _businesses![index];
                          final isActive = b.id == currentBusinessId;

                          return Material(
                            color: isActive
                                ? StitchColors.primary.withValues(alpha: 0.07)
                                : StitchColors.surfaceVariant.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: () => _selectBusiness(b),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isActive
                                        ? StitchColors.primary
                                        : Colors.grey.shade200,
                                    width: isActive ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Business Avatar
                                    InitialsAvatar(b.name, size: 44),
                                    const SizedBox(width: 14),

                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  b.name,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: isActive
                                                        ? StitchColors.primary
                                                        : StitchColors.textPrimary,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isActive) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: StitchColors.primary,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'ACTIVE',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            b.gstin != null && b.gstin!.isNotEmpty
                                                ? 'GSTIN: ${b.gstin}'
                                                : (b.taxRegistered ? 'GST Registered' : 'Composition / Non-GST'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: StitchColors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (b.city != null || b.state != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              [b.city, b.state].where((e) => e != null && e.isNotEmpty).join(', '),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Action icons
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: StitchColors.textTertiary),
                                      tooltip: 'Edit Business Profile',
                                      onPressed: () => _editBusiness(b),
                                    ),
                                    if (isActive)
                                      const Icon(Icons.check_circle_rounded, color: StitchColors.primary, size: 22)
                                    else
                                      Icon(Icons.radio_button_unchecked_rounded, color: Colors.grey.shade400, size: 22),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
