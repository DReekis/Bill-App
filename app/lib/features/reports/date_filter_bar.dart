import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../theme/stitch_theme.dart';

DateTimeRange resolvePresetDateRange(String preset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (preset.toLowerCase()) {
    case 'today':
      return DateTimeRange(start: today, end: today);
    case 'this week':
      final start = today.subtract(Duration(days: today.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return DateTimeRange(start: start, end: end);
    case 'this month':
      final start = DateTime(today.year, today.month, 1);
      final nextMonth = today.month == 12 ? DateTime(today.year + 1, 1, 1) : DateTime(today.year, today.month + 1, 1);
      final end = nextMonth.subtract(const Duration(days: 1));
      return DateTimeRange(start: start, end: end);
    case 'this year':
      final start = DateTime(today.year, 1, 1);
      final end = DateTime(today.year, 12, 31);
      return DateTimeRange(start: start, end: end);
    case 'this quarter':
      final qStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;
      final start = DateTime(today.year, qStartMonth, 1);
      final nextQMonth = qStartMonth + 3 > 12 ? 1 : qStartMonth + 3;
      final nextQYear = qStartMonth + 3 > 12 ? today.year + 1 : today.year;
      final end = DateTime(nextQYear, nextQMonth, 1).subtract(const Duration(days: 1));
      return DateTimeRange(start: start, end: end);
    default:
      return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
  }
}

/// Shared Global Date Filter Bar component for Reports, Sales Summary, P&L, Cashflow, etc.
/// Includes fixed preset chips (Today, This Week, This Month, This Year) and a dedicated Custom Range (calendar) button.
class GlobalDateFilterBar extends StatefulWidget {
  const GlobalDateFilterBar({
    super.key,
    this.selectedPeriod = 'This Month',
    this.customStart,
    this.customEnd,
    required this.onRangeChanged,
    this.presets = const ['Today', 'This Week', 'This Month', 'This Year'],
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final String selectedPeriod;
  final DateTime? customStart;
  final DateTime? customEnd;
  final void Function(DateTime start, DateTime end, String periodLabel) onRangeChanged;
  final List<String> presets;
  final EdgeInsetsGeometry padding;

  @override
  State<GlobalDateFilterBar> createState() => _GlobalDateFilterBarState();
}

class _GlobalDateFilterBarState extends State<GlobalDateFilterBar> {
  late String _activePeriod;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _activePeriod = widget.selectedPeriod;
    _customStart = widget.customStart;
    _customEnd = widget.customEnd;
  }

  @override
  void didUpdateWidget(covariant GlobalDateFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPeriod != widget.selectedPeriod) {
      _activePeriod = widget.selectedPeriod;
    }
    if (oldWidget.customStart != widget.customStart || oldWidget.customEnd != widget.customEnd) {
      _customStart = widget.customStart;
      _customEnd = widget.customEnd;
    }
  }

  Future<void> _openCustomRangePicker() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: _customStart ?? (_activePeriod == 'Custom' ? now.subtract(const Duration(days: 30)) : resolvePresetDateRange(_activePeriod).start),
      end: _customEnd ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: StitchColors.primary,
                  onPrimary: Colors.white,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _activePeriod = 'Custom';
        _customStart = picked.start;
        _customEnd = picked.end;
      });
      widget.onRangeChanged(picked.start, picked.end, 'Custom');
    }
  }

  void _onSelectPreset(String preset) {
    final range = resolvePresetDateRange(preset);
    setState(() {
      _activePeriod = preset;
    });
    widget.onRangeChanged(range.start, range.end, preset);
  }

  String _formatCustomButtonLabel() {
    if (_activePeriod == 'Custom' && _customStart != null && _customEnd != null) {
      return formatRangeDisplay(_customStart!, _customEnd!);
    }
    return 'Custom Range';
  }

  @override
  Widget build(BuildContext context) {
    final isCustomActive = _activePeriod == 'Custom';

    return Padding(
      padding: widget.padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in widget.presets) ...[
              ChoiceChip(
                label: Text(p),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _activePeriod == p ? FontWeight.w700 : FontWeight.w500,
                  color: _activePeriod == p ? Colors.white : StitchColors.textPrimary,
                ),
                selected: _activePeriod == p,
                selectedColor: StitchColors.primary,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: _activePeriod == p ? StitchColors.primary : Colors.grey.shade300,
                  ),
                ),
                showCheckmark: false,
                onSelected: (selected) {
                  if (selected) {
                    _onSelectPreset(p);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],

            // Custom Range Button with Calendar Icon
            InkWell(
              onTap: _openCustomRangePicker,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isCustomActive ? StitchColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isCustomActive ? StitchColors.primary : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: isCustomActive ? Colors.white : StitchColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatCustomButtonLabel(),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isCustomActive ? FontWeight.w700 : FontWeight.w600,
                        color: isCustomActive ? Colors.white : StitchColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
