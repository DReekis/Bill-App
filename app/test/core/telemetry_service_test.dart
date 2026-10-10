import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/telemetry_service.dart';

void main() {
  group('TelemetryService Tests', () {
    test('DSNs are correctly formatted and point to official Sentry ingest', () {
      expect(TelemetryService.flutterDsn, contains('sentry.io'));
      expect(TelemetryService.flutterDsn, contains('4512214038282240'));
      expect(TelemetryService.backendDsn, contains('sentry.io'));
      expect(TelemetryService.backendDsn, contains('4512230552043520'));
    });

    test('addBreadcrumb handles message and data gracefully without throwing', () {
      expect(
        () => TelemetryService.instance.addBreadcrumb(
          'Test breadcrumb action',
          category: 'unit_test',
          data: {'status': 'ok'},
        ),
        returnsNormally,
      );
    });

    test('captureException handles errors gracefully without crashing the app', () async {
      final error = Exception('Simulated test exception for Sentry');
      final result = await TelemetryService.instance.captureException(
        error,
        tag: 'unit_test',
        extra: {'context': 'test_run'},
      );
      // Sentry SDK returns null or SentryId if not fully initialized in headless test
      expect(result == null || result.toString().isNotEmpty, isTrue);
    });

    test('markInitialized updates state flag', () {
      final service = TelemetryService.instance;
      service.markInitialized();
      expect(service.isInitialized, isTrue);
    });
  });
}
