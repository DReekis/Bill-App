import 'package:flutter/material.dart';
import '../../core/subscription_service.dart';
import '../../theme/stitch_theme.dart';
import 'subscription_plans_screen.dart';

class FreeTierPaywallDialog extends StatelessWidget {
  const FreeTierPaywallDialog({super.key});

  static bool _hasPromptedThisSession = false;

  /// Shows the paywall modal if the user is on the free plan and hasn't dismissed it yet this session.
  static Future<void> showIfFree(BuildContext context, {bool force = false}) async {
    if (_hasPromptedThisSession && !force) return;
    
    // Ensure subscription service is initialized
    final sub = SubscriptionService.instance;
    if (sub.currentTier != SubscriptionTier.free) return;

    _hasPromptedThisSession = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FreeTierPaywallDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),

          // Plan Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Text(
              'FREE TIER ACTIVE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          const Text(
            'Unlock Billket Business Growth',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: StitchColors.textPrimary,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Subtitle
          const Text(
            'You are currently on the Free Plan (10 invoices limit). Choose a plan to unlock unlimited billing, e-Way bills, staff access & GST compliance.',
            style: TextStyle(
              fontSize: 13,
              color: StitchColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Plan Highlights
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildBenefitRow(Icons.all_inclusive_rounded, 'Unlimited Sales & Purchase Invoices', 'Never stop billing customers'),
                const SizedBox(height: 10),
                _buildBenefitRow(Icons.local_shipping_rounded, 'NIC E-Way Bill & E-Invoice Integration', 'Instant government compliance'),
                const SizedBox(height: 10),
                _buildBenefitRow(Icons.groups_rounded, 'Multi-Device & Staff PIN Management', 'Cashiers, salesmen & managers'),
                const SizedBox(height: 10),
                _buildBenefitRow(Icons.cloud_sync_rounded, 'Two-Layer Automatic Cloud Backup', 'Never lose invoices or accounting records'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Choose Plan Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Choose a Subscription Plan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Continue on Free Plan
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Continue on Free Plan (10 bills)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildBenefitRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF6366F1)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
