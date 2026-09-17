import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/app_database.dart';
import '../../data/repositories.dart';
import '../../sync/sync_engine.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../banking/cash_bank_hub_screen.dart';
import '../gst/gst_center_screen.dart';
import '../reports/reports_screen.dart';
import '../shell/audit_log_screen.dart';
import '../shell/business_edit_screen.dart';
import '../shell/business_switcher_sheet.dart';
import 'import_screen.dart';

export '../customers/parties_tab.dart' show PartiesTab;

class MoreTab extends StatefulWidget {
  const MoreTab({super.key});
  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  Business? business;

  Future<void> _load() async {
    final businessId = context.read<Session>().businessId;
    if (businessId == null) return;
    final b = await Repository.instance.getBusiness(businessId);
    await SyncEngine.instance.refreshPending();
    if (!mounted) return;
    setState(() => business = b);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final sync = context.watch<SyncEngine>();
    final biz = business;
    void nav(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _load());
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
      Row(children: [
        const Expanded(
          child: Text('More', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (session.hasPin)
          TextButton.icon(
            onPressed: () => session.lock(),
            icon: const Icon(Icons.lock_outline_rounded, size: 16),
            label: const Text('Lock'),
          ),
      ]),
      const SizedBox(height: 6),
      InkWell(
        onTap: () => showBusinessSwitcher(context).then((changed) {
          if (changed == true) _load();
        }),
        borderRadius: BorderRadius.circular(14),
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            InitialsAvatar(biz?.name ?? 'My Business', size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(biz?.name ?? 'My Business', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(biz?.gstin?.isNotEmpty == true ? 'GSTIN ${biz!.gstin}' : 'Tap to switch business',
                    style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20, color: StitchColors.textTertiary),
              tooltip: 'Edit Business Profile',
              onPressed: () => nav(const BusinessEditScreen()),
            ),
            const Icon(Icons.unfold_more_rounded, color: StitchColors.primary),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      _menuTile(context, Icons.swap_horiz_rounded, 'Switch business', () => showBusinessSwitcher(context).then((changed) {
        if (changed == true) _load();
      })),
      _menuTile(context, Icons.account_balance_outlined, 'GST Compliance Center', () => nav(const GstCenterScreen())),
      _menuTile(context, Icons.account_balance_wallet_outlined, 'Cash & Bank Accounts Hub', () => nav(const CashBankHubScreen())),
      _menuTile(context, Icons.bar_chart_rounded, 'Reports & analytics', () => nav(const ReportsScreen())),
      _menuTile(context, Icons.upload_file_rounded, 'Bulk import', () => nav(const ImportScreen())),
      _menuTile(context, Icons.history_rounded, 'Audit log', () => nav(const AuditLogScreen())),
      _menuTile(context, Icons.cloud_sync_rounded, 'Data sync', () => _syncMenu(context, sync), trailing: sync.pendingCount != null && sync.pendingCount! > 0
          ? Text('${sync.pendingCount} pending', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.warning))
          : null),
      _menuTile(context, Icons.backup_outlined, 'Backup & export', () => nav(const BackupExportScreen())),
      _menuTile(context, Icons.tune_rounded, 'Invoice settings', () => nav(const BusinessEditScreen())),
      _menuTile(
        context,
        Icons.lock_rounded,
        session.hasPin ? 'App lock · PIN set' : 'App lock (set PIN)',
        () => _pinSettings(context),
      ),
      _menuTile(
        context,
        Icons.admin_panel_settings_rounded,
        'Role: ${session.currentRole}',
        () => _switchRole(context, session),
      ),
      const SizedBox(height: 18),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 30),
        child: Text('Billket • local-first', style: TextStyle(fontSize: 11, color: StitchColors.textTertiary)),
      ),
    ]);
  }

  Widget _menuTile(BuildContext context, IconData icon, String title, VoidCallback onTap, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: StitchColors.background,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: StitchColors.outline),
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: StitchColors.primaryContainer, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 20, color: StitchColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                if (trailing != null) trailing,
                const Icon(Icons.chevron_right_rounded, color: StitchColors.textTertiary),
              ]),
            ),
          ),
        ),
      );

  void _pinSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => PinSettingsDialog(
        onChanged: (message) {
          if (context.mounted) showAppMessage(context, message);
        },
      ),
    );
  }

  void _switchRole(BuildContext context, Session session) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Switch Role (Testing)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListTile(
          title: const Text('Admin / Owner'),
          onTap: () {
            session.switchRole('Admin');
            Navigator.pop(context);
          },
        ),
        ListTile(
          title: const Text('Salesman'),
          onTap: () {
            session.switchRole('Salesman');
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }

  void _syncMenu(BuildContext context, SyncEngine sync) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Data sync', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${sync.pendingCount ?? 0} change(s) waiting to sync',
              style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await sync.syncNow();
                if (context.mounted) {
                  showAppMessage(context, sync.pendingCount == 0 ? 'All changes synced' : '${sync.pendingCount} waiting to sync');
                }
              },
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
          ),
        ]),
      ),
    );
  }
}

class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key});
  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class PinSettingsDialog extends StatefulWidget {
  const PinSettingsDialog({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;
  @override
  State<PinSettingsDialog> createState() => _PinSettingsDialogState();
}

final _digits = [FilteringTextInputFormatter.digitsOnly];

class _PinSettingsDialogState extends State<PinSettingsDialog> {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = context.read<Session>();
    if (session.hasPin && !session.verifyPin(_current.text.trim())) {
      showAppMessage(context, 'Current PIN is incorrect', error: true);
      return;
    }
    final pin = _pin.text.trim();
    if (pin.length != 4) {
      showAppMessage(context, 'PIN must be exactly 4 digits', error: true);
      return;
    }
    if (pin != _confirm.text.trim()) {
      showAppMessage(context, 'PINs do not match', error: true);
      return;
    }
    await session.setPin(pin);
    if (mounted) Navigator.of(context).pop();
    widget.onChanged('App lock PIN saved');
  }

  void _remove() async {
    final session = context.read<Session>();
    if (!session.verifyPin(_current.text.trim())) {
      showAppMessage(context, 'Current PIN is incorrect', error: true);
      return;
    }
    await session.updatePin(null);
    if (mounted) Navigator.of(context).pop();
    widget.onChanged('App lock disabled');
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = context.watch<Session>().hasPin;
    return AlertDialog(
      title: const Text('App lock (PIN)'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hasPin) ...[
            TextField(
              controller: _current,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: _digits,
              decoration: inputDecoration('Current PIN'),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: _digits,
            decoration: inputDecoration(hasPin ? 'New PIN' : 'PIN (4 digits)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: _digits,
            decoration: inputDecoration('Confirm PIN'),
          ),
        ]),
      ),
      actions: [
        if (hasPin)
          TextButton(
            onPressed: _remove,
            child: const Text('Remove PIN', style: TextStyle(color: StitchColors.error)),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  bool exporting = false;

  Future<void> _export() async {
    setState(() => exporting = true);
    try {
      final file = await AppDatabase.instance.databaseFile();
      if (file.existsSync()) {
        final temp = await AppDatabase.instance.tempExportFile();
        await temp.writeAsBytes(await file.readAsBytes());
        await Share.shareXFiles(
          [XFile(temp.path, mimeType: 'application/octet-stream', name: 'ledger_pilot_backup.db')],
          subject: 'Billket backup',
          text: 'Your Billket data backup. Keep it safe.',
        );
      } else {
        if (mounted) showAppMessage(context, 'Database file not found yet.', error: true);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backup & export')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.storage_rounded, color: StitchColors.primary),
                SizedBox(width: 10),
                Text('Local database', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              const Text('Your data lives on this device in ledger_pilot.db. Export a copy to share or archive it.',
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AsyncButton(
                  loading: exporting,
                  icon: Icons.ios_share_rounded,
                  label: 'Export database file',
                  onPressed: _export,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          const Text('Restore from backup is coming in a future update.',
              style: TextStyle(fontSize: 12.5, color: StitchColors.textTertiary)),
        ]),
      );
}