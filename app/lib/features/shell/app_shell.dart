import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../sync/sync_engine.dart';
import '../../sync/sync_badge.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../dashboard/dashboard_screen.dart';
import '../expenses/expense_form.dart';
import '../inventory/product_form.dart';
import '../inventory/product_list_screen.dart';
import '../more/more_screen.dart';
import '../payments/payment_form.dart';
import '../purchases/purchase_builder_screen.dart';
import '../reports/reports_menu_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/invoice_builder_screen.dart';
import '../sales/quotation_builder_screen.dart';
import '../orders/orders_screen.dart';
import '../sales/sales_order_builder_screen.dart';
import '../sales/delivery_challan_builder_screen.dart';
import '../purchases/purchase_order_builder_screen.dart';
import '../suppliers/supplier_form.dart';
import '../auth/login_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/stitch_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  // bumped after a quick action writes, to force the visible tab to reload
  int _dataVersion = 0;
  static const _icons = [
    Icons.home_filled,
    Icons.people_alt_outlined,
    Icons.inventory_2_outlined,
    Icons.bar_chart_rounded,
    Icons.more_horiz_rounded,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncEngine.instance.refreshPending();
      final session = context.read<Session>();
      if (session.isCloudLinked) {
        SyncEngine.instance.startAutoSync();
        SyncEngine.instance.syncNow();
      }
    });
  }

  Future<void> _syncNow() async {
    await SyncEngine.instance.syncNow();
    if (mounted) {
      showAppMessage(
          context,
          SyncEngine.instance.pendingCount == 0
              ? 'All changes synced'
              : '${SyncEngine.instance.pendingCount} changes waiting to sync');
    }
  }

  void _openQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => QuickActionSheet(
        onTap: (action) {
          Navigator.pop(sheetContext);
          _launchAction(action);
        },
      ),
    );
  }

  Future<void> _reloadTabs() async {
    if (mounted) setState(() => _dataVersion++);
    await SyncEngine.instance.refreshPending();
    SyncEngine.instance.triggerSync();
  }

  void _launchAction(String action) {
    final session = context.read<Session>();
    if (action.startsWith('Expense:')) {
      final category = action.substring('Expense:'.length);
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ExpenseFormSheet(
          onSaved: _reloadTabs,
          businessId: session.businessId!,
          initialCategory: category,
        ),
      );
      return;
    }
    switch (action) {
      case 'New Sale':
        Navigator.of(context)
            .push(
                MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()))
            .then((_) => _reloadTabs());
      case 'Purchase':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const PurchaseBuilderScreen()))
            .then((_) => _reloadTabs());
      case 'Quotation':
      case 'Estimate':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => QuotationBuilderScreen(businessId: session.businessId!)))
            .then((_) => _reloadTabs());
      case 'Payment In':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'customer')))
            .then((_) => _reloadTabs());
      case 'Payment Out':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'supplier')))
            .then((_) => _reloadTabs());
      case 'Expense':
        showExpenseCategoryPicker(
          context,
          businessId: session.businessId!,
          onSaved: _reloadTabs,
        );
      case 'Order':
      case 'Orders':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const OrdersScreen()))
            .then((_) => _reloadTabs());
      case 'Sales Order':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => SalesOrderBuilderScreen(businessId: session.businessId!)))
            .then((_) => _reloadTabs());
      case 'Purchase Order':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => PurchaseOrderBuilderScreen(businessId: session.businessId!)))
            .then((_) => _reloadTabs());
      case 'Challan':
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const DeliveryChallanBuilderScreen()))
            .then((_) => _reloadTabs());
      case 'Party':
      case 'Customer':
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => CustomerFormSheet(
                onSaved: _reloadTabs, businessId: session.businessId!));
      case 'Supplier':
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => SupplierFormSheet(
                onSaved: _reloadTabs, businessId: session.businessId!));
      case 'Product':
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => ProductFormSheet(
                onSaved: _reloadTabs,
                businessId: session.businessId!,
                onSavedProduct: (_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final l10n = context.l10n;
    final titles = [
      l10n.text('home'),
      l10n.text('party'),
      l10n.text('items'),
      l10n.text('reports'),
      l10n.text('more'),
    ];
    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              title: Row(children: [
                Text(titles[_index]),
                const SizedBox(width: 12),
                SyncBadge(onTap: _syncNow),
              ]),
              actions: [
                if (_index == 3)
                  IconButton(
                    tooltip: 'All Reports & Statements',
                    icon: const Icon(Icons.menu_book_rounded),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportsMenuScreen())),
                  ),
                if (session.hasPin)
                  IconButton(
                    tooltip: 'Lock app',
                    icon: const Icon(Icons.lock_outline_rounded),
                    onPressed: () => session.lock(),
                  ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => showAppMessage(context, 'No new alerts'),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showUserSessionSwitcher(context, session),
                    child: Tooltip(
                      message: '${session.currentUser} (${session.currentRole})',
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          InitialsAvatar(session.currentUser, size: 36),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: session.isStaff ? const Color(0xFF0F766E) : const Color(0xFF7C3AED),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Icon(
                                session.isStaff ? Icons.badge_rounded : Icons.workspace_premium_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: (_index == 0 || _index == 3)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_shell_one_click_sale',
                  onPressed: () {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => const InvoiceBuilderScreen()))
                        .then((_) => _reloadTabs());
                  },
                  backgroundColor: const Color(0xFF10B981),
                  icon: const Icon(Icons.add_shopping_cart_rounded,
                      color: Colors.white, size: 20),
                  label: Text(
                    l10n.text('sale'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                  elevation: 4,
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'fab_shell_quick_actions',
                  onPressed: _openQuickActions,
                  backgroundColor: StitchColors.primary,
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                ),
              ],
            ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            DashboardScreen(
              key: ValueKey('dashboard-$_dataVersion-${session.localeCode}'),
              onSwitchTab: (i) => setState(() {
                _index = i;
              }),
              onDataChanged: _reloadTabs,
            ),
            PartiesTab(key: ValueKey('parties-$_dataVersion-${session.localeCode}')),
            ProductListTab(key: ValueKey('products-$_dataVersion-${session.localeCode}')),
            ReportsTab(key: ValueKey('reports-$_dataVersion-${session.localeCode}')),
            MoreTab(key: ValueKey('more-$_dataVersion-${session.localeCode}')),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
        }),
        destinations: List.generate(
            titles.length,
            (i) => NavigationDestination(
                  icon: Icon(_icons[i]),
                  label: titles[i],
                )),
      ),
    );
  }

  void _showUserSessionSwitcher(BuildContext context, Session session) {
    final isStaff = session.isStaff;
    final role = session.role;
    Color roleColor;
    IconData roleIcon;
    switch (role) {
      case UserRole.owner:
        roleColor = const Color(0xFF7C3AED);
        roleIcon = Icons.workspace_premium_rounded;
      case UserRole.admin:
        roleColor = const Color(0xFF4F46E5);
        roleIcon = Icons.admin_panel_settings_rounded;
      case UserRole.cashier:
        roleColor = const Color(0xFF0F766E);
        roleIcon = Icons.point_of_sale_rounded;
      case UserRole.salesman:
        roleColor = const Color(0xFFD97706);
        roleIcon = Icons.storefront_rounded;
      case UserRole.deliveryBoy:
        roleColor = const Color(0xFF16A34A);
        roleIcon = Icons.two_wheeler_rounded;
      case UserRole.accountant:
        roleColor = const Color(0xFF2563EB);
        roleIcon = Icons.account_balance_rounded;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(roleIcon, color: roleColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                session.currentRole,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isStaff ? 'Staff Account' : 'Business Owner',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: roleColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.currentUser,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF2563EB), size: 22),
                ),
                title: Text(
                  isStaff ? 'Switch to Owner Login' : 'Switch to Staff / Cashier Login',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  isStaff ? 'Log in with Owner phone / credentials' : 'Log in as Cashier, Salesman or Delivery agent',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoginScreen(
                        isModal: true,
                        initialStaffMode: !isStaff,
                      ),
                    ),
                  ).then((_) => _reloadTabs());
                },
              ),
              if (session.hasPin) ...[
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_rounded, color: Color(0xFFDC2626), size: 20),
                  ),
                  title: const Text('Lock App Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Requires 4-digit PIN or biometrics to unlock', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  onTap: () {
                    Navigator.pop(ctx);
                    session.lock();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActionSheet extends StatelessWidget {
  const QuickActionSheet({super.key, required this.onTap});
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row1 = [
      {
        'icon': Icons.local_shipping_rounded,
        'label': l10n.text('purchase'),
        'action': 'Purchase',
        'c': const Color(0xFF2E7D32),
      },
      {
        'icon': Icons.request_quote_rounded,
        'label': l10n.text('estimate'),
        'action': 'Estimate',
        'c': const Color(0xFFD97706),
      },
      {
        'icon': Icons.call_received_rounded,
        'label': l10n.text('payment_in'),
        'action': 'Payment In',
        'c': const Color(0xFF3F51B5),
      },
      {
        'icon': Icons.call_made_rounded,
        'label': l10n.text('payment_out'),
        'action': 'Payment Out',
        'c': const Color(0xFFE65100),
      },
    ];
    final row2 = [
      {
        'icon': Icons.assignment_outlined,
        'label': l10n.text('sell_order'),
        'action': 'Sales Order',
        'c': const Color(0xFF5E35B1),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': l10n.text('purchase_order'),
        'action': 'Purchase Order',
        'c': const Color(0xFF00838F),
      },
      {
        'icon': Icons.local_shipping_outlined,
        'label': l10n.text('challan'),
        'action': 'Challan',
        'c': const Color(0xFF0284C7),
      },
      {
        'icon': Icons.receipt_long_rounded,
        'label': l10n.text('expense'),
        'action': 'Expense',
        'c': const Color(0xFFE53935),
      },
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.text('quick_actions'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row1
              .map((a) => QuickAction(
                    icon: a['icon'] as IconData,
                    label: a['label'] as String,
                    color: a['c'] as Color,
                    onTap: () => onTap(a['action'] as String),
                  ))
              .toList(),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row2
              .map((a) => QuickAction(
                    icon: a['icon'] as IconData,
                    label: a['label'] as String,
                    color: a['c'] as Color,
                    onTap: () => onTap(a['action'] as String),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFFE53935)),
              const SizedBox(width: 4),
              Text(
                l10n.text('quick_expenses'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickExpenseBtn(l10n.text('rent'), 'Expense:Rent', Icons.apartment_rounded, const Color(0xFF3949AB)),
            _quickExpenseBtn(l10n.text('staff_salary'), 'Expense:Staff Salary', Icons.badge_outlined, const Color(0xFF00897B)),
            _quickExpenseBtn(l10n.text('maintenance'), 'Expense:Maintenance', Icons.build_outlined, const Color(0xFFE65100)),
            _quickExpenseBtn(l10n.text('custom'), 'Expense:Custom', Icons.edit_note_rounded, const Color(0xFF8E24AA)),
          ],
        ),
      ]),
    );
  }

  Widget _quickExpenseBtn(String label, String action, IconData icon, Color color) {
    return InkWell(
      onTap: () => onTap(action),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
