import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/pdf_invoice.dart';
import '../purchases/purchase_order_builder_screen.dart';
import '../purchases/purchase_order_detail_screen.dart';
import '../sales/sales_order_builder_screen.dart';
import '../sales/sales_order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.initialTab = 0});

  /// 0 for Sale Orders, 1 for Purchase Orders
  final int initialTab;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SalesOrder>? _salesOrders;
  List<PurchaseOrder>? _purchaseOrders;
  Business? _business;
  bool _loading = true;

  String _searchQuery = '';
  String _selectedStatus = 'all'; // all, open, converted, cancelled

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final repo = Repository.instance;

    final so = await repo.allSalesOrders(bizId);
    final po = await repo.allPurchaseOrders(bizId);
    final biz = await repo.getBusiness(bizId);

    if (!mounted) return;
    setState(() {
      _salesOrders = so;
      _purchaseOrders = po;
      _business = biz;
      _loading = false;
    });
  }

  List<SalesOrder> get _filteredSalesOrders {
    if (_salesOrders == null) return [];
    return _salesOrders!.where((o) {
      final matchesQuery = _searchQuery.isEmpty ||
          o.number.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (o.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final statusLower = o.status.toLowerCase();
      final matchesStatus = _selectedStatus == 'all' ||
          (_selectedStatus == 'open' && statusLower != 'converted' && statusLower != 'cancelled') ||
          (_selectedStatus == 'converted' && statusLower == 'converted') ||
          (_selectedStatus == 'cancelled' && statusLower == 'cancelled');
      return matchesQuery && matchesStatus;
    }).toList();
  }

  List<PurchaseOrder> get _filteredPurchaseOrders {
    if (_purchaseOrders == null) return [];
    return _purchaseOrders!.where((o) {
      final matchesQuery = _searchQuery.isEmpty ||
          o.number.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (o.supplierName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final statusLower = o.status.toLowerCase();
      final matchesStatus = _selectedStatus == 'all' ||
          (_selectedStatus == 'open' && statusLower != 'converted' && statusLower != 'cancelled') ||
          (_selectedStatus == 'converted' && statusLower == 'converted') ||
          (_selectedStatus == 'cancelled' && statusLower == 'cancelled');
      return matchesQuery && matchesStatus;
    }).toList();
  }

  void _openCreateOrderSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Select Order Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Choose whether to create a client sale order or a vendor purchase order',
                  style: TextStyle(fontSize: 12.5, color: StitchColors.textSecondary)),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5E35B1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_outlined, color: Color(0xFF5E35B1), size: 24),
                ),
                title: const Text('New Sale Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text('Record booking orders received from clients / customers',
                    style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SalesOrderBuilderScreen()),
                  ).then((_) => _load());
                },
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00838F).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF00838F), size: 24),
                ),
                title: const Text('New Purchase Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text('Issue purchase orders to suppliers & track incoming stock',
                    style: TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PurchaseOrderBuilderScreen()),
                  ).then((_) => _load());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaleOrderTab = _tabController.index == 0;

    // KPI Metrics calculation
    final currentList = isSaleOrderTab ? (_salesOrders ?? []) : (_purchaseOrders ?? []);
    final totalCount = currentList.length;
    final totalAmount = isSaleOrderTab
        ? (_salesOrders?.fold<int>(0, (sum, o) => sum + o.total) ?? 0)
        : (_purchaseOrders?.fold<int>(0, (sum, o) => sum + o.total) ?? 0);
    final openCount = isSaleOrderTab
        ? (_salesOrders?.where((o) => o.status.toLowerCase() != 'converted' && o.status.toLowerCase() != 'cancelled').length ?? 0)
        : (_purchaseOrders?.where((o) => o.status.toLowerCase() != 'converted' && o.status.toLowerCase() != 'cancelled').length ?? 0);

    return Scaffold(
      backgroundColor: StitchColors.surface,
      appBar: AppBar(
        title: const Text('Orders Hub', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create Order',
            onPressed: _openCreateOrderSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: StitchColors.primary,
              unselectedLabelColor: StitchColors.textSecondary,
              indicatorColor: StitchColors.primary,
              indicatorWeight: 3,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('Sale Orders (${_salesOrders?.length ?? 0})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('Purchase Orders (${_purchaseOrders?.length ?? 0})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                // KPI Banner
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _kpiCard(
                          label: 'Total Orders',
                          value: '$totalCount',
                          color: isSaleOrderTab ? const Color(0xFF5E35B1) : const Color(0xFF00838F),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _kpiCard(
                          label: 'Total Value',
                          value: formatPaise(totalAmount),
                          color: StitchColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _kpiCard(
                          label: 'Open / Pending',
                          value: '$openCount',
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search & Filter Bar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: isSaleOrderTab ? 'Search order # or customer...' : 'Search order # or supplier...',
                          hintStyle: const TextStyle(fontSize: 13, color: StitchColors.textTertiary),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('all', 'All'),
                            const SizedBox(width: 8),
                            _filterChip('open', 'Open / Pending'),
                            const SizedBox(width: 8),
                            _filterChip('converted', 'Converted'),
                            const SizedBox(width: 8),
                            _filterChip('cancelled', 'Cancelled'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // 1. Sale Orders List
                      _buildSalesOrderList(),

                      // 2. Purchase Orders List
                      _buildPurchaseOrderList(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (isSaleOrderTab) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesOrderBuilderScreen()),
            ).then((_) => _load());
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseOrderBuilderScreen()),
            ).then((_) => _load());
          }
        },
        backgroundColor: isSaleOrderTab ? const Color(0xFF5E35B1) : const Color(0xFF00838F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          isSaleOrderTab ? 'New Sale Order' : 'New Purchase Order',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _kpiCard({required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String id, String label) {
    final selected = _selectedStatus == id;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : StitchColors.textSecondary,
      ),
      selected: selected,
      selectedColor: StitchColors.primary,
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      onSelected: (_) => setState(() => _selectedStatus = id),
    );
  }

  Widget _buildSalesOrderList() {
    final list = _filteredSalesOrders;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.assignment_outlined, size: 36, color: StitchColors.textTertiary),
              ),
              const SizedBox(height: 14),
              const Text('No Sale Orders Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Create booking orders for your customers to track reservations and draft deliveries.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5E35B1)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SalesOrderBuilderScreen()),
                  ).then((_) => _load());
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Sale Order'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final o = list[index];
        final isConverted = o.status.toLowerCase() == 'converted';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          elevation: 0,
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SalesOrderDetailScreen(orderId: o.id!)),
              ).then((_) => _load());
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(o.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isConverted ? StitchColors.successSoft : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              o.status,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isConverted ? StitchColors.success : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formatPaise(o.total),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StitchColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 16, color: StitchColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          o.customerName ?? 'Walk-in Client',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: StitchColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        displayDate(o.date),
                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                      ),
                      if (o.dueDate != null && o.dueDate!.isNotEmpty) ...[
                        const Text('  •  ', style: TextStyle(color: StitchColors.textTertiary)),
                        Text(
                          'Delivery Due: ${displayDate(o.dueDate!)}',
                          style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  if (o.lines.isNotEmpty) ...[
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${o.lines.length} items (${o.lines.first.name}${o.lines.length > 1 ? ' + ${o.lines.length - 1} more' : ''})',
                          style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share_outlined, size: 18),
                              tooltip: 'Share Order',
                              onPressed: () async {
                                if (_business != null) {
                                  await shareSalesOrder(business: _business!, order: o);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.print_outlined, size: 18),
                              tooltip: 'Print Order',
                              onPressed: () async {
                                if (_business != null) {
                                  await printSalesOrder(business: _business!, order: o);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPurchaseOrderList() {
    final list = _filteredPurchaseOrders;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.inventory_2_outlined, size: 36, color: StitchColors.textTertiary),
              ),
              const SizedBox(height: 14),
              const Text('No Purchase Orders Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Issue purchase orders to your vendors to order new inventory and lock in supplier pricing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00838F)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PurchaseOrderBuilderScreen()),
                  ).then((_) => _load());
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Purchase Order'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final po = list[index];
        final isConverted = po.status.toLowerCase() == 'converted';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          elevation: 0,
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PurchaseOrderDetailScreen(orderId: po.id!)),
              ).then((_) => _load());
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(po.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isConverted ? StitchColors.successSoft : const Color(0xFFE0F7FA),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              po.status,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isConverted ? StitchColors.success : const Color(0xFF00695C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formatPaise(po.total),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF00838F)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 16, color: StitchColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          po.supplierName ?? 'Direct Vendor',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: StitchColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        displayDate(po.date),
                        style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                      ),
                      if (po.expectedDate != null && po.expectedDate!.isNotEmpty) ...[
                        const Text('  •  ', style: TextStyle(color: StitchColors.textTertiary)),
                        Text(
                          'Expected: ${displayDate(po.expectedDate!)}',
                          style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  if (po.lines.isNotEmpty) ...[
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${po.lines.length} items (${po.lines.first.name}${po.lines.length > 1 ? ' + ${po.lines.length - 1} more' : ''})',
                          style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share_outlined, size: 18),
                              tooltip: 'Share PO',
                              onPressed: () async {
                                if (_business != null) {
                                  await sharePurchaseOrder(business: _business!, order: po);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.print_outlined, size: 18),
                              tooltip: 'Print PO',
                              onPressed: () async {
                                if (_business != null) {
                                  await printPurchaseOrder(business: _business!, order: po);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
