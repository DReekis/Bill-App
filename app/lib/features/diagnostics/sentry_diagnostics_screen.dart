import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/telemetry_service.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class SentryDiagnosticsScreen extends StatefulWidget {
  const SentryDiagnosticsScreen({super.key});

  @override
  State<SentryDiagnosticsScreen> createState() => _SentryDiagnosticsScreenState();
}

class _SentryDiagnosticsScreenState extends State<SentryDiagnosticsScreen> {
  bool _testingClient = false;
  bool _testingBackend = false;
  bool _testingException = false;
  String? _lastClientEventId;
  String? _lastBackendEventId;
  String? _lastExceptionEventId;
  String? _statusLog;

  Future<void> _sendClientTestAlert() async {
    setState(() {
      _testingClient = true;
      _statusLog = 'Dispatching test telemetry event to Sentry...';
    });
    try {
      final session = context.read<Session>();
      final eventId = await TelemetryService.instance.sendTestClientAlert(
        notes: 'Manual Sentry diagnostic triggered from Settings / Diagnostics',
        userEmail: session.cloudEmail,
        role: session.currentRole,
        businessId: session.businessId,
      );
      if (!mounted) return;
      setState(() {
        _lastClientEventId = eventId;
        _statusLog = 'Client alert dispatched successfully! Event ID: $eventId';
      });
      showAppMessage(context, 'Flutter Sentry alert dispatched successfully ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusLog = 'Client alert dispatch failed: $e');
      showAppMessage(context, 'Failed to send Sentry alert: $e', error: true);
    } finally {
      if (mounted) setState(() => _testingClient = false);
    }
  }

  Future<void> _sendBackendTestAlert() async {
    setState(() {
      _testingBackend = true;
      _statusLog = 'Triggering cloud backend Sentry test endpoint...';
    });
    try {
      final session = context.read<Session>();
      final res = await TelemetryService.instance.sendTestBackendAlert(client: session.client);
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'];
        final eventId = data is Map ? data['eventId']?.toString() : 'Dispatched';
        setState(() {
          _lastBackendEventId = eventId;
          _statusLog = 'Backend Sentry alert received by AWS gateway! Event ID: $eventId';
        });
        showAppMessage(context, 'AWS Backend Sentry alert dispatched successfully ✓');
      } else {
        setState(() => _statusLog = 'Backend returned HTTP ${res['statusCode']}: ${res['error']}');
        showAppMessage(context, 'Backend test failed with status ${res['statusCode']}', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusLog = 'Backend alert dispatch error: $e');
      showAppMessage(context, 'Failed to reach backend: $e', error: true);
    } finally {
      if (mounted) setState(() => _testingBackend = false);
    }
  }

  Future<void> _simulateHandledException() async {
    setState(() {
      _testingException = true;
      _statusLog = 'Simulating handled exception with stack trace...';
    });
    try {
      throw StateError('[Handled Diagnostic Error] Simulated exception for Phase 5 verification');
    } catch (err, stack) {
      final sentryId = await TelemetryService.instance.captureException(
        err,
        stackTrace: stack,
        tag: 'diagnostics_screen',
        extra: {
          'triggered_by': 'user_action',
          'route': '/diagnostics/sentry',
          'time': DateTime.now().toIso8601String(),
        },
      );
      if (!mounted) return;
      setState(() {
        _lastExceptionEventId = sentryId?.toString() ?? 'Captured';
        _statusLog = 'Exception captured and transmitted to Sentry. Event ID: $_lastExceptionEventId';
      });
      showAppMessage(context, 'Handled exception logged to Sentry dashboard ✓');
    } finally {
      if (mounted) setState(() => _testingException = false);
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showAppMessage(context, '$label copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sentry Telemetry & Health', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Telemetry status badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF362D59), Color(0xFF58478A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF362D59).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Sentry Active',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CONNECTED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automated crash reporting, stack traces, and health telemetry are streaming in real-time.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Configured Endpoints Card
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configured DSN Endpoints', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _buildDsnTile(
                  label: 'Flutter Client DSN',
                  dsn: TelemetryService.flutterDsn,
                  icon: Icons.phone_android_rounded,
                  color: const Color(0xFF0284C7),
                ),
                const Divider(height: 20),
                _buildDsnTile(
                  label: 'AWS Node.js Backend DSN',
                  dsn: TelemetryService.backendDsn,
                  icon: Icons.cloud_outlined,
                  color: const Color(0xFF16A34A),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Diagnostic Actions Card
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Diagnostic Alert Tests', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Trigger instant telemetry events to verify they show up in your Sentry.io issues and performance tabs.',
                  style: TextStyle(fontSize: 12, color: StitchColors.textSecondary),
                ),
                const SizedBox(height: 16),

                // Button 1: Client Alert
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF362D59),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _testingClient ? null : _sendClientTestAlert,
                    icon: _testingClient
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _testingClient ? 'Dispatching to Sentry...' : '1. Test Flutter Client Alert',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (_lastClientEventId != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: StitchColors.success, size: 14),
                      const SizedBox(width: 4),
                      Text('Event ID: $_lastClientEventId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // Button 2: Simulate Exception
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      foregroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _testingException ? null : _simulateHandledException,
                    icon: _testingException
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)))
                        : const Icon(Icons.bug_report_outlined, size: 18),
                    label: Text(
                      _testingException ? 'Capturing Stack Trace...' : '2. Simulate Exception with Stack Trace',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (_lastExceptionEventId != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: StitchColors.success, size: 14),
                      const SizedBox(width: 4),
                      Text('Exception Event ID: $_lastExceptionEventId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // Button 3: Backend Alert
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _testingBackend ? null : _sendBackendTestAlert,
                    icon: _testingBackend
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(
                      _testingBackend ? 'Calling AWS Backend...' : '3. Test AWS Backend Cloud Alert',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (_lastBackendEventId != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: StitchColors.success, size: 14),
                      const SizedBox(width: 4),
                      Text('Backend Event ID: $_lastBackendEventId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StitchColors.textSecondary)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Real-time Status Console
          if (_statusLog != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Telemetry Log Output',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusLog!,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDsnTile({
    required String label,
    required String dsn,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dsn,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: StitchColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _copy(dsn, label),
                child: const Icon(Icons.copy_rounded, size: 14, color: StitchColors.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
