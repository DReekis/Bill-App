import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../sync/sync_engine.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../dashboard/dashboard_screen.dart';
import '../expenses/expense_form.dart';
import '../inventory/product_form.dart';
import '../inventory/product_list_screen.dart';
import '../more/more_screen.dart';
import '../payments/payment_form.dart';
import '../purchases/purchase_builder_screen.dart';
import '../sales/invoice_builder_screen.dart';
import '../sales/invoice_list_tab.dart';
import '../suppliers/supplier_form.dart';
import '../../l10n/app_localizations.dart';

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
    Icons.receipt_long_outlined,
    Icons.inventory_2_outlined,
    Icons.people_alt_outlined,
    Icons.more_horiz_rounded,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncEngine.instance.refreshPending();
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
  }

  void _launchAction(String action) {
    final session = context.read<Session>();
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
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => ExpenseFormSheet(
                onSaved: _reloadTabs, businessId: session.businessId!));
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
    final sync = context.watch<SyncEngine>();
    final session = context.watch<Session>();
    final l10n = context.l10n;
    final titles = [
      l10n.text('home'),
      l10n.text('transactions'),
      l10n.text('items'),
      l10n.text('parties'),
      l10n.text('more'),
    ];
    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              title: Row(children: [
                Text(titles[_index]),
                const SizedBox(width: 12),
                _SyncBadge(
                    pending: sync.pendingCount,
                    busy: sync.syncing,
                    onTap: _syncNow),
              ]),
              actions: [
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
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: InitialsAvatar('Owner'),
                ),
              ],
            ),
      floatingActionButton: _index == 0
          ? null
          : FloatingActionButton(
              onPressed: _openQuickActions,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            DashboardScreen(
              key: ValueKey('dashboard-$_dataVersion-${session.localeCode}'),
              onSwitchTab: (i) => setState(() {
                _index = i;
                _dataVersion++;
              }),
              onDataChanged: _reloadTabs,
            ),
            InvoiceListTab(key: ValueKey('invoices-$_dataVersion-${session.localeCode}')),
            ProductListTab(key: ValueKey('products-$_dataVersion-${session.localeCode}')),
            PartiesTab(key: ValueKey('parties-$_dataVersion-${session.localeCode}')),
            MoreTab(key: ValueKey('more-$_dataVersion-${session.localeCode}')),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _dataVersion++;
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
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge(
      {required this.pending, required this.busy, required this.onTap});
  final int pending;
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = busy
        ? StitchColors.primary
        : pending > 0
            ? StitchColors.warning
            : StitchColors.success;
    final icon = busy
        ? Icons.sync_rounded
        : pending > 0
            ? Icons.cloud_upload_outlined
            : Icons.cloud_done_outlined;
    final label = busy
        ? 'Syncing'
        : pending > 0
            ? '$pending to sync'
            : 'Synced';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
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
    final actions = [
      {
        'icon': Icons.add_shopping_cart_rounded,
        'label': l10n.text('sale'),
        'action': 'New Sale',
        'c': const Color(0xFF3F51B5),
      },
      {
        'icon': Icons.local_shipping_rounded,
        'label': l10n.text('purchase'),
        'action': 'Purchase',
        'c': const Color(0xFF2E7D32),
      },
      {
        'icon': Icons.call_received_rounded,
        'label': l10n.text('payment_in'),
        'action': 'Payment In',
        'c': const Color(0xFF00C853),
      },
      {
        'icon': Icons.call_made_rounded,
        'label': l10n.text('payment_out'),
        'action': 'Payment Out',
        'c': const Color(0xFFE53935),
      },
      {
        'icon': Icons.currency_rupee_rounded,
        'label': l10n.text('expenses'),
        'action': 'Expense',
        'c': const Color(0xFFE53935),
      },
      {
        'icon': Icons.person_add_alt_1_rounded,
        'label': l10n.text('parties'),
        'action': 'Party',
        'c': const Color(0xFF00897B),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': l10n.text('item'),
        'action': 'Product',
        'c': const Color(0xFF7B1FA2),
      },
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.text('quick_actions'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: actions
              .map((a) => QuickAction(
                    icon: a['icon'] as IconData,
                    label: a['label'] as String,
                    color: a['c'] as Color,
                    onTap: () => onTap(a['action'] as String),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}
