import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../sync/sync_engine.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_form.dart';
import '../expenses/expense_form.dart';
import '../inventory/product_form.dart';
import '../payments/payment_form.dart';
import '../purchases/purchase_builder_screen.dart';
import '../purchases/purchase_order_builder_screen.dart';
import '../sales/delivery_challan_builder_screen.dart';
import '../sales/invoice_builder_screen.dart';
import '../sales/quotation_builder_screen.dart';
import '../sales/sales_order_builder_screen.dart';
import '../sales/invoice_detail_screen.dart';
import '../sales/invoice_list_tab.dart';
import '../suppliers/supplier_form.dart';
import '../search/search_screen.dart';
import '../reports/reports_menu_screen.dart';
import '../banking/cash_bank_hub_screen.dart';
import '../gst/gst_center_screen.dart';
import '../shell/business_switcher_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'payables_screen.dart';
import 'receivables_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onSwitchTab, this.onDataChanged});
  final ValueChanged<int>? onSwitchTab;
  final VoidCallback? onDataChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int>? totals;
  List<TransactionRecord>? recent;
  Business? business;
  List<double> salesHistory = [];
  List<double> profitHistory = [];
  int low = 0;
  int out = 0;
  int overdueCount = 0;
  int overdueAmount = 0;
  ReceivablesSummary? receivables;
  PayablesSummary? payables;
  String snapshotTimeframe = 'Today';
  TrendInfo salesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%');
  TrendInfo purchasesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%');
  TrendInfo expensesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%');
  TrendInfo revenueTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%');
  TrendInfo profitTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%');
  String comparisonLabel = 'vs yesterday';

  Future<void> _load() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final perf = await repo.dashboardPerformance(businessId, snapshotTimeframe);
    final recents = await repo.recentTransactions(businessId, limit: 5);
    final biz = await repo.getBusiness(businessId);
    final lowCount = await repo.lowStockCount(businessId);
    final outCount = await repo.outOfStockCount(businessId);
    final overdueSummary = await repo.overdueInvoicesSummary(businessId);
    final recSummary = await repo.receivablesSummary(businessId);
    final paySummary = await repo.payablesSummary(businessId);

    await SyncEngine.instance.refreshPending();
    if (!mounted) return;
    setState(() {
      totals = perf.totals;
      salesTrend = perf.salesTrend;
      purchasesTrend = perf.purchasesTrend;
      expensesTrend = perf.expensesTrend;
      revenueTrend = perf.revenueTrend;
      profitTrend = perf.profitTrend;
      comparisonLabel = perf.comparisonLabel;
      salesHistory = perf.salesHistory;
      profitHistory = perf.profitHistory;
      recent = recents;
      business = biz;
      low = lowCount;
      out = outCount;
      overdueCount = overdueSummary.$1;
      overdueAmount = overdueSummary.$2;
      receivables = recSummary;
      payables = paySummary;
    });
  }

  Future<void> _loadTotalsForTimeframe(String tf) async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final perf = await repo.dashboardPerformance(businessId, tf);
    if (!mounted) return;
    setState(() {
      totals = perf.totals;
      salesTrend = perf.salesTrend;
      purchasesTrend = perf.purchasesTrend;
      expensesTrend = perf.expensesTrend;
      revenueTrend = perf.revenueTrend;
      profitTrend = perf.profitTrend;
      comparisonLabel = perf.comparisonLabel;
      salesHistory = perf.salesHistory;
      profitHistory = perf.profitHistory;
      snapshotTimeframe = tf;
    });
  }

  Future<void> _showLowStockSheet() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final items = await Repository.instance.lowStockProducts(businessId);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: StitchColors.warning.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.warning_amber_rounded, color: StitchColors.warning, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Low Stock Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('${items.length} ${items.length == 1 ? "item needs" : "items need"} replenishment', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No low stock products.'))
                    : ListView.separated(
                        controller: scroll,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final p = items[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text('SKU: ${p.sku ?? "—"} • Reorder point: ${p.lowStockThreshold}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Text('${p.stock} left', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Add Purchase / Restock'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _quick('Purchase');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOverdueSheet() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final items = await Repository.instance.overdueInvoices(businessId);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: StitchColors.error.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.access_time_rounded, color: StitchColors.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Overdue Invoices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('${items.length} ${items.length == 1 ? "invoice is" : "invoices are"} past due date', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No overdue invoices.'))
                    : ListView.separated(
                        controller: scroll,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final inv = items[i];
                          final due = inv.total - inv.amountPaid;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(inv.number, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text('${inv.customerName ?? "Customer"} • Due: ${inv.dueDate ?? "—"}'),
                            trailing: Text('₹${formatPaise(due)}', style: const TextStyle(color: StitchColors.error, fontWeight: FontWeight.w800, fontSize: 14)),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id!))).then((_) => _load());
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.call_received_rounded, size: 18),
                  label: const Text('Record Payment In'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _quick('Payment In');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOutOfStockSheet() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final items = await Repository.instance.outOfStockProducts(businessId);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: StitchColors.error.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.error_outline_rounded, color: StitchColors.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Out of Stock Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('${items.length} ${items.length == 1 ? "item has" : "items have"} 0 inventory', style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No out of stock products.'))
                    : ListView.separated(
                        controller: scroll,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final p = items[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text('SKU: ${p.sku ?? "—"}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Text('0 in stock', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Add Purchase / Restock'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _quick('Purchase');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNotificationsSheet() {
    final pendingSync = SyncEngine.instance.pendingCount;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: StitchColors.primary, size: 24),
                SizedBox(width: 10),
                Text('Notifications & Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            if (low > 0)
              _NotificationItemTile(
                icon: Icons.warning_amber_rounded,
                color: StitchColors.warning,
                title: 'Low Stock Alert',
                subtitle: '$low products have reached minimum reorder levels',
                actionLabel: 'View Products',
                onAction: () {
                  Navigator.pop(ctx);
                  _showLowStockSheet();
                },
              ),
            if (out > 0)
              _NotificationItemTile(
                icon: Icons.error_outline_rounded,
                color: StitchColors.error,
                title: 'Out of Stock Alert',
                subtitle: '$out products are completely depleted',
                actionLabel: 'View Items',
                onAction: () {
                  Navigator.pop(ctx);
                  _showOutOfStockSheet();
                },
              ),
            if (overdueCount > 0)
              _NotificationItemTile(
                icon: Icons.access_time_rounded,
                color: StitchColors.error,
                title: 'Overdue Invoices Alert',
                subtitle: '$overdueCount invoices totaling ₹${formatPaise(overdueAmount)} are past due',
                actionLabel: 'View Invoices',
                onAction: () {
                  Navigator.pop(ctx);
                  _showOverdueSheet();
                },
              ),
            if (pendingSync > 0)
              _NotificationItemTile(
                icon: Icons.sync_problem_rounded,
                color: const Color(0xFF3F51B5),
                title: 'Pending Cloud Sync',
                subtitle: '$pendingSync changes queued locally for cloud sync',
                actionLabel: 'Sync Now',
                onAction: () async {
                  Navigator.pop(ctx);
                  await SyncEngine.instance.syncNow();
                  await _load();
                  if (mounted) showAppMessage(context, 'Sync triggered');
                },
              ),
            if (low == 0 && out == 0 && overdueCount == 0 && pendingSync == 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('All Caught Up!', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green.shade900, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text('Stock levels healthy, no overdue invoices, and all records are synced.', style: TextStyle(color: Colors.green.shade800, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _quick(String action) {
    final session = context.read<Session>();
    if (action == 'Reports' && !session.can('view_reports')) {
      showAppMessage(context, 'Access Denied', error: true);
      return;
    }
    final businessId = session.businessId!;
    final nav = Navigator.of(context);
    Future<void> onDone() async {
      await _load();
      widget.onDataChanged?.call();
    }

    switch (action) {
      case 'New Sale':
        nav
            .push(
                MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()))
            .then((_) => onDone());
      case 'Payment In':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'customer')))
            .then((_) => onDone());
      case 'Payment Out':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'supplier')))
            .then((_) => onDone());
      case 'Purchase':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PurchaseBuilderScreen()))
            .then((_) => onDone());
      case 'Estimate':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const QuotationBuilderScreen()))
            .then((_) => onDone());
      case 'Sales Order':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const SalesOrderBuilderScreen()))
            .then((_) => onDone());
      case 'Purchase Order':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PurchaseOrderBuilderScreen()))
            .then((_) => onDone());
      case 'Challan':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const DeliveryChallanBuilderScreen()))
            .then((_) => onDone());
      case 'Reports':
        nav.push(MaterialPageRoute(builder: (_) => const ReportsMenuScreen()));
      case 'GST Center':
        nav.push(MaterialPageRoute(builder: (_) => const GstCenterScreen()));
      case 'Cash & Bank':
        nav.push(MaterialPageRoute(builder: (_) => const CashBankHubScreen())).then((_) => onDone());
      default:
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => switch (action) {
                  'Party' =>
                    CustomerFormSheet(onSaved: onDone, businessId: businessId),
                  'Customer' =>
                    CustomerFormSheet(onSaved: onDone, businessId: businessId),
                  'Supplier' =>
                    SupplierFormSheet(onSaved: onDone, businessId: businessId),
                  'Product' => ProductFormSheet(
                      onSaved: onDone,
                      businessId: businessId,
                      onSavedProduct: (_) {}),
                  'Expense' =>
                    ExpenseFormSheet(onSaved: onDone, businessId: businessId),
                  _ => const SizedBox.shrink(),
                });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final profitToday = t == null
        ? 0
        : t['taxableToday']! - t['cogsToday']! - t['expensesToday']!;
    return Scaffold(
      body: _ReferenceDashboard(
        business: business,
        totals: t,
        profitToday: profitToday,
        low: low,
        out: out,
        overdueCount: overdueCount,
        overdueAmount: overdueAmount,
        receivables: receivables,
        payables: payables,
        snapshotTimeframe: snapshotTimeframe,
        salesHistory: salesHistory,
        profitHistory: profitHistory,
        salesTrend: salesTrend,
        purchasesTrend: purchasesTrend,
        expensesTrend: expensesTrend,
        revenueTrend: revenueTrend,
        profitTrend: profitTrend,
        comparisonLabel: comparisonLabel,
        recent: recent,
        onViewAllTransactions: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TransactionListScreen(),
            ),
          );
        },
        onQuick: _quick,
        onRefresh: _load,
        onSelectTimeframe: _loadTotalsForTimeframe,
        onOpenNotifications: _openNotificationsSheet,
        onShowLowStock: _showLowStockSheet,
        onShowOverdue: _showOverdueSheet,
        onShowOutOfStock: _showOutOfStockSheet,
        onSwitchBusiness: () => showBusinessSwitcher(context).then((changed) {
          if (changed == true) _load();
        }),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        backgroundColor: StitchColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = ctx.l10n;
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionItem(ctx, Icons.shopping_cart_outlined, l10n.text('sale'), 'New Sale', const Color(0xFF3F51B5)),
                    _actionItem(ctx, Icons.shopping_bag_outlined, l10n.text('purchase'), 'Purchase', const Color(0xFF2E7D32)),
                    _actionItem(ctx, Icons.description_outlined, l10n.text('estimate'), 'Estimate', const Color(0xFF0288D1)),
                  ]),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionItem(ctx, Icons.assignment_outlined, l10n.text('order'), 'Sales Order', const Color(0xFFE65100)),
                    _actionItem(ctx, Icons.local_shipping_outlined, l10n.text('challan'), 'Challan', const Color(0xFF5E35B1)),
                    _actionItem(ctx, Icons.person_add_outlined, l10n.text('parties'), 'Party', const Color(0xFF00897B)),
                  ]),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionItem(ctx, Icons.inventory_2_outlined, l10n.text('item'), 'Product', const Color(0xFF7B1FA2)),
                    _actionItem(ctx, Icons.payments_outlined, l10n.text('payment_in'), 'Payment In', const Color(0xFF00C853)),
                    _actionItem(ctx, Icons.outbox_outlined, l10n.text('payment_out'), 'Payment Out', const Color(0xFFE53935)),
                  ]),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionItem(ctx, Icons.account_balance_outlined, l10n.text('gst'), 'GST Center', const Color(0xFF00838F)),
                    _actionItem(ctx, Icons.account_balance_wallet_outlined, l10n.text('cash_bank'), 'Cash & Bank', const Color(0xFF1B5E20)),
                    _actionItem(ctx, Icons.bar_chart_rounded, l10n.text('reports'), 'Reports', const Color(0xFF5C6BC0)),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionItem(BuildContext context, IconData icon, String label, String action, Color color) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(context);
          _quick(action);
        },
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textPrimary),
              ),
            ],
          ),
        ),
      );
}

class _ReferenceDashboard extends StatelessWidget {
  const _ReferenceDashboard({
    required this.business,
    required this.totals,
    required this.profitToday,
    required this.low,
    required this.out,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.receivables,
    this.payables,
    this.snapshotTimeframe = 'Today',
    required this.salesHistory,
    required this.profitHistory,
    this.salesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.purchasesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.expensesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.revenueTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.profitTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.comparisonLabel = 'vs yesterday',
    this.recent,
    this.onViewAllTransactions,
    required this.onQuick,
    required this.onRefresh,
    this.onSelectTimeframe,
    this.onOpenNotifications,
    this.onShowLowStock,
    this.onShowOverdue,
    this.onShowOutOfStock,
    this.onSwitchBusiness,
  });

  final Business? business;
  final Map<String, int>? totals;
  final int profitToday;
  final int low;
  final int out;
  final int overdueCount;
  final int overdueAmount;
  final ReceivablesSummary? receivables;
  final PayablesSummary? payables;
  final String snapshotTimeframe;
  final List<double> salesHistory;
  final List<double> profitHistory;
  final TrendInfo salesTrend;
  final TrendInfo purchasesTrend;
  final TrendInfo expensesTrend;
  final TrendInfo revenueTrend;
  final TrendInfo profitTrend;
  final String comparisonLabel;
  final List<TransactionRecord>? recent;
  final VoidCallback? onViewAllTransactions;
  final ValueChanged<String> onQuick;
  final Future<void> Function() onRefresh;
  final ValueChanged<String>? onSelectTimeframe;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onShowLowStock;
  final VoidCallback? onShowOverdue;
  final VoidCallback? onShowOutOfStock;
  final VoidCallback? onSwitchBusiness;

  String amount(int? value) => value == null ? '₹0' : formatPaise(value);

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 12) return l10n.text('good_morning');
    if (hour >= 12 && hour < 17) return l10n.text('good_afternoon');
    return l10n.text('good_evening');
  }

  String shortDate(DateTime date) => '${date.day} ${const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = totals;
    final name = business?.ownerName?.split(' ').first ?? 'Rahul';
    final alertCount = (low > 0 ? 1 : 0) + (out > 0 ? 1 : 0) + (overdueCount > 0 ? 1 : 0);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: StitchColors.textPrimary),
                        children: [
                          TextSpan(text: 'Bill'),
                          TextSpan(
                              text: 'ket',
                              style: TextStyle(color: StitchColors.primary))
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onSwitchBusiness,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: StitchColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                business?.name ?? 'My Business',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: StitchColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: StitchColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Text('Smart Billing. Better Business.',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
              ],
            ),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded, size: 26, color: StitchColors.textPrimary)),
            Stack(children: [
              IconButton(
                  onPressed: onOpenNotifications,
                  tooltip: 'Alerts & Notifications',
                  icon: const Icon(Icons.notifications_none_rounded, size: 26, color: StitchColors.textPrimary)),
              if (alertCount > 0)
                Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: StitchColors.error, shape: BoxShape.circle),
                      child: Text('$alertCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    )),
            ]),
            const SizedBox(width: 4),
            InkWell(
              onTap: onSwitchBusiness,
              borderRadius: BorderRadius.circular(18),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF3F51B5),
                child: Text(
                  (business?.name.isNotEmpty == true ? business!.name[0] : 'R').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_greeting(l10n)}, $name 👋',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text(l10n.text('business_summary'),
                        style: const TextStyle(fontSize: 14, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: StitchColors.textPrimary),
                  const SizedBox(width: 8),
                  Text(shortDate(DateTime.now()),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _Snapshot(
            totals: t,
            amount: amount,
            timeframe: snapshotTimeframe,
            onSelectTimeframe: onSelectTimeframe,
            salesTrend: salesTrend,
            purchasesTrend: purchasesTrend,
            expensesTrend: expensesTrend,
          ),
          const SizedBox(height: 16),

          _CashFlowSummaryRow(
            receivables: receivables,
            payables: payables,
            onTapReceivables: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceivablesScreen()),
              ).then((_) => onRefresh());
            },
            onTapPayables: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PayablesScreen()),
              ).then((_) => onRefresh());
            },
          ),
          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.text('business_overview'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              PopupMenuButton<String>(
                initialValue: snapshotTimeframe,
                tooltip: 'Select timeframe',
                onSelected: (val) => onSelectTimeframe?.call(val),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.white,
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'Today', child: Text(l10n.text('today'))),
                  PopupMenuItem(value: 'This Week', child: Text(l10n.text('this_week'))),
                  PopupMenuItem(value: 'This Month', child: Text(l10n.text('this_month'))),
                  PopupMenuItem(value: 'This Year', child: Text(l10n.text('this_year'))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: StitchColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshotTimeframe == 'Today'
                            ? l10n.text('today')
                            : (snapshotTimeframe == 'This Week'
                                ? l10n.text('this_week')
                                : (snapshotTimeframe == 'This Month'
                                    ? l10n.text('this_month')
                                    : l10n.text('this_year'))),
                        style: const TextStyle(color: StitchColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: StitchColors.primary, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _OverviewCard(
                    label: l10n.text('revenue'),
                    value: formatPaise(totals?['taxableToday'] ?? 0),
                    change: '${revenueTrend.formatted} $comparisonLabel',
                    data: salesHistory,
                    isNegative: revenueTrend.isNegative,
                    color: revenueTrend.isNegative ? const Color(0xFFE53935) : const Color(0xFF00C853))),
            const SizedBox(width: 16),
            Expanded(
                child: _OverviewCard(
                    label: l10n.text('net_profit'),
                    value: formatPaise(profitToday),
                    change: '${profitTrend.formatted} $comparisonLabel',
                    data: profitHistory,
                    isNegative: profitTrend.isNegative || profitToday < 0,
                    color: profitToday < 0 || profitTrend.isNegative ? const Color(0xFFE53935) : const Color(0xFF00C853))),
          ]),
          const SizedBox(height: 32),

          Text(l10n.text('quick_actions'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            childAspectRatio: 0.84,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _ReferenceAction(Icons.shopping_cart_outlined, l10n.text('sale'), 'New Sale', onQuick, color: const Color(0xFF3F51B5)),
              _ReferenceAction(Icons.shopping_bag_outlined, l10n.text('purchase'), 'Purchase', onQuick, color: const Color(0xFF2E7D32)),
              _ReferenceAction(Icons.account_balance_outlined, l10n.text('gst'), 'GST Center', onQuick, color: const Color(0xFF00897B)),
              _ReferenceAction(Icons.account_balance_wallet_outlined, l10n.text('cash_bank'), 'Cash & Bank', onQuick, color: const Color(0xFF1B5E20)),
              _ReferenceAction(Icons.inventory_2_outlined, l10n.text('item'), 'Product', onQuick, color: const Color(0xFF7B1FA2)),
              _ReferenceAction(Icons.description_outlined, l10n.text('estimate'), 'Estimate', onQuick, color: const Color(0xFF0288D1)),
              _ReferenceAction(Icons.assignment_outlined, l10n.text('order'), 'Sales Order', onQuick, color: const Color(0xFFE65100)),
              _ReferenceAction(Icons.bar_chart_rounded, l10n.text('reports'), 'Reports', onQuick, color: const Color(0xFF5C6BC0)),
            ],
          ),
          const SizedBox(height: 32),

          Row(children: [
            Text(l10n.text('alerts_and_notifications'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: onOpenNotifications,
              child: Row(children: [
                Text(l10n.text('view_all'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3F51B5))),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF3F51B5)),
              ])),
          ]),
          const SizedBox(height: 8),
          _AlertRow(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF44336),
              title: l10n.isHindi ? 'कम स्टॉक: $low सामान' : 'Low Stock: $low products',
              onTap: onShowLowStock),
          const SizedBox(height: 12),
          _AlertRow(
              icon: Icons.access_time_rounded,
              color: const Color(0xFFFFA000),
              title: overdueCount > 0
                  ? (l10n.isHindi
                      ? 'बकाया: ₹${formatPaise(overdueAmount)} ($overdueCount बिल)'
                      : 'Overdue: ₹${formatPaise(overdueAmount)} from $overdueCount invoices')
                  : (l10n.isHindi ? 'बकाया: कोई बकाया नहीं' : 'Overdue: No overdue invoices'),
              onTap: onShowOverdue),
          if (out > 0)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _AlertRow(
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFF44336),
                    title: l10n.isHindi ? 'स्टॉक खत्म: $out सामान' : 'Out of stock: $out products',
                    onTap: onShowOutOfStock)),

          const SizedBox(height: 32),
          Row(children: [
            Text(l10n.text('recent_transactions'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: onViewAllTransactions,
              child: Row(children: [
                Text(l10n.text('view_all'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: StitchColors.primary),
              ])),
          ]),
          const SizedBox(height: 8),
          if (recent == null || recent!.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(l10n.text('no_transactions'),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: StitchColors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                        label: Text(l10n.text('sale')),
                        onPressed: () => onQuick('New Sale'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                        label: Text(l10n.text('purchase')),
                        onPressed: () => onQuick('Purchase'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ...recent!.map((tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DashboardTransactionRow(
                    transaction: tx,
                    onTap: () {
                      if (tx.type == TransactionType.sale && tx.refId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: tx.refId!)),
                        ).then((_) => onRefresh());
                      } else {
                        onViewAllTransactions?.call();
                      }
                    },
                  ),
                )),
        ],
      ),
    );
  }
}

class _DashboardTransactionRow extends StatelessWidget {
  const _DashboardTransactionRow({required this.transaction, required this.onTap});
  final TransactionRecord transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = switch (transaction.type) {
      TransactionType.sale => (Icons.shopping_cart_outlined, const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      TransactionType.purchase => (Icons.shopping_bag_outlined, const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      TransactionType.paymentIn => (Icons.call_received_rounded, const Color(0xFFE0F2F1), const Color(0xFF00695C)),
      TransactionType.paymentOut => (Icons.call_made_rounded, const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      TransactionType.expense => (Icons.receipt_long_outlined, const Color(0xFFF3E5F5), const Color(0xFF7B1FA2)),
      _ => (Icons.description_outlined, const Color(0xFFECEFF1), const Color(0xFF455A64)),
    };

    final isPositive = transaction.isInflow;
    final prefix = isPositive ? '+' : '-';
    final amountColor = isPositive ? StitchColors.success : StitchColors.error;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, color: fg, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.number,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: StitchColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${transaction.partyName ?? transaction.typeLabel} • ${transaction.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$prefix${formatPaise(transaction.amount)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: amountColor),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    transaction.status,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({
    required this.totals,
    required this.amount,
    required this.timeframe,
    required this.onSelectTimeframe,
    this.salesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.purchasesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
    this.expensesTrend = const TrendInfo(percent: 0, isNegative: false, formatted: '0.0%'),
  });
  final Map<String, int>? totals;
  final String Function(int?) amount;
  final String timeframe;
  final ValueChanged<String>? onSelectTimeframe;
  final TrendInfo salesTrend;
  final TrendInfo purchasesTrend;
  final TrendInfo expensesTrend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final timeframeLabel = switch (timeframe) {
      'Today' => l10n.text('today'),
      'This Week' => l10n.text('this_week'),
      'This Month' => l10n.text('this_month'),
      'This Year' => l10n.text('this_year'),
      _ => timeframe,
    };
    final snapshotTitle = timeframe == 'Today'
        ? l10n.text('todays_snapshot')
        : (l10n.isHindi
            ? '$timeframeLabel ${l10n.text('snapshot')}'
            : "$timeframe's ${l10n.text('snapshot')}");

    return Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF3F51B5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3F51B5).withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ]),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(snapshotTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                PopupMenuButton<String>(
                  initialValue: timeframe,
                  tooltip: 'Select timeframe',
                  onSelected: (val) => onSelectTimeframe?.call(val),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: Colors.white,
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'Today', child: Text(l10n.text('today'))),
                    PopupMenuItem(value: 'This Week', child: Text(l10n.text('this_week'))),
                    PopupMenuItem(value: 'This Month', child: Text(l10n.text('this_month'))),
                    PopupMenuItem(value: 'This Year', child: Text(l10n.text('this_year'))),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Text(timeframeLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SnapshotValue(l10n.text('sales'), amount(totals?['salesToday']), salesTrend.formatted, isNegative: salesTrend.isNegative),
                _SnapshotValue(l10n.text('purchases'), amount(totals?['purchasesToday']), purchasesTrend.formatted, isNegative: purchasesTrend.isNegative),
                _SnapshotValue(l10n.text('expenses'), amount(totals?['expensesToday']), expensesTrend.formatted, isNegative: expensesTrend.isNegative),
              ],
            ),
          ],
        ),
      );
  }
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue(this.label, this.value, this.change, {this.isNegative = false});
  final String label, value, change;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    final badgeBg = isNegative
        ? const Color(0xFFFF5252).withValues(alpha: 0.22)
        : const Color(0xFF00E676).withValues(alpha: 0.20);
    final badgeBorder = isNegative
        ? const Color(0xFFFF8A80).withValues(alpha: 0.45)
        : const Color(0xFF69F0AE).withValues(alpha: 0.45);
    final badgeFg = isNegative
        ? const Color(0xFFFF8A80)
        : const Color(0xFF69F0AE);

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeBorder, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: isNegative
                      ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                      : const Color(0xFF00E676).withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNegative ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  size: 13,
                  color: badgeFg,
                ),
                const SizedBox(width: 4),
                Text(
                  change,
                  style: TextStyle(
                    color: badgeFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

class _CashFlowSummaryRow extends StatelessWidget {
  const _CashFlowSummaryRow({
    required this.receivables,
    required this.payables,
    required this.onTapReceivables,
    required this.onTapPayables,
  });

  final ReceivablesSummary? receivables;
  final PayablesSummary? payables;
  final VoidCallback onTapReceivables;
  final VoidCallback onTapPayables;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _CashFlowCard(
            title: l10n.text('to_collect'),
            amount: formatPaise(receivables?.totalReceivable ?? 0),
            subtitle: (receivables?.partyCount ?? 0) > 0
                ? '${receivables!.partyCount} ${l10n.isHindi ? 'पार्टियां' : 'parties'}'
                : (l10n.isHindi ? 'कोई बकाया नहीं' : 'All clear'),
            badgeText: (receivables?.overdueCount ?? 0) > 0
                ? '${receivables!.overdueCount} ${l10n.text('overdue').toLowerCase()}'
                : null,
            icon: Icons.call_received_rounded,
            primaryColor: const Color(0xFF1B8A4C),
            bgColor: const Color(0xFFF1F8F4),
            borderColor: const Color(0xFFA5D6A7),
            onTap: onTapReceivables,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CashFlowCard(
            title: l10n.text('to_pay'),
            amount: formatPaise(payables?.totalPayable ?? 0),
            subtitle: (payables?.partyCount ?? 0) > 0
                ? '${payables!.partyCount} ${l10n.isHindi ? 'सप्लायर' : 'suppliers'}'
                : (l10n.isHindi ? 'कोई देनदारी नहीं' : 'All clear'),
            icon: Icons.call_made_rounded,
            primaryColor: const Color(0xFFC62828),
            bgColor: const Color(0xFFFDF4F4),
            borderColor: const Color(0xFFFFCDD2),
            onTap: onTapPayables,
          ),
        ),
      ],
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.primaryColor,
    required this.bgColor,
    required this.borderColor,
    required this.onTap,
    this.badgeText,
  });

  final String title;
  final String amount;
  final String subtitle;
  final String? badgeText;
  final IconData icon;
  final Color primaryColor;
  final Color bgColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 14, color: primaryColor),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: primaryColor.withValues(alpha: 0.7)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                amount,
                style: TextStyle(
                  color: primaryColor.withValues(alpha: 0.95),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFFCDD2), width: 0.5),
                      ),
                      child: Text(
                        badgeText!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.change,
    required this.color,
    required this.data,
    this.isNegative = false,
  });
  final String label, value, change;
  final Color color;
  final List<double> data;
  final bool isNegative;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: StitchColors.textSecondary))),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Icon(isNegative ? Icons.trending_down_rounded : Icons.trending_up_rounded, color: color, size: 16),
          )
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: StitchColors.textPrimary)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(isNegative ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 10, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(change,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 40, width: double.infinity, child: CustomPaint(painter: _SparklinePainter(color: color, data: data))),
      ]));
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.color, required this.data});
  final Color color;
  final List<double> data;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final effectiveData = data.length == 1 ? [data.first, data.first] : data;
    final path = Path();
    final double stepX = size.width / (effectiveData.length - 1);

    double maxVal = effectiveData.reduce((a, b) => a > b ? a : b);
    double minVal = effectiveData.reduce((a, b) => a < b ? a : b);
    if (maxVal == minVal) {
      if (maxVal == 0) {
        maxVal = 1;
        minVal = 0;
      } else {
        maxVal += 1;
        minVal -= 1;
      }
    }
    final double range = maxVal - minVal;

    for (var i = 0; i < effectiveData.length; i++) {
      final x = i * stepX;
      final y = size.height - ((effectiveData[i] - minVal) / range * size.height * 0.8 + size.height * 0.1);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.data != data;
}

class _ReferenceAction extends StatefulWidget {
  const _ReferenceAction(this.icon, this.label, this.action, this.onTap,
      {required this.color});
  final IconData icon;
  final String label, action;
  final ValueChanged<String> onTap;
  final Color color;

  @override
  State<_ReferenceAction> createState() => _ReferenceActionState();
}

class _ReferenceActionState extends State<_ReferenceAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: _isHovered ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? color.withValues(alpha: 0.55)
                : StitchColors.outline.withValues(alpha: 0.7),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? color.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: _isHovered ? 12 : 4,
              offset: Offset(0, _isHovered ? 5 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onTap(widget.action),
            borderRadius: BorderRadius.circular(16),
            splashColor: color.withValues(alpha: 0.15),
            highlightColor: color.withValues(alpha: 0.08),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: _isHovered ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: _isHovered ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: color, size: 24),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _isHovered ? color : StitchColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon,
    required this.color,
    required this.title,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StitchColors.outline.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 16),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: StitchColors.textPrimary))),
            const Text('View',
                style: TextStyle(
                    color: Color(0xFF3F51B5),
                    fontSize: 13,
                    fontWeight: FontWeight.w800))
          ])));
}

class _NotificationItemTile extends StatelessWidget {
  const _NotificationItemTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: StitchColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
