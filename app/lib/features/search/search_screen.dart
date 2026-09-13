import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../sales/invoice_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _search = TextEditingController();
  List<SearchResult> results = [];
  bool searching = false;

  void _doSearch(String q) async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => searching = true);
    final res = await Repository.instance.globalSearch(bizId, q);
    setState(() {
      results = res;
      searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search customers, products, invoices...', border: InputBorder.none),
          onChanged: _doSearch,
        ),
      ),
      body: searching
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(
                  leading: Icon(switch (r.type) {
                    'customer' => Icons.person_outline,
                    'product' => Icons.inventory_2_outline,
                    'invoice' => Icons.receipt_long_outline,
                    _ => Icons.search,
                  }),
                  title: Text(r.title),
                  subtitle: r.subtitle != null ? Text(r.subtitle!) : null,
                  trailing: r.amount != null ? Text(formatPaise(r.amount!)) : null,
                  onTap: () {
                    if (r.type == 'invoice') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: r.id)));
                    }
                  },
                );
              },
            ),
    );
  }
}
