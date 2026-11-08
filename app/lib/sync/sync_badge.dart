import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/login_screen.dart';
import '../theme/stitch_theme.dart';
import '../utils/widgets.dart';
import 'sync_engine.dart';

/// Clean, stateful cloud sync badge with 4 reactive states:
/// 🔵 Syncing (Spinning indicator)
/// 🔴 Error (Alert red with retry)
/// 🟡 Pending (Amber with pending count)
/// 🟢 Synced (Green checkmark)
class SyncBadge extends StatelessWidget {
  const SyncBadge({
    super.key,
    this.onTap,
    this.compact = false,
  });

  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final isBusy = sync.syncing;
    final hasError = sync.lastError != null && sync.lastError!.isNotEmpty;
    final hasPending = sync.pendingCount > 0;

    final Color color;
    final Widget icon;
    final String label;

    if (isBusy) {
      color = StitchColors.primary;
      icon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
      label = 'Syncing...';
    } else if (hasError) {
      color = StitchColors.error;
      icon = Icon(sync.isAuthError ? Icons.lock_clock_outlined : Icons.sync_problem_rounded, size: 14, color: color);
      label = sync.isAuthError ? 'Session expired' : 'Sync error';
    } else if (hasPending) {
      color = StitchColors.warning;
      icon = Icon(Icons.cloud_upload_outlined, size: 14, color: color);
      label = '${sync.pendingCount} to sync';
    } else {
      color = StitchColors.success;
      icon = Icon(Icons.cloud_done_outlined, size: 14, color: color);
      label = 'Synced';
    }

    return Tooltip(
      message: isBusy
          ? 'Syncing with cloud...'
          : hasError
              ? 'Sync error: ${sync.lastError ?? 'Tap to retry'}'
              : hasPending
                  ? '${sync.pendingCount} changes waiting to upload — Tap to sync now'
                  : 'All cloud changes synced — Tap to refresh',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ??
              () async {
                if (sync.syncing) {
                  showAppMessage(context, 'Cloud sync is already in progress');
                  return;
                }
                if (sync.isAuthError) {
                  _showAuthExpiredSheet(context);
                  return;
                }
                await sync.syncNow(force: true);
                if (context.mounted) {
                  if (sync.lastError != null) {
                    showAppMessage(context, 'Sync failed: ${sync.lastError}');
                  } else {
                    final summary = sync.lastSyncResultSummary ?? 'Up to date';
                    showAppMessage(context, 'Cloud sync complete: $summary');
                  }
                }
              },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: compact ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAuthExpiredSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StitchColors.warning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_sync_outlined, color: StitchColors.warning, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud Session Expired',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Re-authenticate to keep your invoices synced',
                        style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Your cloud session token has expired or is invalid. Your local data on this phone is 100% safe. Sign in again to resume automatic cloud backup and sync.',
              style: TextStyle(fontSize: 13, height: 1.4, color: StitchColors.textPrimary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen(isModal: true)),
                );
                await SyncEngine.instance.syncNow(force: true);
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Sign In / Reconnect Cloud', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: StitchColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss (Stay Offline)', style: TextStyle(color: StitchColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
