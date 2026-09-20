import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../customers/customer_detail_screen.dart';
import '../payments/payment_form.dart';

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  ReceivablesSummary? summary;
  bool loading = true;
  String query = '';
  int filterIndex = 0; // 0: All, 1: Overdue, 2: Due Soon

  final searchController = TextEditingController();

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    setState(() => loading = true);
    final res = await Repository.instance.receivablesSummary(businessId);
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

  Future<void> _sendReminder(PartyReceivable item, {bool forceShare = false}) async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final business = await Repository.instance.getBusiness(businessId);
    final bizName = business?.name ?? 'Our Business';
    final upiId = business?.upiId;

    final buffer = StringBuffer();
    buffer.writeln('Dear ${item.customerName},');
    buffer.writeln();
    buffer.writeln('This is a gentle payment reminder from *$bizName*.');
    buffer.writeln('Your total outstanding balance is *${formatPaise(item.balance)}*.');

    if (item.pendingInvoices.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Pending Invoices:');
      for (final inv in item.pendingInvoices) {
        final dueText = inv.dueDate != null && inv.dueDate!.isNotEmpty ? ' (Due: ${inv.dueDate})' : '';
        final overdueText = inv.isOverdue ? ' [${inv.overdueDays} days overdue]' : '';
        buffer.writeln('• #${inv.invoiceNumber}: ${formatPaise(inv.pendingAmount)}$dueText$overdueText');
      }
    }

    if (upiId != null && upiId.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Kindly clear the payment via UPI:');
      buffer.writeln('UPI ID: $upiId');
      final upiLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(bizName)}&am=${(item.balance / 100).toStringAsFixed(2)}&cu=INR';
      buffer.writeln('Pay Link: $upiLink');
    }

    buffer.writeln();
    buffer.writeln('Thank you for your business!');

    final message = buffer.toString();
    final phone = (item.whatsapp != null && item.whatsapp!.isNotEmpty)
        ? item.whatsapp!
        : (item.phone ?? '');

    if (!forceShare && phone.isNotEmpty) {
      final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final formatted = clean.length == 10 ? '91$clean' : clean;
      final uri = Uri.parse('https://wa.me/$formatted?text=${Uri.encodeComponent(message)}');
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // Fallback or explicit share
    await Share.share(message, subject: 'Payment Reminder - $bizName');
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allItems = summary?.items ?? const <PartyReceivable>[];

    // Filter items
    final filtered = allItems.where((item) {
      if (query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        final matchName = item.customerName.toLowerCase().contains(q);
        final matchPhone = (item.phone ?? '').contains(q);
        final matchInv = item.pendingInvoices.any((i) => i.invoiceNumber.toLowerCase().contains(q));
        if (!matchName && !matchPhone && !matchInv) return false;
      }

      if (filterIndex == 1) {
        // Overdue
        return item.maxOverdueDays > 0;
      } else if (filterIndex == 2) {
        // Due Soon (has pending invoices that aren't overdue yet)
        return item.pendingInvoices.any((i) => !i.isOverdue);
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('you_will_receive')),
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
                _ReceivablesHero(
                  totalReceivable: summary?.totalReceivable ?? 0,
                  partyCount: summary?.partyCount ?? 0,
                  overdueAmount: summary?.overdueAmount ?? 0,
                  overdueCount: summary?.overdueCount ?? 0,
                ),

                // Search & Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: (v) => setState(() => query = v),
                          decoration: InputDecoration(
                            hintText: l10n.isHindi ? 'ग्राहक या बिल खोजें' : 'Search customer or bill...',
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
                    ],
                  ),
                ),

                // Filter Tabs (All, Overdue, Due Soon)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: '${l10n.isHindi ? 'सभी' : 'All'} (${allItems.length})',
                        selected: filterIndex == 0,
                        onTap: () => setState(() => filterIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '${l10n.text('overdue')} (${summary?.overdueCount ?? 0})',
                        selected: filterIndex == 1,
                        color: Colors.red.shade700,
                        onTap: () => setState(() => filterIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: l10n.isHindi ? 'जल्द देय' : 'Due Soon',
                        selected: filterIndex == 2,
                        onTap: () => setState(() => filterIndex = 2),
                      ),
                    ],
                  ),
                ),

                // List of Debtors
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(32),
                          children: [
                            AppEmptyState(
                              icon: Icons.check_circle_outline_rounded,
                              title: l10n.text('no_receivables'),
                              subtitle: l10n.text('no_receivables_desc'),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final item = filtered[i];
                            return _DebtorCard(
                              item: item,
                              onSendReminder: () => _sendReminder(item),
                              onShareReminder: () => _sendReminder(item, forceShare: true),
                              onRecordPayment: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PaymentFormScreen(
                                      partyType: 'customer',
                                      partyId: item.customerId > 0 ? item.customerId : null,
                                      partyName: item.customerName,
                                      initialAmount: item.balance,
                                    ),
                                  ),
                                );
                                _load();
                              },
                              onCall: () => _makeCall(item.phone),
                              onTapCustomer: () {
                                if (item.customerId > 0) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CustomerDetailScreen(customerId: item.customerId),
                                    ),
                                  ).then((_) => _load());
                                }
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

class _ReceivablesHero extends StatelessWidget {
  const _ReceivablesHero({
    required this.totalReceivable,
    required this.partyCount,
    required this.overdueAmount,
    required this.overdueCount,
  });

  final int totalReceivable;
  final int partyCount;
  final int overdueAmount;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D532B), Color(0xFF1B8A4C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B8A4C).withValues(alpha: 0.25),
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
                    child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.text('to_collect').toUpperCase(),
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
                  '$partyCount ${l10n.isHindi ? 'पार्टियां' : 'Parties'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatPaise(totalReceivable),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          if (overdueAmount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF8A80).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFF8A80)),
                  const SizedBox(width: 6),
                  Text(
                    '${formatPaise(overdueAmount)} ${l10n.text('overdue').toLowerCase()} ($overdueCount ${l10n.isHindi ? 'पार्टियां' : 'parties'})',
                    style: const TextStyle(
                      color: Color(0xFFFFEBEE),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? StitchColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : activeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : activeColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : activeColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DebtorCard extends StatefulWidget {
  const _DebtorCard({
    required this.item,
    required this.onSendReminder,
    required this.onShareReminder,
    required this.onRecordPayment,
    required this.onCall,
    required this.onTapCustomer,
  });

  final PartyReceivable item;
  final VoidCallback onSendReminder;
  final VoidCallback onShareReminder;
  final VoidCallback onRecordPayment;
  final VoidCallback onCall;
  final VoidCallback onTapCustomer;

  @override
  State<_DebtorCard> createState() => _DebtorCardState();
}

class _DebtorCardState extends State<_DebtorCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = widget.item;
    final hasOverdue = item.maxOverdueDays > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOverdue
              ? const Color(0xFFFFCDD2)
              : StitchColors.outline.withValues(alpha: 0.6),
          width: hasOverdue ? 1.2 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: hasOverdue
                ? const Color(0xFFFF5252).withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main Info Row
          InkWell(
            onTap: widget.onTapCustomer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InitialsAvatar(item.customerName, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.customerName,
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
                        if (hasOverdue) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.maxOverdueDays} ${l10n.isHindi ? 'दिन बकाया' : 'days overdue'}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC62828),
                              ),
                            ),
                          ),
                        ],
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
                          color: Color(0xFF1B8A4C),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.text('to_collect'),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Invoices Dropdown Toggle
          if (item.pendingInvoices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${item.pendingInvoices.length} ${l10n.text('pending_bills')}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: StitchColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: StitchColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: item.pendingInvoices.map((inv) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.receipt_outlined, size: 14, color: StitchColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                '#${inv.invoiceNumber}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              if (inv.isOverdue) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${inv.overdueDays}d',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.red.shade900),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            formatPaise(inv.pendingAmount),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],

          const Divider(height: 1, indent: 14, endIndent: 14),

          // Action Buttons Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                // 1-Tap WhatsApp Reminder
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onSendReminder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.chat_outlined, size: 16),
                    label: Text(
                      l10n.isHindi ? 'व्हाट्सएप' : 'WhatsApp',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Share Sheet Reminder
                IconButton(
                  onPressed: widget.onShareReminder,
                  tooltip: l10n.text('share_reminder'),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(width: 6),

                // Call Button
                if (item.phone != null && item.phone!.isNotEmpty) ...[
                  IconButton(
                    onPressed: widget.onCall,
                    tooltip: l10n.text('call'),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // 1-Tap Collect Payment (Pay In)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onRecordPayment,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StitchColors.primary,
                      side: const BorderSide(color: StitchColors.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_card_rounded, size: 15),
                    label: Text(
                      l10n.text('collect_payment'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
