import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/app_database.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import 'package:provider/provider.dart';

class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});

  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  List<LedgerEntry>? entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    final db = await Repository.instance.allLedger(bizId);
    setState(() => entries = db);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day Book', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries!.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: StitchColors.outline),
                  itemBuilder: (context, index) {
                    final e = entries![index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      title: Text(e.note ?? 'Transaction', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${e.date} • ${e.account}', style: const TextStyle(fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (e.debit > 0)
                            Text('Dr ${formatPaise(e.debit)}', style: const TextStyle(color: StitchColors.error, fontWeight: FontWeight.w800, fontSize: 14)),
                          if (e.credit > 0)
                            Text('Cr ${formatPaise(e.credit)}', style: const TextStyle(color: StitchColors.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

extension on Repository {
  Future<List<LedgerEntry>> allLedger(int businessId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('ledger',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(LedgerEntry.fromMap).toList();
  }
}
