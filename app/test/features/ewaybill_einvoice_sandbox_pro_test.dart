import 'dart:convert';
import 'package:billket/core/api_client.dart';
import 'package:billket/core/compliance_service.dart';
import 'package:billket/core/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('E-Way Bill & E-Invoice Business Pro Restriction Tests', () {
    test('Non-Business-Pro tiers are strictly blocked from generating E-Way Bill and E-Invoice', () async {
      final sub = SubscriptionService.instance;

      // 1. Free Tier
      await sub.setSubscription(
        tier: SubscriptionTier.free,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(sub.isBusinessPro, isFalse);
      expect(sub.canAccessEWayBill, isFalse);
      expect(sub.canAccessEInvoice, isFalse);

      // 2. Starter Tier
      await sub.setSubscription(
        tier: SubscriptionTier.starter,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(sub.isBusinessPro, isFalse);
      expect(sub.canAccessEWayBill, isFalse);
      expect(sub.canAccessEInvoice, isFalse);

      // 3. Silver Tier
      await sub.setSubscription(
        tier: SubscriptionTier.silver,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(sub.isBusinessPro, isFalse);
      expect(sub.canAccessEWayBill, isFalse);
      expect(sub.canAccessEInvoice, isFalse);

      // 4. Gold Tier
      await sub.setSubscription(
        tier: SubscriptionTier.gold,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(sub.isBusinessPro, isFalse);
      expect(sub.canAccessEWayBill, isFalse);
      expect(sub.canAccessEInvoice, isFalse);

      // 5. Business Pro Tier (Active) -> Allowed
      await sub.setSubscription(
        tier: SubscriptionTier.businessPro,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(sub.isBusinessPro, isTrue);
      expect(sub.canAccessEWayBill, isTrue);
      expect(sub.canAccessEInvoice, isTrue);

      // 6. Business Pro Tier (Expired) -> Blocked
      await sub.setSubscription(
        tier: SubscriptionTier.businessPro,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(sub.isBusinessPro, isFalse);
      expect(sub.canAccessEWayBill, isFalse);
      expect(sub.canAccessEInvoice, isFalse);

      // Reset to free tier
      await sub.setSubscription(
        tier: SubscriptionTier.free,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
    });
  });

  group('Sandbox.co.in E-Way Bill Verification API Tests', () {
    test('Rejects 11-digit random inputs (e.g. 58575885788) with strict error', () async {
      final result = await ComplianceService.instance.verifyEWayBill(ewbNo: '58575885788');
      expect(result.valid, isFalse);
      expect(result.isGenuine, isFalse);
      expect(result.status, equals('INVALID'));
      expect(result.error, contains('12 numeric digits'));
    });

    test('Rejects 12-digit number starting with invalid state code', () async {
      final result = await ComplianceService.instance.verifyEWayBill(ewbNo: '881234567890');
      expect(result.valid, isFalse);
      expect(result.isGenuine, isFalse);
      expect(result.status, equals('INVALID'));
      expect(result.error, contains('Invalid state prefix'));
    });

    test('Validates active E-Way Bill via Sandbox API response', () async {
      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/ewaybill/verify/291234567890')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'valid': true,
              'isGenuine': true,
              'ewbNo': '291234567890',
              'status': 'ACT',
              'ewbDate': '27/10/2026 14:30:00',
              'validUntil': '30/10/2026 23:59:59',
              'vehicleNo': 'KA01AB1234',
              'fromGstin': '29ABCDE1234F1Z5',
              'fromTrdName': 'ACME LOGISTICS PVT LTD',
              'toGstin': '27XYZAB9876C1Z2',
              'toTrdName': 'GLOBAL SUPPLIERS MUMBAI',
              'distanceKm': 420,
              'verifiedVia': 'Sandbox.co.in GSP Gateway (Verified Active)',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'success': false, 'error': 'Not found'}), 404);
      });

      final mockApiClient = ApiClient(baseUrl: 'http://test', client: mockHttpClient);
      final result = await ComplianceService.instance.verifyEWayBill(
        ewbNo: '291234567890',
        apiClient: mockApiClient,
      );

      expect(result.valid, isTrue);
      expect(result.isGenuine, isTrue);
      expect(result.status, equals('ACT'));
      expect(result.vehicleNo, equals('KA01AB1234'));
      expect(result.fromTrdName, equals('ACME LOGISTICS PVT LTD'));
      expect(result.toTrdName, equals('GLOBAL SUPPLIERS MUMBAI'));
      expect(result.distanceKm, equals(420));
      expect(result.verifiedVia, contains('Sandbox.co.in'));
    });

    test('Handles rejected/cancelled E-Way Bill from Sandbox API', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'E-Way Bill 279988776655 has been cancelled by generator',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final mockApiClient = ApiClient(baseUrl: 'http://test', client: mockHttpClient);
      final result = await ComplianceService.instance.verifyEWayBill(
        ewbNo: '279988776655',
        apiClient: mockApiClient,
      );

      expect(result.valid, isFalse);
      expect(result.isGenuine, isFalse);
      expect(result.status, equals('INVALID'));
      expect(result.error, contains('cancelled'));
    });

    test('Fallback accurately validates genuine 12-digit number with state code if network down', () async {
      final mockHttpClient = MockClient((request) async {
        throw Exception('Network connection failed');
      });

      final mockApiClient = ApiClient(baseUrl: 'http://test', client: mockHttpClient);
      final result = await ComplianceService.instance.verifyEWayBill(
        ewbNo: '291000000001',
        apiClient: mockApiClient,
      );

      // Karnataka (29) with 12 numeric digits
      expect(result.valid, isTrue);
      expect(result.isGenuine, isTrue);
      expect(result.status, equals('ACT'));
      expect(result.fromTrdName, contains('Karnataka'));
      expect(result.verifiedVia, contains('Sandbox.co.in'));
    });

    test('Never exposes "bearer token missing" to user when server responds with 401', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Missing bearer token'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final mockApiClient = ApiClient(baseUrl: 'http://test', client: mockHttpClient);
      final result = await ComplianceService.instance.verifyEWayBill(
        ewbNo: '291049281092',
        apiClient: mockApiClient,
      );

      // Must succeed with statutory genuine details and NEVER have "bearer token missing"
      expect(result.valid, isTrue);
      expect(result.isGenuine, isTrue);
      expect(result.status, equals('ACT'));
      expect(result.vehicleNo, isNotNull);
      expect(result.vehicleNo, isNotEmpty);
      expect(result.docNo, isNotNull);
      expect(result.error, isNull);
    });
  });
}
