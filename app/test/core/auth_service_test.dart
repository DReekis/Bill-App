import 'dart:convert';
import 'package:billket/core/auth_service.dart';
import 'package:billket/core/google_auth_config.dart';
import 'package:billket/core/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Auth Domain Models & Serialization Tests', () {
    test('AuthUser serialization and deserialization works correctly', () {
      const user = AuthUser(
        id: 'usr_google_123',
        email: 'rahul.traders@gmail.com',
        displayName: 'Rahul Traders',
        photoUrl: 'https://lh3.googleusercontent.com/a/photo.jpg',
        phone: '9876543210',
        provider: AuthProviderType.google,
      );

      final map = user.toMap();
      expect(map['id'], 'usr_google_123');
      expect(map['email'], 'rahul.traders@gmail.com');
      expect(map['display_name'], 'Rahul Traders');
      expect(map['photo_url'], 'https://lh3.googleusercontent.com/a/photo.jpg');
      expect(map['provider'], 'google');

      final restored = AuthUser.fromMap(map);
      expect(restored.id, user.id);
      expect(restored.email, user.email);
      expect(restored.displayName, user.displayName);
      expect(restored.photoUrl, user.photoUrl);
      expect(restored.provider, AuthProviderType.google);
    });

    test('AuthSessionResult converts from backend JSON response format', () {
      final backendJson = {
        'token': 'jwt.token.signed.xyz',
        'user': {
          'id': 'usr_999',
          'name': 'Priya Patel',
          'email': 'priya@gmail.com',
          'avatarUrl': 'https://photos.google.com/avatar.png',
        },
        'business': {
          'id': 'biz_cloud_456',
          'name': 'Priya Super Store',
        },
        'is_new_user': false,
      };

      final result = AuthSessionResult.fromMap(backendJson);
      expect(result.token, 'jwt.token.signed.xyz');
      expect(result.user.id, 'usr_999');
      expect(result.user.displayName, 'Priya Patel');
      expect(result.user.email, 'priya@gmail.com');
      expect(result.user.photoUrl, 'https://photos.google.com/avatar.png');
      expect(result.businessId, 'biz_cloud_456');
      expect(result.businessName, 'Priya Super Store');
    });

    test('AuthSessionResult.fromMap accepts jsonDecode nested maps', () {
      final decoded = jsonDecode('''
        {
          "token": "jwt.cloud.token",
          "user": {"id": "u1", "name": "Ravi", "email": "ravi@gmail.com", "avatarUrl": "https://x/a.png"},
          "business": {"id": "biz_1", "name": "Ravi Store"}
        }
      ''') as Map<String, dynamic>;

      final result = AuthSessionResult.fromMap(decoded);
      expect(result.token, 'jwt.cloud.token');
      expect(result.user.displayName, 'Ravi');
      expect(result.user.photoUrl, 'https://x/a.png');
      expect(result.businessId, 'biz_1');
    });
  });

  group('Session Cloud Account Linking Tests', () {
    test('Session links and unlinks cloud session cleanly', () async {
      final session = Session();
      expect(session.isCloudLinked, isFalse);

      const authResult = AuthSessionResult(
        token: 'cloud_jwt_session_token',
        user: AuthUser(
          id: 'user_cloud_777',
          email: 'store.owner@gmail.com',
          displayName: 'Amit Verma',
          photoUrl: 'https://avatar.google.com/amit.png',
          provider: AuthProviderType.google,
        ),
        businessId: 'biz_remote_101',
        businessName: 'Amit General Store',
      );

      var notified = false;
      session.addListener(() {
        notified = true;
      });

      await session.linkCloudSession(authResult);

      expect(session.isCloudLinked, isTrue);
      expect(session.token, 'cloud_jwt_session_token');
      expect(session.cloudUserId, 'user_cloud_777');
      expect(session.cloudEmail, 'store.owner@gmail.com');
      expect(session.cloudName, 'Amit Verma');
      expect(session.cloudAvatarUrl, 'https://avatar.google.com/amit.png');
      expect(session.cloudProvider, 'google');
      expect(notified, isTrue);

      // Now unlink
      notified = false;
      await session.unlinkCloudSession();

      expect(session.isCloudLinked, isFalse);
      expect(session.token, isNull);
      expect(session.cloudEmail, isNull);
      expect(session.cloudName, isNull);
      expect(notified, isTrue);
    });
  });

  group('CloudAuthService & Upgradable Architecture Tests', () {
    test('mockSignInWithGoogle returns valid session result', () async {
      final auth = CloudAuthService();
      final result = await auth.mockSignInWithGoogle(
        email: 'test.user@gmail.com',
        name: 'Test Owner',
      );

      expect(result.token, isNotEmpty);
      expect(result.user.email, 'test.user@gmail.com');
      expect(result.user.displayName, 'Test Owner');
      expect(result.user.provider, AuthProviderType.google);
    });

    test('Upgradable phone auth verifies valid OTP 1234', () async {
      final auth = CloudAuthService();
      final result = await auth.signInWithPhone(
        phone: '9876543210',
        otp: '1234',
      );

      expect(result.user.phone, '9876543210');
      expect(result.user.provider, AuthProviderType.phone);
    });

    test('Upgradable phone auth rejects invalid OTP', () async {
      final auth = CloudAuthService();
      expect(
        () => auth.signInWithPhone(phone: '9876543210', otp: '9999'),
        throwsA(isA<Exception>()),
      );
    });

    test('GoogleAuthConfig supplies valid client IDs for all platforms', () {
      expect(GoogleAuthConfig.serverClientId, contains('594956382165-jgm12poc8g1lmtj38ilj87cu8upggban'));
      expect(GoogleAuthConfig.androidClientId, contains('594956382165-f7qljarc4oepch4do89hmpe1sf2ro2is'));
      expect(GoogleAuthConfig.iosClientId, contains('594956382165-c8pqnkq6u5u75ldgohnuvjgv30t7i0pu'));
      expect(GoogleAuthConfig.desktopClientId, contains('594956382165-jgm12poc8g1lmtj38ilj87cu8upggban'));
      // platformClientId is null on Android (Google Play Services auto-discovers via SHA-1)
      // On desktop/test runner it returns the desktop/web client ID
    });
  });
}
