import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import '../sales/invoice_list_tab.dart';
import '../shell/audit_log_screen.dart';
import '../shell/business_edit_screen.dart';
import '../shell/business_switcher_sheet.dart';
import 'import_screen.dart';
import '../../l10n/app_localizations.dart';

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
    final l10n = context.l10n;
    final isHi = session.localeCode == 'hi';
    final biz = business;
    void nav(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _load());
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
      Row(children: [
        Expanded(
          child: Text(l10n.text('more'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (session.hasPin)
          TextButton.icon(
            onPressed: () => session.lock(),
            icon: const Icon(Icons.lock_outline_rounded, size: 16),
            label: Text(l10n.text('lock')),
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
                Text(biz?.gstin?.isNotEmpty == true ? 'GSTIN ${biz!.gstin}' : (isHi ? 'व्यापार बदलने के लिए टैप करें' : 'Tap to switch business'),
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
      _menuTile(context, Icons.swap_horiz_rounded, isHi ? 'व्यापार बदलें' : 'Switch business', () => showBusinessSwitcher(context).then((changed) {
        if (changed == true) _load();
      })),
      _menuTile(context, Icons.receipt_long_outlined, isHi ? 'सभी लेन-देन' : 'All Transactions', () => nav(const TransactionListScreen())),
      _menuTile(context, Icons.account_balance_outlined, isHi ? 'जीएसटी केंद्र' : 'GST Compliance Center', () => nav(const GstCenterScreen())),
      _menuTile(context, Icons.account_balance_wallet_outlined, isHi ? 'कैश व बैंक खाते' : 'Cash & Bank Accounts Hub', () => nav(const CashBankHubScreen())),
      _menuTile(context, Icons.bar_chart_rounded, isHi ? 'रिपोर्ट्स' : 'Reports & analytics', () => nav(const ReportsScreen())),
      _menuTile(context, Icons.upload_file_rounded, isHi ? 'डेटा आयात' : 'Bulk import', () => nav(const ImportScreen())),
      _menuTile(context, Icons.history_rounded, isHi ? 'ऑडिट लॉग' : 'Audit log', () => nav(const AuditLogScreen())),
      _menuTile(context, Icons.cloud_sync_rounded, isHi ? 'डेटा सिंक' : 'Data sync', () => _syncMenu(context, sync), trailing: sync.pendingCount > 0
          ? Text(isHi ? '${sync.pendingCount} बाकी' : '${sync.pendingCount} pending', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StitchColors.warning))
          : null),
      _menuTile(context, Icons.backup_outlined, isHi ? 'बैकअप व निर्यात' : 'Backup & export', () => nav(const BackupExportScreen())),
      _menuTile(context, Icons.translate_rounded, 'Language / भाषा (${isHi ? 'हिन्दी' : 'English'})', () => _languageSelector(context, session)),
      _menuTile(
        context,
        Icons.security_rounded,
        isHi ? 'स्क्रीन सुरक्षा (स्क्रीनशॉट रोकें)' : 'Screen security (block capture)',
        () => session.setFlagSecure(!session.flagSecureEnabled),
        trailing: Switch(
          value: session.flagSecureEnabled,
          onChanged: (val) => session.setFlagSecure(val),
        ),
      ),
      if (session.hasPin)
        _menuTile(
          context,
          Icons.fingerprint_rounded,
          isHi ? 'बायोमेट्रिक अनलॉक' : 'Biometric unlock (Fingerprint/Face)',
          () => session.setBiometricEnabled(!session.biometricEnabled),
          trailing: Switch(
            value: session.biometricEnabled,
            onChanged: (val) => session.setBiometricEnabled(val),
          ),
        ),
      _menuTile(context, Icons.tune_rounded, isHi ? 'बिल सेटिंग्स' : 'Invoice settings', () => nav(const BusinessEditScreen())),
      _menuTile(
        context,
        Icons.gpp_good_rounded,
        isHi ? 'GSTIN ऑटो-फिल API कुंजी' : 'GSTIN Autofill API Key',
        () => _showGstnApiKeyDialog(context, session),
        trailing: session.gstnApiKey.isNotEmpty
            ? const Icon(Icons.check_circle_rounded, color: StitchColors.success, size: 18)
            : const Icon(Icons.warning_amber_rounded, color: StitchColors.warning, size: 18),
      ),
      _menuTile(
        context,
        Icons.lock_rounded,
        session.hasPin
            ? (isHi ? 'ऐप लॉक · पिन सेट है' : 'App lock · PIN set')
            : (isHi ? 'ऐप लॉक (पिन सेट करें)' : 'App lock (set PIN)'),
        () => _pinSettings(context),
      ),
      _menuTile(
        context,
        Icons.admin_panel_settings_rounded,
        isHi ? 'भूमिका: ${session.currentRole}' : 'Role: ${session.currentRole}',
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

  void _languageSelector(BuildContext context, Session session) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Choose Language / भाषा चुनें',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded, color: StitchColors.primary),
              title: const Text('English', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: session.localeCode == 'en'
                  ? const Icon(Icons.check_circle_rounded, color: StitchColors.success)
                  : null,
              onTap: () {
                session.setLocale('en');
                Navigator.pop(ctx);
                showAppMessage(context, 'Language set to English');
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: StitchColors.primary),
              title: const Text('हिन्दी (Hindi)', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: session.localeCode == 'hi'
                  ? const Icon(Icons.check_circle_rounded, color: StitchColors.success)
                  : null,
              onTap: () {
                session.setLocale('hi');
                Navigator.pop(ctx);
                showAppMessage(context, 'भाषा हिन्दी सेट की गई');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showGstnApiKeyDialog(BuildContext context, Session session) {
    final controller = TextEditingController(text: session.gstnApiKey);
    final isHi = session.localeCode == 'hi';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.gpp_good_rounded, color: StitchColors.primary),
            const SizedBox(width: 8),
            Text(
              isHi ? 'GSTIN ऑटो-फिल API कुंजी' : 'GSTIN Autofill API Key',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isHi
                  ? 'gstincheck.co.in से API कुंजी दर्ज करें ताकि GSTIN डालने पर पार्टी का नाम और पता अपने आप भर सके। यदि कुंजी नहीं है, तो ऐप स्मार्ट ऑफलाइन पद्धति का उपयोग करेगा।'
                  : 'Enter your free API key (e.g. from gstincheck.co.in) to automatically fetch full business names and addresses for any GSTIN. If blank, smart offline resolution is used.',
              style: const TextStyle(fontSize: 12, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'e.g. gstin_live_...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          if (session.gstnApiKey.isNotEmpty)
            TextButton(
              onPressed: () async {
                await session.saveGstnApiKey('');
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  showAppMessage(context, 'API key cleared');
                }
              },
              child: const Text('Clear', style: TextStyle(color: StitchColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await session.saveGstnApiKey(controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                showAppMessage(context, 'GSTIN API key saved');
              }
            },
            child: const Text('Save'),
          ),
        ],
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
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isOnline = sync.isOnline;
          final pending = sync.pendingCount;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isOnline ? StitchColors.success : StitchColors.warning)
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: isOnline ? StitchColors.success : StitchColors.warning,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? 'Cloud Sync Online' : 'Offline Mode (Local Safe)',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              isOnline
                                  ? 'Connected to backend server'
                                  : 'Changes will sync automatically when reconnected',
                              style: const TextStyle(fontSize: 12.5, color: StitchColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Check Connection',
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () async {
                          await sync.checkConnectivity();
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Server URL configuration card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StitchColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: StitchColors.outline),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dns_rounded, size: 20, color: StitchColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Backend Server URL',
                                  style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                              Text(
                                sync.apiClient.baseUrl,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _editServerUrl(context, sync, setModalState),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Sync queue metrics
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            color: StitchColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pending Changes',
                                  style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(
                                '$pending item${pending == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: pending > 0 ? StitchColors.warning : StitchColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            color: StitchColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: StitchColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Last Synced',
                                  style: TextStyle(fontSize: 11, color: StitchColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(
                                sync.lastSyncedAt == null
                                    ? 'Never'
                                    : DateFormat('hh:mm a').format(sync.lastSyncedAt!),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sync.lastError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: StitchColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: StitchColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sync.lastError!,
                              style: const TextStyle(fontSize: 11.5, color: StitchColors.error),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: sync.syncing
                          ? null
                          : () async {
                              await sync.syncNow(force: true);
                              setModalState(() {});
                              if (context.mounted) {
                                showAppMessage(
                                  context,
                                  sync.pendingCount == 0
                                      ? 'All changes synchronized successfully'
                                      : '${sync.pendingCount} change(s) remaining in queue',
                                );
                              }
                            },
                      icon: sync.syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(sync.syncing ? 'Synchronizing...' : 'Sync Now'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _editServerUrl(BuildContext context, SyncEngine sync, StateSetter setModalState) {
    final controller = TextEditingController(text: sync.apiClient.baseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter backend URL (e.g. http://10.0.2.2:4000 for emulator, or http://localhost:4000 via adb reverse).',
              style: TextStyle(fontSize: 12.5, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await sync.apiClient.setBaseUrl(newUrl);
                await sync.checkConnectivity();
                setModalState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save & Test'),
          ),
        ],
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
  bool exportingJson = false;

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

  Future<void> _exportJsonArchive() async {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;

    setState(() => exportingJson = true);
    try {
      final db = await AppDatabase.instance.database;
      final customers = await db.query('customers', where: 'business_id = ?', whereArgs: [businessId]);
      final products = await db.query('products', where: 'business_id = ?', whereArgs: [businessId]);
      final invoices = await db.query('invoices', where: 'business_id = ?', whereArgs: [businessId]);
      final payments = await db.query('payments', where: 'business_id = ?', whereArgs: [businessId]);
      final bankAccounts = await db.query('bank_accounts', where: 'business_id = ?', whereArgs: [businessId]);

      final archive = {
        'exportDate': DateTime.now().toIso8601String(),
        'app': 'Billket',
        'businessId': businessId,
        'customers': customers,
        'products': products,
        'invoices': invoices,
        'payments': payments,
        'bankAccounts': bankAccounts,
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(archive);
      final temp = await AppDatabase.instance.tempExportFile();
      final jsonFile = File('${temp.parent.path}/billket_business_archive.json');
      await jsonFile.writeAsString(jsonStr);

      await Share.shareXFiles(
        [XFile(jsonFile.path, mimeType: 'application/json', name: 'billket_business_archive.json')],
        subject: 'Billket Complete Business JSON Export',
        text: 'Complete structured business records archive from Billket.',
      );
    } catch (e) {
      if (mounted) showAppMessage(context, 'JSON export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => exportingJson = false);
    }
  }

  void _confirmDeleteBusinessAccount() {
    final session = context.read<Session>();
    final businessId = session.businessId;
    if (businessId == null) return;

    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Business & Wipe Data',
            style: TextStyle(color: StitchColors.error, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete all local invoices, customers, products, ledger entries, and audit records for this business.\n\nThis action cannot be undone.',
              style: TextStyle(fontSize: 13, color: StitchColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text('Type DELETE to confirm:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'DELETE',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StitchColors.error),
            onPressed: () async {
              if (controller.text.trim() == 'DELETE') {
                Navigator.pop(ctx);
                await session.deleteBusinessData(businessId);
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  showAppMessage(context, 'Business data wiped cleanly');
                }
              } else {
                showAppMessage(ctx, 'Type DELETE to proceed', error: true);
              }
            },
            child: const Text('Confirm Deletion'),
          ),
        ],
      ),
    );
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
                Text('Local database backup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
                  label: 'Export database (.db) file',
                  onPressed: _export,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.data_object_rounded, color: StitchColors.primary),
                SizedBox(width: 10),
                Text('JSON Data Archive (Portability)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              const Text('Export structured customer, invoice, and catalog records in machine-readable JSON format for audit or migration.',
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AsyncButton(
                  loading: exportingJson,
                  icon: Icons.file_download_outlined,
                  label: 'Export structured JSON archive',
                  onPressed: _exportJsonArchive,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.delete_forever_rounded, color: StitchColors.error),
                SizedBox(width: 10),
                Text('Compliance & Account Erasure', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: StitchColors.error)),
              ]),
              const SizedBox(height: 8),
              const Text('Permanently erase all business records and transaction ledgers stored on this device.',
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StitchColors.error,
                    side: const BorderSide(color: StitchColors.error),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Business & Clear Data'),
                  onPressed: _confirmDeleteBusinessAccount,
                ),
              ),
            ]),
          ),
        ]),
      );
}