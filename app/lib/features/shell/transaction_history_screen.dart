import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../purchases/purchase_order_detail_screen.dart';
import '../sales/delivery_challan_detail_screen.dart';
import '../sales/quotation_detail_screen.dart';
import '../sales/sales_order_detail_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Quotation>? quotations;
  List<SalesOrder>? salesOrders;
  List<PurchaseOrder>? purchaseOrders;
  List<DeliveryChallan>? challans;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    final repo = Repository.instance;
    final q = await repo.quotations(bizId);
    final so = await repo.allSalesOrders(bizId);
    final po = await repo.allPurchaseOrders(bizId);
    final dc = await repo.allDeliveryChallans(bizId);
    setState(() {
      quotations = q;
      salesOrders = so;
      purchaseOrders = po;
      challans = dc;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders & Quotations', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Quotations'),
            Tab(text: 'Sales Orders'),
            Tab(text: 'Purchase Orders'),
            Tab(text: 'Challans'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _List(items: quotations, onConvert: _convertQuotation),
          _List(items: salesOrders, onConvert: _convertSalesOrder),
          _List(items: purchaseOrders, onConvert: _convertPurchaseOrder),
          _List(items: challans, onConvert: _convertChallan),
        ],
      ),
    );
  }

  Future<void> _convertQuotation(dynamic item) async {
    final q = item as Quotation;
    try {
      final invoiceId = await Repository.instance.convertQuotationToInvoice(q.id!);
      if (mounted) {
        showAppMessage(context, 'Quotation ${q.number} converted to Invoice #$invoiceId');
        _load();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    }
  }

  Future<void> _convertSalesOrder(dynamic item) async {
    final so = item as SalesOrder;
    try {
      final invoiceId = await Repository.instance.convertSalesOrderToInvoice(so.id!);
      if (mounted) {
        showAppMessage(context, 'Sales Order ${so.number} converted to Invoice #$invoiceId');
        _load();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    }
  }

  Future<void> _convertChallan(dynamic item) async {
    final dc = item as DeliveryChallan;
    try {
      final invoiceId = await Repository.instance.convertDeliveryChallanToInvoice(dc.id!);
      if (mounted) {
        showAppMessage(context, 'Challan ${dc.number} converted to Invoice #$invoiceId');
        _load();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    }
  }

  Future<void> _convertPurchaseOrder(dynamic item) async {
    final po = item as PurchaseOrder;
    try {
      final purchaseId = await Repository.instance.convertPurchaseOrderToPurchase(po.id!);
      if (mounted) {
        showAppMessage(context, 'Purchase Order ${po.number} converted to Purchase #$purchaseId');
        _load();
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Conversion failed: $e', error: true);
    }
  }
}

class _List extends StatelessWidget {
  const _List({required this.items, this.onConvert});
  final List<dynamic>? items;
  final Function(dynamic)? onConvert;

  @override
  Widget build(BuildContext context) {
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items!.isEmpty) return const Center(child: Text('No entries found'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items![index];
        return Card(
          child: ListTile(
            title: Text(item.number, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item.date} • ${item.status}'),
            trailing: onConvert != null && item.status != 'Converted'
                ? TextButton(onPressed: () => onConvert!(item), child: const Text('Convert'))
                : null,
            onTap: () {
              if (item is Quotation && item.id != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => QuotationDetailScreen(quotationId: item.id!)));
              } else if (item is SalesOrder && item.id != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => SalesOrderDetailScreen(orderId: item.id!)));
              } else if (item is PurchaseOrder && item.id != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseOrderDetailScreen(orderId: item.id!)));
              } else if (item is DeliveryChallan && item.id != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryChallanDetailScreen(challanId: item.id!)));
              }
            },
          ),
        );
      },
    );
  }
}



void showAppMessage(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red : null,
  ));
}
