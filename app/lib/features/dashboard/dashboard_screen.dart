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
import '../suppliers/supplier_form.dart';
import '../search/search_screen.dart';
import '../reports/reports_menu_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int>? totals;
  List<Invoice>? recent;
  Business? business;
  List<double> salesHistory = [];
  List<double> profitHistory = [];
  int low = 0;
  int out = 0;

  Future<void> _load() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;
    final repo = Repository.instance;
    final map = await repo.dashboardTotals(businessId);
    final allInvoices = await repo.invoices(businessId);
    final biz = await repo.getBusiness(businessId);
    final lowCount = await repo.lowStockCount(businessId);
    final outCount = await repo.outOfStockCount(businessId);
    final sHist = await repo.dailyPerformance(businessId, 'sales', days: 7);
    final pHist = await repo.dailyPerformance(businessId, 'profit', days: 7);

    await SyncEngine.instance.refreshPending();
    if (!mounted) return;
    setState(() {
      totals = map;
      recent = allInvoices.take(6).toList();
      business = biz;
      low = lowCount;
      out = outCount;
      salesHistory = sHist;
      profitHistory = pHist;
    });
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
    switch (action) {
      case 'New Sale':
        nav
            .push(
                MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()))
            .then((_) => _load());
      case 'Payment In':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'customer')))
            .then((_) => _load());
      case 'Payment Out':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PaymentFormScreen(partyType: 'supplier')))
            .then((_) => _load());
      case 'Purchase':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PurchaseBuilderScreen()))
            .then((_) => _load());
      case 'Estimate':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const QuotationBuilderScreen()))
            .then((_) => _load());
      case 'Sales Order':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const SalesOrderBuilderScreen()))
            .then((_) => _load());
      case 'Purchase Order':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const PurchaseOrderBuilderScreen()))
            .then((_) => _load());
      case 'Challan':
        nav
            .push(MaterialPageRoute(
                builder: (_) => const DeliveryChallanBuilderScreen()))
            .then((_) => _load());
      case 'Reports':
        nav.push(MaterialPageRoute(builder: (_) => const ReportsMenuScreen()));
      default:
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => switch (action) {
                  'Customer' =>
                    CustomerFormSheet(onSaved: _load, businessId: businessId),
                  'Supplier' =>
                    SupplierFormSheet(onSaved: _load, businessId: businessId),
                  'Product' => ProductFormSheet(
                      onSaved: _load,
                      businessId: businessId,
                      onSavedProduct: (_) {}),
                  'Expense' =>
                    ExpenseFormSheet(onSaved: _load, businessId: businessId),
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
        salesHistory: salesHistory,
        profitHistory: profitHistory,
        onQuick: _quick,
        onRefresh: _load,
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
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _actionItem(context, Icons.shopping_cart_outlined, 'Sale', 'New Sale'),
            _actionItem(context, Icons.shopping_bag_outlined, 'Purchase', 'Purchase'),
            _actionItem(context, Icons.description_outlined, 'Estimate', 'Estimate'),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _actionItem(context, Icons.assignment_outlined, 'Order', 'Sales Order'),
            _actionItem(context, Icons.local_shipping_outlined, 'Challan', 'Challan'),
            _actionItem(context, Icons.person_add_outlined, 'Customer', 'Customer'),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _actionItem(context, Icons.inventory_2_outlined, 'Product', 'Product'),
            _actionItem(context, Icons.payments_outlined, 'Payment In', 'Payment In'),
            _actionItem(context, Icons.outbox_outlined, 'Payment Out', 'Payment Out'),
          ]),
        ]),
      ),
    );
  }

  Widget _actionItem(BuildContext context, IconData icon, String label, String action) => InkWell(
        onTap: () {
          Navigator.pop(context);
          _quick(action);
        },
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: StitchColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: StitchColors.primary),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _ReferenceDashboard extends StatelessWidget {
  const _ReferenceDashboard({
    required this.business,
    required this.totals,
    required this.profitToday,
    required this.low,
    required this.out,
    required this.salesHistory,
    required this.profitHistory,
    required this.onQuick,
    required this.onRefresh,
  });

  final Business? business;
  final Map<String, int>? totals;
  final int profitToday;
  final int low;
  final int out;
  final List<double> salesHistory;
  final List<double> profitHistory;
  final ValueChanged<String> onQuick;
  final Future<void> Function() onRefresh;

  String amount(int? value) => value == null ? '₹0' : formatPaise(value);

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
    final t = totals;
    final name = business?.ownerName?.split(' ').first ?? 'Rahul';
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          Row(children: [
            const Icon(Icons.menu_rounded, size: 28, color: StitchColors.textPrimary),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 28,
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
                const Text('Smart Billing. Better Business.',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
              ],
            ),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                icon: const Icon(Icons.search_rounded, size: 26, color: StitchColors.textPrimary)),
            Stack(children: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded, size: 26, color: StitchColors.textPrimary)),
              Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: StitchColors.error, shape: BoxShape.circle),
                    child: const Text('3',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  )),
            ]),
            const SizedBox(width: 4),
            const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF3F51B5),
                child: Text('R',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
          ]),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good morning, $name 👋',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    const Text("Here's your business summary",
                        style: TextStyle(fontSize: 14, color: StitchColors.textSecondary, fontWeight: FontWeight.w500)),
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
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _Snapshot(totals: t, amount: amount),
          const SizedBox(height: 32),

          const Text('Business Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _OverviewCard(
                    label: 'Revenue',
                    value: formatPaise(totals?['taxableToday'] ?? 0),
                    change: '7-day trend',
                    data: salesHistory,
                    color: const Color(0xFF00C853))),
            const SizedBox(width: 16),
            Expanded(
                child: _OverviewCard(
                    label: 'Net Profit',
                    value: formatPaise(profitToday),
                    change: '7-day trend',
                    data: profitHistory,
                    color: const Color(0xFF00C853))),
          ]),
          const SizedBox(height: 32),

          const Text('Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            childAspectRatio: 0.88,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _ReferenceAction(Icons.shopping_cart_outlined, 'Create Sale', 'New Sale', onQuick, primary: true),
              _ReferenceAction(Icons.shopping_bag_outlined, 'Add Purchase', 'Purchase', onQuick),
              _ReferenceAction(Icons.inventory_2_outlined, 'Add Product', 'Product', onQuick),
              _ReferenceAction(Icons.description_outlined, 'Estimate', 'Estimate', onQuick),
              _ReferenceAction(Icons.assignment_outlined, 'Sales Order', 'Sales Order', onQuick),
              _ReferenceAction(Icons.local_shipping_outlined, 'Challan', 'Challan', onQuick),
              _ReferenceAction(Icons.list_alt_outlined, 'Orders', 'Reports', onQuick), // Reusing Reports for now or adding a specific one
              _ReferenceAction(Icons.grid_view_rounded, 'More', 'More', onQuick),
            ],
          ),
          const SizedBox(height: 32),

          Row(children: [
            const Text('Alerts & Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: () {},
              child: const Row(children: [
                Text('View All', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3F51B5))),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF3F51B5)),
              ])),
          ]),
          const SizedBox(height: 8),
          _AlertRow(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF44336),
              title: 'Low Stock: $low products'),
          const SizedBox(height: 12),
          const _AlertRow(
              icon: Icons.access_time_rounded,
              color: Color(0xFFFFA000),
              title: 'Overdue: ₹42,500 from 5 invoices'),
          if (out > 0)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _AlertRow(
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFF44336),
                    title: 'Out of stock: $out products')),
        ],
      ),
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.totals, required this.amount});
  final Map<String, int>? totals;
  final String Function(int?) amount;

  @override
  Widget build(BuildContext context) => Container(
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
                const Text("Today's Snapshot",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Text('Today', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SnapshotValue('Sales', amount(totals?['salesToday']), '12.4%', color: const Color(0xFF4CAF50)),
                _SnapshotValue('Purchases', amount(totals?['purchasesToday']), '8.6%', color: const Color(0xFF4CAF50)),
                _SnapshotValue('Expenses', amount(totals?['expensesToday']), '3.2%', color: const Color(0xFFFF5252), isNegative: true),
              ],
            ),
          ],
        ),
      );
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue(this.label, this.value, this.change, {required this.color, this.isNegative = false});
  final String label, value, change;
  final Color color;
  final bool isNegative;

  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isNegative ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 10, color: color),
                const SizedBox(width: 4),
                Text(change,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ],
            )),
      ]));
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard(
      {required this.label, required this.value, required this.change, required this.color, required this.data});
  final String label, value, change;
  final Color color;
  final List<double> data;

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
            child: Icon(Icons.trending_up_rounded, color: color, size: 16),
          )
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: StitchColors.textPrimary)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.arrow_upward_rounded, size: 10, color: color),
          const SizedBox(width: 4),
          Text(change,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
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

    final path = Path();
    final double stepX = size.width / (data.length - 1);

    double maxVal = data.reduce((a, b) => a > b ? a : b);
    double minVal = data.reduce((a, b) => a < b ? a : b);
    if (maxVal == minVal) {
      maxVal += 1;
      minVal -= 1;
    }
    final double range = maxVal - minVal;

    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range * size.height * 0.8 + size.height * 0.1);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ReferenceAction extends StatelessWidget {
  const _ReferenceAction(this.icon, this.label, this.action, this.onTap,
      {this.primary = false});
  final IconData icon;
  final String label, action;
  final ValueChanged<String> onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => onTap(action),
      borderRadius: BorderRadius.circular(16),
      child: Container(
          decoration: BoxDecoration(
              color: primary ? const Color(0xFF3F51B5) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary ? const Color(0xFF3F51B5) : StitchColors.outline.withValues(alpha: 0.7)),
              boxShadow: [
                if (!primary) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ]),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                color: primary ? Colors.white : const Color(0xFF3F51B5), size: 28),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary ? Colors.white : StitchColors.textPrimary))
          ])));
}

class _AlertRow extends StatelessWidget {
  const _AlertRow(
      {required this.icon, required this.color, required this.title});
  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
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
      ]));
}
