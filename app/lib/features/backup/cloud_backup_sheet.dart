import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/backup_service.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../auth/login_screen.dart';

class CloudBackupSheet extends StatefulWidget {
  const CloudBackupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudBackupSheet(),
    );
  }

  @override
  State<CloudBackupSheet> createState() => _CloudBackupSheetState();
}

class _CloudBackupSheetState extends State<CloudBackupSheet> {
  final _backupService = BackupService();
  bool _loading = true;
  bool _actionInProgress = false;
  String? _statusText;
  DateTime? _lastBackupTime;
  List<BackupInfo> _backups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final session = context.read<Session>();
    final lastTime = await _backupService.getLastCloudBackupTime();

    List<BackupInfo> list = [];
    if (session.isCloudLinked) {
      try {
        final client = ApiClient()
          ..setToken(session.token)
          ..setBusinessId(session.businessId?.toString());
        list = await _backupService.listCloudBackups(clientOverride: client);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _lastBackupTime = lastTime;
      _backups = list;
      _loading = false;
    });
  }

  Future<void> _handleBackupNow() async {
    final session = context.read<Session>();
    if (!session.isCloudLinked) {
      final linked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen(isModal: true)),
      );
      if (linked == true) {
        _loadData();
      }
      return;
    }

    setState(() {
      _actionInProgress = true;
      _statusText = 'Creating snapshot & encrypting...';
    });

    try {
      final client = ApiClient()
        ..setToken(session.token)
        ..setBusinessId(session.businessId?.toString());

      setState(() => _statusText = 'Uploading to AWS Cloud Vault...');
      final info = await _backupService.uploadToCloud(clientOverride: client);

      if (!mounted) return;
      setState(() {
        _lastBackupTime = info.createdAt;
        _backups.insert(0, info);
        _actionInProgress = false;
        _statusText = null;
      });
      showAppMessage(context, 'Database safely backed up to Cloud Vault');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionInProgress = false;
        _statusText = null;
      });
      showAppMessage(context, 'Backup failed: $e', error: true);
    }
  }

  Future<void> _handleRestore(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Cloud Backup?'),
        content: Text(
          'Restoring "${backup.filename}" (${backup.sizeFormatted}) will roll back your local transactions to ${DateFormat('dd MMM yyyy, hh:mm a').format(backup.createdAt)}.\n\nA safety failover copy will be preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StitchColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore Database'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final session = context.read<Session>();
    setState(() {
      _actionInProgress = true;
      _statusText = 'Restoring database snapshot...';
    });

    try {
      final client = ApiClient()
        ..setToken(session.token)
        ..setBusinessId(session.businessId?.toString());

      await _backupService.restoreFromCloud(backupId: backup.id, clientOverride: client);

      if (!mounted) return;
      setState(() {
        _actionInProgress = false;
        _statusText = null;
      });
      showAppMessage(context, 'Database restored successfully!');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionInProgress = false;
        _statusText = null;
      });
      showAppMessage(context, 'Restore failed: $e', error: true);
    }
  }

  Future<void> _handleExportLocal() async {
    try {
      await _backupService.exportLocalBackup();
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Export failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isLinked = session.isCloudLinked;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B4DBC).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF5B4DBC), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cloud Backup & Disaster Recovery',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLinked ? 'Encrypted AWS Cloud Vault Active' : 'Offline Mode (Local Storage)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isLinked ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Vault Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'LAST CLOUD BACKUP',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                    if (isLinked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AES-256',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _lastBackupTime != null
                      ? DateFormat('EEEE, dd MMM yyyy • hh:mm a').format(_lastBackupTime!)
                      : 'Never backed up to cloud',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  isLinked
                      ? 'Point-in-time snapshots protect your ledger from device loss, damage, or accidental deletions.'
                      : 'Connect your Google Cloud Account to enable automatic point-in-time recovery vaults.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Primary Actions
          if (_actionInProgress) ...[
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(height: 10),
                  Text(_statusText ?? 'Processing...', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                ],
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _handleBackupNow,
              icon: const Icon(Icons.cloud_upload_outlined, size: 19),
              label: Text(isLinked ? 'Backup to Cloud Vault Now' : 'Connect Google Cloud Account to Backup'),
              style: FilledButton.styleFrom(
                backgroundColor: StitchColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _handleExportLocal,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Export Local Copy (WhatsApp / Drive / Files)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],

          if (isLinked) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cloud Backup Vaults',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
                TextButton(
                  onPressed: _loadData,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Refresh', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_backups.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No cloud backups found yet.\nTap "Backup to Cloud Vault Now" to create your first safe copy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _backups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    final b = _backups[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF5B4DBC), size: 22),
                      title: Text(
                        DateFormat('dd MMM yyyy • hh:mm a').format(b.createdAt),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${b.sizeFormatted} • ${b.deviceName ?? 'Device'}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                      trailing: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF5B4DBC),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 16),
                        label: const Text('Restore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        onPressed: _actionInProgress ? null : () => _handleRestore(b),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
