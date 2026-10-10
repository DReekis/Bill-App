import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../core/subscription_service.dart';
import '../../core/razorpay_service.dart';
import '../../data/repositories.dart';

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  State<SubscriptionPlansScreen> createState() => _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshCurrentSubscription();
  }

  Future<void> _refreshCurrentSubscription() async {
    final session = context.read<Session>();
    if (session.cloudBusinessId != null && session.token != null) {
      await SubscriptionService.instance.syncWithServer(
        cloudBusinessId: session.cloudBusinessId!,
        token: session.token!,
        localBusinessId: session.businessId,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleUpgrade(SubscriptionTier tier) async {
    if (tier == SubscriptionTier.free) return;

    final session = context.read<Session>();
    final subService = SubscriptionService.instance;

    if (tier == subService.currentTier && !subService.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are already subscribed to ${tier.displayName}.'),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final business = session.businessId != null
          ? await Repository.instance.getBusiness(session.businessId!)
          : null;

      final cloudBizId = session.cloudBusinessId ??
          (session.businessId != null ? 'local_${session.businessId}' : 'biz_default');

      final result = await RazorpayService.instance.checkout(
        tier: tier,
        cloudBusinessId: cloudBizId,
        businessName: business?.name ?? 'PricePilot Business',
        localBusinessId: session.businessId,
        email: business?.email ?? session.cloudEmail,
        phone: business?.phone ?? session.mobile,
        token: session.token,
      );

      if (mounted) {
        setState(() => _loading = false);

        if (result.success) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Upgrade Activated!',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Congratulations! Your business is now activated on the ${tier.displayName} plan for 1 year.\n\nAll premium features, higher limits, and capabilities are unlocked immediately.',
                style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155)),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {});
                  },
                  child: const Text('Awesome'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message ?? 'Payment cancelled or verification failed.'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment initiation failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subService = SubscriptionService.instance;
    final currentTier = subService.currentTier;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Subscriptions & Licensing',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _refreshCurrentSubscription,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // Active Plan Status Header Card
              _buildCurrentStatusCard(subService),
              const SizedBox(height: 24),

              // Title & Subtitle
              const Text(
                'Choose Your Business Tier',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Annual billing with zero hidden fees. Instant activation via Razorpay.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Plan Cards Carousel / List
              _buildPlanCard(
                tier: SubscriptionTier.starter,
                title: 'Starter Plan',
                price: '₹579',
                period: '/ year',
                description: 'For small stores & individual traders needing unlimited billing.',
                highlights: [
                  'Unlimited Sales & Purchase Invoices',
                  'Sales & Purchase Returns + Quotes',
                  '500 Customers & 500 Suppliers, 1,000 Items',
                  'Basic P&L, Excel Export & Daily Backup',
                  '500 WhatsApp Invoices / month',
                ],
                isCurrent: currentTier == SubscriptionTier.starter,
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                tier: SubscriptionTier.silver,
                title: 'Silver Plan',
                price: '₹1,499',
                period: '/ year',
                badge: 'MOST POPULAR',
                badgeColor: const Color(0xFF2563EB),
                description: 'Full ERP tools for growing businesses with staff and orders.',
                highlights: [
                  'Sales & Purchase Orders + Delivery Challan',
                  'Barcode Scanning & Low Stock Alerts',
                  'Government E-Invoice IRN & 10 E-Way Bills/mo',
                  'Bank Management Hub & Tally XML Export',
                  'Multi-Device Sync, 2 Companies & 2 Users',
                  'Unlimited WhatsApp Invoices & Reminders',
                ],
                isCurrent: currentTier == SubscriptionTier.silver,
                isRecommended: true,
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                tier: SubscriptionTier.gold,
                title: 'Gold Plan',
                price: '₹2,999',
                period: '/ year',
                badge: 'BEST VALUE',
                badgeColor: const Color(0xFFD97706),
                description: 'Complete multi-user powerhouse with Desktop and advanced accounting.',
                highlights: [
                  'Windows Desktop & Android Multi-Device Support',
                  '10,000 Customers & 25,000 Items Catalog',
                  'Unlimited E-Way Bills & Unlimited Restores',
                  'Full Accounting: Balance Sheet & Party P&L',
                  '5 Companies & 5 Staff Users with Advanced RBAC',
                  'Priority Support & Dedicated Relationship Manager',
                ],
                isCurrent: currentTier == SubscriptionTier.gold,
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                tier: SubscriptionTier.businessPro,
                title: 'Business Pro',
                price: '₹4,999',
                period: '/ year',
                badge: 'ENTERPRISE',
                badgeColor: const Color(0xFF7C3AED),
                description: 'Uncapped unlimited enterprise edition with customer loyalty program.',
                highlights: [
                  'Everything in Gold + Unlimited Everything',
                  'Customer Loyalty Rewards & Points Engine',
                  'Up to 10 Business Companies Under One Account',
                  'Unlimited Staff Users & Device Access',
                  'Advanced P&L Analytics & Dedicated RM Support',
                ],
                isCurrent: currentTier == SubscriptionTier.businessPro,
              ),
              const SizedBox(height: 16),

              _buildFreePlanCard(isCurrent: currentTier == SubscriptionTier.free),
              const SizedBox(height: 24),

              // Expandable Deep Comparison Matrix
              _buildComparisonSection(),
              const SizedBox(height: 24),

              // Trust & Security Notice
              _buildSecurityFooter(),
              const SizedBox(height: 40),
            ],
          ),

          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 3),
                        SizedBox(height: 16),
                        Text(
                          'Connecting to Razorpay...',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatusCard(SubscriptionService subService) {
    final tier = subService.currentTier;
    final isExpired = subService.isExpired;
    final days = subService.daysRemaining;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF38BDF8),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ACTIVE SUBSCRIPTION',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isExpired
                      ? const Color(0xFFDC2626)
                      : (tier == SubscriptionTier.free
                          ? Colors.grey.shade700
                          : const Color(0xFF059669)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isExpired ? 'EXPIRED' : (tier == SubscriptionTier.free ? 'FREE TIER' : 'ACTIVE'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tier.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tier == SubscriptionTier.free
                        ? '10 invoices & basic stock included'
                        : (subService.expiresAt != null
                            ? 'Renews on ${subService.expiresAt!.day}/${subService.expiresAt!.month}/${subService.expiresAt!.year}'
                            : 'Annual license'),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (tier != SubscriptionTier.free)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$days',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Days Left',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required SubscriptionTier tier,
    required String title,
    required String price,
    required String period,
    required String description,
    required List<String> highlights,
    String? badge,
    Color? badgeColor,
    bool isCurrent = false,
    bool isRecommended = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecommended
              ? const Color(0xFF2563EB)
              : (isCurrent ? const Color(0xFF059669) : Colors.grey.shade200),
          width: isRecommended || isCurrent ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Badge
          if (badge != null || isCurrent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFF059669)
                    : (badgeColor ?? const Color(0xFF2563EB)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Text(
                isCurrent ? 'YOUR CURRENT ACTIVE PLAN' : badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Pricing
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      period,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Feature Highlights
                ...highlights.map((h) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Color(0xFF059669),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              h,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCurrent
                          ? Colors.grey.shade200
                          : (isRecommended
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF0F172A)),
                      foregroundColor: isCurrent ? Colors.grey.shade800 : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isCurrent ? null : () => _handleUpgrade(tier),
                    child: Text(
                      isCurrent ? 'Current Plan' : 'Upgrade to $title',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreePlanCard({bool isCurrent = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent ? const Color(0xFF059669) : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Free Plan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '₹0 / forever • 10 Sales Invoices • 50 Customers • Basic Stock',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: const Text(
          'Detailed Feature Comparison Matrix',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: const Text(
          'Compare limits and features across all 5 tiers',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          _buildComparisonTable(),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    final rows = [
      ['Sales Invoices', '10', 'Unlimited', 'Unlimited', 'Unlimited', 'Unlimited'],
      ['Purchases', '10', 'Unlimited', 'Unlimited', 'Unlimited', 'Unlimited'],
      ['Returns & Quotes', '❌', '✅', '✅', '✅', '✅'],
      ['Sales / PO / Challan', '❌', '❌', '✅', '✅', '✅'],
      ['Customer Limit', '50', '500', '2,500', '10,000', 'Unlimited'],
      ['Item Catalog', '100', '1,000', '5,000', '25,000', 'Unlimited'],
      ['Stock Management', 'Basic', 'Basic', 'Advanced', 'Advanced', 'Advanced'],
      ['Barcode & Low Stock', '❌', '❌', '✅', '✅', '✅'],
      ['Govt E-Invoice IRN', '❌', '❌', '✅', '✅', '✅'],
      ['E-Way Bill Generation', '❌', '❌', '10/month', 'Unlimited', 'Unlimited'],
      ['Bank Management Hub', '❌', '❌', '✅', '✅', '✅'],
      ['Tally XML Export', '❌', '❌', '✅', '✅', '✅'],
      ['P&L Financials', '❌', 'Basic', 'Basic', 'Advanced', 'Advanced'],
      ['Balance Sheet / Acct', '❌', '❌', '❌', '✅', '✅'],
      ['Windows Desktop App', '❌', '❌', '❌', '✅', '✅'],
      ['Companies Allowed', '1', '1', '2', '5', '10'],
      ['Staff Users', '1', '1', '2', '5', 'Unlimited'],
      ['Customer Loyalty Club', '❌', '❌', '❌', '❌', '✅'],
      ['Data Backup', '❌', 'Daily', 'Auto', 'Auto', 'Auto'],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Feature', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Free', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Starter', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Silver', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Gold', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pro', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: rows.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(r[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              DataCell(Text(r[1], style: const TextStyle(fontSize: 12))),
              DataCell(Text(r[2], style: const TextStyle(fontSize: 12))),
              DataCell(Text(r[3], style: const TextStyle(fontSize: 12))),
              DataCell(Text(r[4], style: const TextStyle(fontSize: 12))),
              DataCell(Text(r[5], style: const TextStyle(fontSize: 12))),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSecurityFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.security_rounded, color: Color(0xFF0F172A), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '100% Cryptographic Security by Razorpay',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'End-to-end encrypted • Server-side HMAC SHA-256 verification • PCI-DSS compliant payment processing.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
