import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../theme/stitch_theme.dart';

Color statusColor(String status) {
  switch (status) {
    case 'Paid':
      return StitchColors.success;
    case 'Overdue':
    case 'Unpaid':
      return StitchColors.error;
    case 'Pending':
    case 'Partially paid':
      return StitchColors.warning;
    case 'Finalized':
      return StitchColors.primary;
    default:
      return StitchColors.textSecondary;
  }
}

Color statusBackground(String status) {
  switch (status) {
    case 'Paid':
      return StitchColors.successSoft;
    case 'Overdue':
    case 'Unpaid':
      return StitchColors.errorSoft;
    case 'Pending':
    case 'Partially paid':
      return StitchColors.warningSoft;
    case 'Finalized':
      return StitchColors.primaryContainer;
    default:
      return const Color(0xFFF1F5F9);
  }
}

class StitchStatusChip extends StatelessWidget {
  const StitchStatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusBackground(status),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status,
          style: TextStyle(
            color: statusColor(status),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, this.padding = const EdgeInsets.all(16), required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: StitchColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: StitchColors.outline),
        ),
        child: child,
      );
}

class MoneyText extends StatelessWidget {
  const MoneyText(this.paise, {super.key, this.fontSize = 15, this.weight = FontWeight.w700, this.color});
  final int paise;
  final double fontSize;
  final FontWeight weight;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        formatPaise(paise),
        style: moneyStyle(fontSize: fontSize, weight: weight, color: color ?? StitchColors.textPrimary),
      );
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {super.key, this.actionText, this.onAction});
  final String title;
  final String? actionText;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StitchColors.textPrimary)),
          ),
          if (actionText != null)
            TextButton(onPressed: onAction, child: Text(actionText!)),
        ],
      );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color = StitchColors.primary, this.detail});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? detail;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(color: StitchColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Icon(icon, size: 18, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: moneyStyle(fontSize: 20, weight: FontWeight.w800, color: StitchColors.textPrimary)),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: StitchColors.surfaceVariant, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: StitchColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: StitchColors.textSecondary)),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      );
}

class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap, this.color = StitchColors.primary});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 74,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 7),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.prefixText,
    this.icon,
    this.obscure = false,
    this.validator,
    this.maxLines = 1,
    this.onSubmitted,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? prefixText;
  final IconData? icon;
  final bool obscure;
  final String? Function(String?)? validator;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged,
        inputFormatters: keyboardType == TextInputType.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefixText,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
        ),
        validator: validator,
      );
}

class AppAmountField extends StatelessWidget {
  const AppAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.suffixIcon,
    this.hintText,
  });
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final Widget? suffixIcon;
  final String? hintText;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText ?? '0.00',
          prefixText: '₹ ',
          prefixStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: StitchColors.textPrimary),
          suffixText: suffix,
          suffixIcon: suffixIcon,
        ),
      );
}

class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.date,
    required this.onDateSelected,
    this.label = 'Date',
    this.firstDate,
    this.lastDate,
  });

  final String date;
  final ValueChanged<String> onDateSelected;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final dt = dateTimeFor(date);
        final picked = await showDatePicker(
          context: context,
          initialDate: dt,
          firstDate: firstDate ?? DateTime(dt.year - 2),
          lastDate: lastDate ?? DateTime(dt.year + 2),
        );
        if (picked != null) onDateSelected(isoDate(picked));
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: inputDecoration(label).copyWith(
          prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          displayDate(date),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: StitchColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class AsyncButton extends StatefulWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.loading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.style,
  });
  final String label;
  final FutureOr<void> Function() onPressed;
  final IconData? icon;
  final bool expand;
  final bool loading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final ButtonStyle? style;
  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool busy = false;
  Future<void> _run() async {
    if (busy || widget.loading) return;
    setState(() => busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = busy || widget.loading;
    final child = isBusy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 18), const SizedBox(width: 8)],
            // long labels must ellipsize instead of overflowing the button
            Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]);
    final onTapped = isBusy ? null : _run;
    final btnStyle = widget.style ??
        (widget.backgroundColor != null || widget.foregroundColor != null
            ? FilledButton.styleFrom(
                backgroundColor: widget.backgroundColor,
                foregroundColor: widget.foregroundColor,
              )
            : null);
    return widget.expand
        ? SizedBox(width: double.infinity, child: FilledButton(style: btnStyle, onPressed: onTapped, child: child))
        : FilledButton(style: btnStyle, onPressed: onTapped, child: child);
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final names = name.trim().split(RegExp(r'\s+'));
    final initials = names.isNotEmpty
        ? names.take(2).map((n) => n.isNotEmpty ? n[0].toUpperCase() : '').join()
        : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: StitchColors.primaryContainer, borderRadius: BorderRadius.circular(size / 3)),
      child: Text(initials, style: TextStyle(color: StitchColors.primary, fontSize: size * 0.32, fontWeight: FontWeight.w800)),
    );
  }
}

OverlayEntry? _activeMessage;

/// Shown in the root overlay, not via ScaffoldMessenger: a SnackBar raised from
/// inside a bottom sheet or dialog is painted behind it and never seen.
void showAppMessage(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeMessage?.remove();
  _activeMessage = null;
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: IgnorePointer(
        child: Material(
          color: error ? StitchColors.error : StitchColors.textPrimary,
          borderRadius: BorderRadius.circular(10),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    ),
  );
  _activeMessage = entry;
  overlay.insert(entry);
  Timer(const Duration(seconds: 3), () {
    if (_activeMessage == entry) {
      entry.remove();
      _activeMessage = null;
    }
  });
}

InputDecoration inputDecoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
    );

String initialsOf(String name) {
  final names = name.trim().split(RegExp(r'\s+'));
  if (names.isEmpty) return '?';
  return names.take(2).map((n) => n.isNotEmpty ? n[0].toUpperCase() : '').join();
}