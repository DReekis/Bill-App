import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

/// Screen allowing owners and CAs to view the tamper-evident history of any transaction,
/// inspect before/after diffs, and export official CSV logs as required by MCA Rule 3(1).
class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key, this.initialEntity, this.initialEntityId});

  final String? initialEntity;
  final int? initialEntityId;

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  List<AuditEntry>? _allEntries;
  List<AuditEntry> _filteredEntries = [];
  bool _loading = true;

  String _selectedEntity = 'all';
  String _selectedAction = 'all';
  String _dateRangeLabel = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  final List<String> _entities = ['all', 'invoice', 'payment', 'product', 'customer', 'staff', 'supplier'];
  final List<String> _actions = ['all', 'create', 'update', 'cancel', 'delete'];

  @override
  void initState() {
    super.initState();
    if (widget.initialEntity != null) {
      _selectedEntity = widget.initialEntity!.toLowerCase();
    }
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    setState(() => _loading = true);

    try {
      final entries = await Repository.instance.auditLog(
        bizId,
        entity: _selectedEntity == 'all' ? null : _selectedEntity,
        entityId: widget.initialEntityId,
        action: _selectedAction == 'all' ? null : _selectedAction,
        startDate: _startDate != null ? isoDate(_startDate!) : null,
        endDate: _endDate != null ? '${isoDate(_endDate!)} 23:59:59' : null,
        limit: 1000,
      );

      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _applySearch();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppMessage(context, 'Failed to load audit trail: $e', error: true);
      }
    }
  }

  void _applySearch() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (_allEntries == null) {
      _filteredEntries = [];
      return;
    }
    if (query.isEmpty) {
      _filteredEntries = List.from(_allEntries!);
    } else {
      _filteredEntries = _allEntries!.where((e) {
        final actor = e.actor.toLowerCase();
        final action = e.action.toLowerCase();
        final entity = e.entity.toLowerCase();
        final idStr = (e.entityId ?? '').toString();
        final beforeStr = (e.before ?? '').toLowerCase();
        final afterStr = (e.after ?? '').toLowerCase();
        return actor.contains(query) ||
            action.contains(query) ||
            entity.contains(query) ||
            idStr.contains(query) ||
            beforeStr.contains(query) ||
            afterStr.contains(query);
      }).toList();
    }
  }

  void _setDatePreset(String label, DateTime? start, DateTime? end) {
    setState(() {
      _dateRangeLabel = label;
      _startDate = start;
      _endDate = end;
    });
    _loadEntries();
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked != null) {
      _setDatePreset('${picked.start.day}/${picked.start.month} - ${picked.end.day}/${picked.end.month}', picked.start, picked.end);
    }
  }

  Future<void> _exportCsv() async {
    final bizId = context.read<Session>().businessId;
    if (bizId == null) return;
    final biz = await Repository.instance.getBusiness(bizId);
    if (!mounted) return;
    final entries = _filteredEntries;
    if (entries.isEmpty) {
      showAppMessage(context, 'No audit records to export.');
      return;
    }

    final sb = StringBuffer()
      ..writeln('MCA Rule 3(1) Statutory Audit Trail - ${biz?.name ?? 'Business'}')
      ..writeln('Export Date,${DateTime.now().toIso8601String()}')
      ..writeln('Filtered Entity,$_selectedEntity,Filtered Action,$_selectedAction,Period,$_dateRangeLabel')
      ..writeln('Log ID,Timestamp,Actor (Mobile/Role),Action,Entity,Entity ID,Before State,After State');

    for (final e in entries) {
      final logId = e.id ?? '';
      final timestamp = e.timestamp;
      final actor = e.actor;
      final action = e.action;
      final entity = e.entity;
      final entityId = e.entityId ?? '';
      final before = _cleanCsv(e.before);
      final after = _cleanCsv(e.after);

      sb.writeln('$logId,"$timestamp","$actor","$action","$entity","$entityId","$before","$after"');
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/mca_audit_trail_${biz?.id ?? 0}_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(sb.toString(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'MCA Audit Trail Log - ${biz?.name ?? 'Business'}',
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to share CSV: $e', error: true);
    }
  }

  String _cleanCsv(String? val) {
    if (val == null || val.isEmpty) return '';
    return val.replaceAll('"', '""');
  }

  void _showInspectModal(AuditEntry entry) {
    Map<String, dynamic>? beforeMap;
    Map<String, dynamic>? afterMap;

    try {
      if (entry.before != null && entry.before!.isNotEmpty) {
        beforeMap = jsonDecode(entry.before!) as Map<String, dynamic>?;
      }
    } catch (_) {}

    try {
      if (entry.after != null && entry.after!.isNotEmpty) {
        afterMap = jsonDecode(entry.after!) as Map<String, dynamic>?;
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildActionBadge(entry.action),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${entry.entity.toUpperCase()} #${entry.entityId ?? entry.id}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  _detailRow('Timestamp', entry.timestamp),
                  _detailRow('Actor', entry.actor),
                  _detailRow('Action', entry.action.toUpperCase()),
                  _detailRow('Entity', entry.entity),
                  if (entry.entityId != null) _detailRow('Entity ID', entry.entityId.toString()),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  if (beforeMap != null && afterMap != null) ...[
                    const Text('Changes / Diff Inspection', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _buildDiffTable(beforeMap, afterMap),
                    const SizedBox(height: 14),
                  ],
                  if (beforeMap != null) ...[
                    const Text('State Before Edit (Snapshot)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                    const SizedBox(height: 6),
                    _buildJsonBox(beforeMap, isBefore: true),
                    const SizedBox(height: 14),
                  ],
                  if (afterMap != null) ...[
                    const Text('State After Edit (Snapshot)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                    const SizedBox(height: 6),
                    _buildJsonBox(afterMap, isBefore: false),
                  ],
                  if (beforeMap == null && afterMap == null)
                    const AppEmptyState(icon: Icons.notes_rounded, title: 'No structured payload recorded for this event.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffTable(Map<String, dynamic> before, Map<String, dynamic> after) {
    final allKeys = {...before.keys, ...after.keys}.toList()..sort();
    final changedRows = <Widget>[];

    for (final k in allKeys) {
      final bVal = before[k]?.toString() ?? '<null>';
      final aVal = after[k]?.toString() ?? '<null>';
      final isDifferent = bVal != aVal;

      if (isDifferent) {
        changedRows.add(
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bVal,
                        style: const TextStyle(fontSize: 11.5, color: StitchColors.error, decoration: TextDecoration.lineThrough),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 14, color: StitchColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        aVal,
                        style: const TextStyle(fontSize: 11.5, color: StitchColors.success, fontWeight: FontWeight.w700),
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

    if (changedRows.isEmpty) {
      return const Text('No modified field values detected.', style: TextStyle(fontSize: 12, color: StitchColors.textSecondary));
    }

    return Column(children: changedRows);
  }

  Widget _buildJsonBox(Map<String, dynamic> map, {required bool isBefore}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isBefore ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isBefore ? const Color(0xFFFECDD3) : const Color(0xFFBBF7D0)),
      ),
      child: SelectableText(
        const JsonEncoder.withIndent('  ').convert(map),
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 11,
          color: isBefore ? Colors.red.shade900 : Colors.green.shade900,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildActionBadge(String action) {
    final act = action.toLowerCase();
    Color bg;
    Color fg;
    IconData icon;

    switch (act) {
      case 'create':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        icon = Icons.add_circle_outline_rounded;
        break;
      case 'update':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        icon = Icons.edit_note_rounded;
        break;
      case 'cancel':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
        icon = Icons.cancel_outlined;
        break;
      case 'delete':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        icon = Icons.delete_outline_rounded;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = StitchColors.textPrimary;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(action.toUpperCase(), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCA Audit Trail'),
        actions: [
          IconButton(
            tooltip: 'Search audit records',
            icon: Icon(_showSearch ? Icons.search_off_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _applySearch();
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Export CSV for CA Audit',
            icon: const Icon(Icons.share_rounded),
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          // Statutory compliance notice banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFEEF2FF),
            child: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Color(0xFF4F46E5), size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'MCA Rule 3(1) Compliant: Continuous, tamper-evident audit trail recording every edit & cancellation.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF3730A3), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Search field if opened
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by actor, entity ID, or field changes...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(_applySearch);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                onChanged: (_) => setState(_applySearch),
              ),
            ),

          // Entity & Action Filter Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                // Date range button
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 14, color: StitchColors.primary),
                  label: Text(_dateRangeLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (bctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.all_inclusive_rounded),
                              title: const Text('All Time'),
                              onTap: () {
                                Navigator.pop(bctx);
                                _setDatePreset('All Time', null, null);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.today_rounded),
                              title: const Text('Today'),
                              onTap: () {
                                Navigator.pop(bctx);
                                final now = DateTime.now();
                                _setDatePreset('Today', now, now);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.calendar_view_week_rounded),
                              title: const Text('This Week'),
                              onTap: () {
                                Navigator.pop(bctx);
                                final now = DateTime.now();
                                _setDatePreset('This Week', now.subtract(Duration(days: now.weekday - 1)), now);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.calendar_month_rounded),
                              title: const Text('This Month'),
                              onTap: () {
                                Navigator.pop(bctx);
                                final now = DateTime.now();
                                _setDatePreset('This Month', DateTime(now.year, now.month, 1), now);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.date_range_rounded),
                              title: const Text('Custom Date Range...'),
                              onTap: () {
                                Navigator.pop(bctx);
                                _pickCustomDateRange();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Entity Chips
                ..._entities.map(
                  (ent) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(ent == 'all' ? 'All Entities' : ent.toUpperCase(), style: const TextStyle(fontSize: 11)),
                      selected: _selectedEntity == ent,
                      onSelected: (sel) {
                        if (sel) {
                          setState(() => _selectedEntity = ent);
                          _loadEntries();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Text('Action: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.textSecondary)),
                ..._actions.map(
                  (act) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(act == 'all' ? 'All Actions' : act.toUpperCase(), style: const TextStyle(fontSize: 11)),
                      selected: _selectedAction == act,
                      selectedColor: switch (act) {
                        'create' => const Color(0xFFDCFCE7),
                        'update' => const Color(0xFFDBEAFE),
                        'cancel' => const Color(0xFFFFEDD5),
                        'delete' => const Color(0xFFFEE2E2),
                        _ => null,
                      },
                      onSelected: (sel) {
                        if (sel) {
                          setState(() => _selectedAction = act);
                          _loadEntries();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Results summary header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredEntries.length} log ${_filteredEntries.length == 1 ? 'event' : 'events'} recorded',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: StitchColors.textSecondary),
                ),
                if (_filteredEntries.isNotEmpty)
                  InkWell(
                    onTap: _exportCsv,
                    child: const Row(
                      children: [
                        Icon(Icons.download_rounded, size: 14, color: StitchColors.primary),
                        SizedBox(width: 4),
                        Text('Export CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Audit records list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _filteredEntries.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.history_edu_rounded,
                        title: 'No audit records found',
                        subtitle: 'Transactions, edits and cancellations will automatically appear here.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: _filteredEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final e = _filteredEntries[i];
                          final hasPayload = (e.before != null && e.before!.isNotEmpty) || (e.after != null && e.after!.isNotEmpty);

                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showInspectModal(e),
                            child: AppCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _buildActionBadge(e.action),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${e.entity.toUpperCase()}${e.entityId != null ? ' #${e.entityId}' : ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        displayDate(e.timestamp.split(' ').first),
                                        style: const TextStyle(fontSize: 11, color: StitchColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.person_outline_rounded, size: 13, color: StitchColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Actor: ${e.actor.isEmpty ? "owner" : e.actor}',
                                        style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                                      ),
                                      const Spacer(),
                                      if (hasPayload)
                                        const Row(
                                          children: [
                                            Text('Inspect Diff', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StitchColors.primary)),
                                            SizedBox(width: 2),
                                            Icon(Icons.chevron_right_rounded, size: 16, color: StitchColors.primary),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
