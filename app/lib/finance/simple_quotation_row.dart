import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class SimpleQuotationRow extends StatelessWidget {
  const SimpleQuotationRow({
    super.key,
    required this.quotation,
    required this.onTap,
    this.onConvert,
    this.onShare,
  });

  final Quotation quotation;
  final VoidCallback onTap;
  final VoidCallback? onConvert;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final isConverted = quotation.status.toLowerCase() == 'converted';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // Soft amber icon container for estimate
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.request_quote_rounded,
                    size: 18,
                    color: Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              quotation.number,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isConverted ? StitchColors.successSoft : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isConverted ? 'Converted' : 'Estimate',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: isConverted ? StitchColors.success : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${displayDate(quotation.date)}${quotation.lines.isNotEmpty ? ' • ${quotation.lines.length} items' : ''}',
                        style: const TextStyle(fontSize: 11.5, color: StitchColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(quotation.total, fontSize: 13),
                    const SizedBox(height: 2),
                    Text(
                      isConverted ? 'Invoiced' : 'Open',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isConverted ? StitchColors.success : StitchColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (onConvert != null || onShare != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onShare != null)
                    TextButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share_outlined, size: 14),
                      label: const Text('Share', style: TextStyle(fontSize: 11.5)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                    ),
                  if (!isConverted && onConvert != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onConvert,
                      icon: const Icon(Icons.transform_rounded, size: 13),
                      label: const Text('Convert to Bill', style: TextStyle(fontSize: 11.5)),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
