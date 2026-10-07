import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import 'date_filter_bar.dart';

class CashflowReportScreen extends StatefulWidget {
  const CashflowReportScreen({super.key});

  @override
  State<CashflowReportScreen> createState() => _CashflowReportScreenState();
}

class _CashflowReportScreenState extends State<CashflowReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _period = 'This Month';
  late DateTime _startDate;
  late DateTime _endDate;
  String _accountType = 'all'; // 'all', 'cash', 'bank'

  bool _loading = true;
  String? _error;
  CashflowReportData? _data;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final range = resolvePresetDateRange(_period);
    _startDate = range.start;
    _endDate = range.end;
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
    setState(() => _loading = true);
    try {
      final res = await Repository.instance.getCashflowReport(
        bizId,
        accountType: _accountType,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    if (_data == null) return;
    final biz = await Repository.instance.getBusiness(context.read<Session>().businessId!);
    final bizName = biz?.name ?? 'Business';
    final excel = xl.Excel.createExcel();
    final sheet = excel['Cash Flow Statement'];

    sheet.appendRow(['Cash Flow Statement - $bizName']);
    sheet.appendRow(['Period: ${displayDate(isoDate(_startDate))} to ${displayDate(isoDate(_endDate))}']);
    sheet.appendRow(['Account: ${_accountTypeLabel(_accountType)}']);
    sheet.appendRow([]);

    sheet.appendRow(['Summary Metrics']);
    sheet.appendRow(['Opening Cash', formatPaise(_data!.openingCash)]);
    sheet.appendRow(['Money In (+)', formatPaise(_data!.moneyIn)]);
    sheet.appendRow(['Money Out (-)', formatPaise(_data!.moneyOut)]);
    sheet.appendRow(['Closing Cash', formatPaise(_data!.closingCash)]);
    sheet.appendRow([]);

    sheet.appendRow(['Money In Transactions']);
    sheet.appendRow(['Date', 'Party Name', 'Transaction Type', 'Account', 'Amount (Rs)']);
    for (final e in _data!.moneyInList) {
      sheet.appendRow([
        displayDate(e.date),
        e.partyName,
        e.transactionType,
        e.accountDisplayName ?? e.account,
        e.amount / 100.0,
      ]);
    }
    sheet.appendRow([]);

    sheet.appendRow(['Money Out Transactions']);
    sheet.appendRow(['Date', 'Party Name', 'Transaction Type', 'Account', 'Amount (Rs)']);
    for (final e in _data!.moneyOutList) {
      sheet.appendRow([
        displayDate(e.date),
        e.partyName,
        e.transactionType,
        e.accountDisplayName ?? e.account,
        e.amount / 100.0,
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final filename = 'Cashflow_Statement_${_period.replaceAll(' ', '_')}_${todayIso()}.xlsx';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Cash Flow Statement - $bizName',
    );
  }

  String _accountTypeLabel(String type) {
    switch (type) {
      case 'cash':
        return 'Cash-in-hand';
      case 'bank':
        return 'Bank Accounts';
      case 'all':
      default:
        return 'All Accounts';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Cash Flow Statement', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_rounded, size: 20),
            tooltip: 'Export to Excel (.xlsx)',
            onPressed: _data == null ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar Section
          Container(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlobalDateFilterBar(
                  selectedPeriod: _period,
                  customStart: _startDate,
                  customEnd: _endDate,
                  onRangeChanged: (start, end, label) {
                    setState(() {
                      _startDate = start;
                      _endDate = end;
                      _period = label;
                    });
                    _load();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Date range display subtitle
                      Row(
                        children: [
                          const Icon(Icons.date_range_rounded, size: 14, color: StitchColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            '${displayDate(isoDate(_startDate))} - ${displayDate(isoDate(_endDate))}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                          ),
                        ],
                      ),

                      // Account Type Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: StitchColors.outline.withValues(alpha: 0.8)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _accountType,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: StitchColors.primary),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Accounts')),
                              DropdownMenuItem(value: 'cash', child: Text('Cash-in-hand')),
                              DropdownMenuItem(value: 'bank', child: Text('Bank Accounts')),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _accountType) {
                                setState(() => _accountType = val);
                                _load();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error loading cash flow: $_error', style: const TextStyle(color: StitchColors.error)),
                        ),
                      )
                    : _data == null
                        ? const Center(child: Text('No data available'))
                        : Column(
                            children: [
                              // Top Summary Cards (4 key metrics)
                              _buildHeaderCards(_data!),

                              // Tabbed View: Money In vs Money Out
                              Container(
                                color: Colors.white,
                                child: TabBar(
                                  controller: _tabController,
                                  indicatorColor: StitchColors.primary,
                                  indicatorWeight: 3,
                                  labelColor: StitchColors.primary,
                                  unselectedLabelColor: StitchColors.textSecondary,
                                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  tabs: [
                                    Tab(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.arrow_downward_rounded, size: 16, color: StitchColors.success),
                                          const SizedBox(width: 6),
                                          Text('Money In (${_data!.moneyInList.length})'),
                                        ],
                                      ),
                                    ),
                                    Tab(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.arrow_upward_rounded, size: 16, color: StitchColors.error),
                                          const SizedBox(width: 6),
                                          Text('Money Out (${_data!.moneyOutList.length})'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),

                              // Tab Content List
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _buildTransactionList(_data!.moneyInList, isMoneyIn: true),
                                    _buildTransactionList(_data!.moneyOutList, isMoneyIn: false),
                                  ],
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCards(CashflowReportData d) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Opening Cash',
                  value: formatPaise(d.openingCash),
                  icon: Icons.account_balance_wallet_outlined,
                  color: StitchColors.primary,
                  subtext: 'Prior balance',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  title: 'Money In (+)',
                  value: '+${formatPaise(d.moneyIn)}',
                  icon: Icons.south_west_rounded,
                  color: StitchColors.success,
                  subtext: '${d.moneyInList.length} txns',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Money Out (-)',
                  value: '-${formatPaise(d.moneyOut)}',
                  icon: Icons.north_east_rounded,
                  color: StitchColors.error,
                  subtext: '${d.moneyOutList.length} txns',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  title: 'Closing Cash',
                  value: formatPaise(d.closingCash),
                  icon: Icons.savings_rounded,
                  color: const Color(0xFF0F172A),
                  subtext: 'Opening + In - Out',
                  isHighlighted: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtext,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted ? color.withValues(alpha: 0.3) : StitchColors.outline.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<CashflowEntry> list, {required bool isMoneyIn}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMoneyIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              isMoneyIn ? 'No Money In transactions in this period' : 'No Money Out transactions in this period',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = list[index];
          return _buildTransactionCard(item, isMoneyIn: isMoneyIn);
        },
      ),
    );
  }

  Widget _buildTransactionCard(CashflowEntry item, {required bool isMoneyIn}) {
    final amountColor = isMoneyIn ? StitchColors.success : StitchColors.error;
    final prefix = isMoneyIn ? '+' : '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMoneyIn ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: amountColor,
            ),
          ),
          const SizedBox(width: 12),

          // Details: Party Name, Date, Transaction Type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.partyName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StitchColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildTypeBadge(item.transactionType),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 12, color: StitchColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      displayDate(item.date),
                      style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.account_balance_outlined, size: 12, color: StitchColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      item.accountDisplayName ?? item.account,
                      style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Amount
          Text(
            '$prefix${formatPaise(item.amount)}',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bg;
    Color fg;
    switch (type.toLowerCase()) {
      case 'sales':
      case 'payment in':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
      case 'purchase':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      case 'expense':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        break;
      case 'transfer':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
        break;
      case 'opening balance':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = StitchColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
