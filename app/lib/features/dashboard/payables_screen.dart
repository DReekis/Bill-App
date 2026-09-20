import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../payments/payment_form.dart';
import '../suppliers/supplier_detail_screen.dart';

class PayablesScreen extends StatefulWidget {
  const PayablesScreen({super.key});

  @override
  State<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends State<PayablesScreen> {
  PayablesSummary? summary;
  bool loading = true;
  String query = '';

  final searchController = TextEditingController();

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    setState(() => loading = true);
    final res = await Repository.instance.payablesSummary(businessId);
    if (!mounted) return;
    setState(() {
      summary = res;
      loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String? phone, String supplierName) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = clean.length == 10 ? '91$clean' : clean;
    final message = 'Hello $supplierName,\nRegarding our pending account balance with you.';
    final uri = Uri.parse('https://wa.me/$formatted?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allItems = summary?.items ?? const <PartyPayable>[];

    final filtered = query.trim().isEmpty
        ? allItems
        : allItems.where((item) {
            final q = query.toLowerCase();
            final matchName = item.supplierName.toLowerCase().contains(q);
            final matchPhone = (item.phone ?? '').contains(q);
            return matchName || matchPhone;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('you_will_pay')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                // Top Hero Card
                _PayablesHero(
                  totalPayable: summary?.totalPayable ?? 0,
                  partyCount: summary?.partyCount ?? 0,
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: searchController,
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: l10n.isHindi ? 'सप्लायर खोजें' : 'Search supplier or phone...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                searchController.clear();
                                setState(() => query = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),

                // List of Creditors / Suppliers
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(32),
                          children: [
                            AppEmptyState(
                              icon: Icons.check_circle_outline_rounded,
                              title: l10n.text('no_payables'),
                              subtitle: l10n.text('no_payables_desc'),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final item = filtered[i];
                            return _CreditorCard(
                              item: item,
                              onRecordPayment: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PaymentFormScreen(
                                      partyType: 'supplier',
                                      partyId: item.supplierId,
                                      partyName: item.supplierName,
                                      initialAmount: item.balance,
                                    ),
                                  ),
                                );
                                _load();
                              },
                              onCall: () => _makeCall(item.phone),
                              onWhatsApp: () => _openWhatsApp(item.whatsapp ?? item.phone, item.supplierName),
                              onTapSupplier: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SupplierDetailScreen(supplierId: item.supplierId),
                                  ),
                                ).then((_) => _load());
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _PayablesHero extends StatelessWidget {
  const _PayablesHero({
    required this.totalPayable,
    required this.partyCount,
  });

  final int totalPayable;
  final int partyCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8C1D18), Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC62828).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.text('to_pay').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$partyCount ${l10n.isHindi ? 'सप्लायर' : 'Suppliers'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatPaise(totalPayable),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.isHindi ? 'कुल बकाया जो आपको चुकाना है' : 'Total outstanding balance owed to suppliers',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditorCard extends StatelessWidget {
  const _CreditorCard({
    required this.item,
    required this.onRecordPayment,
    required this.onCall,
    required this.onWhatsApp,
    required this.onTapSupplier,
  });

  final PartyPayable item;
  final VoidCallback onRecordPayment;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onTapSupplier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: StitchColors.outline.withValues(alpha: 0.6),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main Info Row
          InkWell(
            onTap: onTapSupplier,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  InitialsAvatar(item.supplierName, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.supplierName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (item.phone != null && item.phone!.isNotEmpty) ...[
                              Icon(Icons.phone_outlined, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                item.phone!,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ] else
                              Text(
                                l10n.isHindi ? 'कोई फोन नहीं' : 'No contact saved',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatPaise(item.balance),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFC62828),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.text('to_pay'),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1, indent: 14, endIndent: 14),

          // Actions Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                if (item.phone != null && item.phone!.isNotEmpty) ...[
                  IconButton(
                    onPressed: onCall,
                    tooltip: l10n.text('call'),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onWhatsApp,
                    tooltip: 'WhatsApp',
                    icon: const Icon(Icons.chat_outlined, size: 18, color: Color(0xFF25D366)),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F5E9),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRecordPayment,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.payment_rounded, size: 16),
                    label: Text(
                      l10n.text('pay_now'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
}
