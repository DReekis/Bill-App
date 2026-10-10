import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'api_client.dart';

/// Centralized Telemetry & Error Reporting service wrapping Sentry.
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  static const String flutterDsn =
      'https://5c8ca4520327b0fc092eb21c9584ed14@o4512214034677760.ingest.us.sentry.io/4512214038282240';
  static const String backendDsn =
      'https://b81fe0dccbe91fc92f403d905cdf88d4@o4512214034677760.ingest.us.sentry.io/4512230552043520';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  void markInitialized() {
    _initialized = true;
  }

  /// Records a breadcrumb representing a user action, sync transition, or database step.
  void addBreadcrumb(
    String message, {
    String? category,
    SentryLevel? level,
    Map<String, dynamic>? data,
  }) {
    try {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: category ?? 'app.lifecycle',
          level: level ?? SentryLevel.info,
          data: data,
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {
      // Never crash the host application during telemetry logging
    }
  }

  /// Captures an handled or unhandled exception with context and stack trace.
  Future<SentryId?> captureException(
    dynamic exception, {
    dynamic stackTrace,
    String? tag,
    Map<String, dynamic>? extra,
  }) async {
    try {
      return await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) {
          if (tag != null) scope.setTag('feature', tag);
          if (extra != null) {
            scope.setContexts('extra', extra);
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to dispatch exception to Sentry: $e');
      }
      return null;
    }
  }

  /// Sends a manual test diagnostic event from the Flutter client to verify Sentry ingest.
  Future<String> sendTestClientAlert({
    String? notes,
    String? userEmail,
    String? role,
    int? businessId,
  }) async {
    addBreadcrumb('Triggering manual diagnostic test from TelemetryService', category: 'diagnostic');
    final eventId = await Sentry.captureMessage(
      '[Flutter Diagnostic Telemetry] Manual Sentry alert test from Billket device',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('environment', kReleaseMode ? 'production' : 'development');
        scope.setTag('platform', defaultTargetPlatform.name);
        scope.setTag('role', role ?? 'Owner');
        if (businessId != null) scope.setTag('businessId', businessId.toString());
        if (userEmail != null) scope.setUser(SentryUser(email: userEmail));
        scope.setContexts('diagnostics', {
          'notes': notes ?? 'User verified Phase 5 Sentry integration',
          'timestamp': DateTime.now().toIso8601String(),
        });
      },
    );
    return eventId.toString();
  }

  /// Sends a manual test diagnostic request to the AWS backend gateway to test cloud Sentry ingest.
  Future<Map<String, dynamic>> sendTestBackendAlert({ApiClient? client}) async {
    final c = client ?? ApiClient.instance;
    final res = await c.post('/api/v1/diagnostics/sentry-test', {
      'timestamp': DateTime.now().toIso8601String(),
      'source': 'Flutter Client Diagnostic Sheet',
    });
    if (res.statusCode == 200) {
      return {
        'success': true,
        'statusCode': res.statusCode,
        'data': res.body,
      };
    } else {
      return {
        'success': false,
        'statusCode': res.statusCode,
        'error': res.body,
      };
    }
  }
}
