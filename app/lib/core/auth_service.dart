import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';
import 'google_auth_config.dart';

enum AuthProviderType {
  google,
  phone,
  emailPassword;

  String get label {
    switch (this) {
      case AuthProviderType.google:
        return 'Google';
      case AuthProviderType.phone:
        return 'Mobile Phone (OTP)';
      case AuthProviderType.emailPassword:
        return 'Email & Password';
    }
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.provider = AuthProviderType.google,
  });

  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phone;
  final AuthProviderType provider;

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'photo_url': photoUrl,
        'phone': phone,
        'provider': provider.name,
      };

  factory AuthUser.fromMap(Map<String, dynamic> map) => AuthUser(
        id: map['id']?.toString() ?? '',
        email: map['email']?.toString() ?? '',
        displayName: map['display_name']?.toString() ?? map['name']?.toString() ?? '',
        photoUrl: map['photo_url']?.toString() ?? map['avatarUrl']?.toString(),
        phone: map['phone']?.toString(),
        provider: AuthProviderType.values.firstWhere(
          (p) => p.name == map['provider'],
          orElse: () => AuthProviderType.google,
        ),
      );
}

class AuthSessionResult {
  const AuthSessionResult({
    required this.token,
    required this.user,
    this.businessId,
    this.businessName,
    this.isNewUser = false,
  });

  final String token;
  final AuthUser user;
  final String? businessId;
  final String? businessName;
  final bool isNewUser;

  Map<String, dynamic> toMap() => {
        'token': token,
        'user': user.toMap(),
        'business_id': businessId,
        'business_name': businessName,
        'is_new_user': isNewUser,
      };

  factory AuthSessionResult.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> asStringMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    final userMap = asStringMap(map['user']);
    final businessMap = asStringMap(map['business']);
    return AuthSessionResult(
      token: map['token']?.toString() ?? '',
      user: AuthUser.fromMap(userMap),
      businessId: businessMap['id']?.toString() ?? map['business_id']?.toString(),
      businessName: businessMap['name']?.toString() ?? map['business_name']?.toString(),
      isNewUser: map['is_new_user'] == true,
    );
  }
}

/// Abstract upgradable authentication interface.
/// Easily permits adding Mobile Phone OTP, Email/Password, or Custom SAML/SSO
/// without modifying the core session or UI contracts.
abstract class AuthService {
  Future<AuthSessionResult> signInWithGoogle({ApiClient? apiClient, String? businessName});
  Future<AuthSessionResult> signInWithPhone({required String phone, required String otp, String? sessionId, ApiClient? apiClient});
  Future<Map<String, dynamic>> requestPhoneOtp(String phone, {ApiClient? apiClient});
  Future<AuthSessionResult> register({
    required String name,
    required String email,
    required String password,
    String? businessName,
    ApiClient? apiClient,
  });
  Future<AuthSessionResult> login({
    required String email,
    required String password,
    ApiClient? apiClient,
  });
  Future<void> signOut();
}

class CloudAuthService implements AuthService {
  CloudAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(
      clientId: GoogleAuthConfig.platformClientId,
      serverClientId: GoogleAuthConfig.serverClientId,
    );
    _initialized = true;
  }

  @override
  Future<AuthSessionResult> signInWithGoogle({ApiClient? apiClient, String? businessName}) async {
    try {
      await _ensureInitialized();
      bool isSupported = false;
      try {
        isSupported = _googleSignIn.supportsAuthenticate();
      } catch (_) {
        isSupported = false;
      }
      if (!isSupported) {
        throw Exception(
          'GOOGLE_SIGN_IN_UNSUPPORTED: Google Sign-In is not supported on this platform directly.',
        );
      }
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'openid', 'profile'],
      );
      final auth = account.authentication;
      final email = account.email;
      final name = account.displayName ?? account.email.split('@').first;
      final photoUrl = account.photoUrl;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
          'MISSING_ID_TOKEN: Google did not return an OpenID token. Confirm the Web client ID is passed as serverClientId.',
        );
      }

      // Exchange with backend if API client is provided
      if (apiClient != null) {
        await apiClient.ensureReady();
        final res = await apiClient.loginWithGoogle(
          email: email,
          name: name,
          avatarUrl: photoUrl,
          idToken: idToken,
          businessName: businessName,
        );
        return res;
      }

      // Offline / standalone session fallback
      return AuthSessionResult(
        token: 'local_google_token_${account.id}',
        user: AuthUser(
          id: account.id,
          email: email,
          displayName: name,
          photoUrl: photoUrl,
          provider: AuthProviderType.google,
        ),
        businessName: businessName ?? "$name's Business",
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CloudAuthService] Google sign-in error: $e');
      }
      rethrow;
    }
  }

  /// Upgradable Mock/Simulation Sign-In for environments without Google Play Services
  /// (e.g., Windows Desktop, headless emulator, or offline developer testing)
  Future<AuthSessionResult> mockSignInWithGoogle({
    String email = 'business.owner@gmail.com',
    String name = 'Rahul Sharma',
    String? avatarUrl,
    ApiClient? apiClient,
    String? businessName,
  }) async {
    if (apiClient != null) {
      await apiClient.ensureReady();
      return await apiClient.loginWithGoogle(
        email: email,
        name: name,
        avatarUrl: avatarUrl,
        idToken: 'mock_google_id_token_${DateTime.now().millisecondsSinceEpoch}',
        businessName: businessName,
      );
    }

    return AuthSessionResult(
      token: 'mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
      user: AuthUser(
        id: 'mock_google_uid_101',
        email: email,
        displayName: name,
        photoUrl: avatarUrl,
        provider: AuthProviderType.google,
      ),
      businessName: businessName ?? "$name's Business",
    );
  }

  /// Upgradable Phone Authentication Hook:
  /// When mobile-number OTP is enabled (AWS SNS, Twilio, Firebase Phone Auth),
  /// this method seamlessly connects to the verification gateway.
  @override
  Future<AuthSessionResult> signInWithPhone({
    required String phone,
    required String otp,
    String? sessionId,
    ApiClient? apiClient,
  }) async {
    if (apiClient != null) {
      await apiClient.ensureReady();
      return await apiClient.loginWithPhone(phone: phone, otp: otp, sessionId: sessionId);
    }

    // Default mock verification: '1234' or '0000'
    if (otp != '1234' && otp != '0000') {
      throw Exception('INVALID_OTP: Please enter the valid code.');
    }

    final cleanPhone = phone.trim();
    return AuthSessionResult(
      token: 'local_phone_token_${DateTime.now().millisecondsSinceEpoch}',
      user: AuthUser(
        id: 'phone_${cleanPhone.replaceAll(RegExp(r'[^0-9]'), '')}',
        email: '$cleanPhone@phone.billapp.in',
        displayName: 'User ${cleanPhone.length >= 4 ? cleanPhone.substring(cleanPhone.length - 4) : cleanPhone}',
        phone: cleanPhone,
        provider: AuthProviderType.phone,
      ),
      businessName: 'My Business',
    );
  }

  @override
  Future<Map<String, dynamic>> requestPhoneOtp(String phone, {ApiClient? apiClient}) async {
    if (apiClient != null) {
      return await apiClient.requestPhoneOtp(phone);
    }
    return {'success': true, 'isTestMode': true};
  }

  @override
  Future<AuthSessionResult> register({
    required String name,
    required String email,
    required String password,
    String? businessName,
    ApiClient? apiClient,
  }) async {
    if (apiClient != null) {
      await apiClient.ensureReady();
      return await apiClient.registerWithEmail(
        name: name,
        email: email,
        password: password,
        businessName: businessName,
      );
    }

    return AuthSessionResult(
      token: 'local_token_${DateTime.now().millisecondsSinceEpoch}',
      user: AuthUser(
        id: 'user_${email.hashCode}',
        email: email,
        displayName: name,
        provider: AuthProviderType.emailPassword,
      ),
      businessName: businessName ?? "$name's Business",
    );
  }

  @override
  Future<AuthSessionResult> login({
    required String email,
    required String password,
    ApiClient? apiClient,
  }) async {
    if (apiClient != null) {
      await apiClient.ensureReady();
      return await apiClient.loginWithEmail(email: email, password: password);
    }

    return AuthSessionResult(
      token: 'local_token_${DateTime.now().millisecondsSinceEpoch}',
      user: AuthUser(
        id: 'user_${email.hashCode}',
        email: email,
        displayName: email.split('@').first,
        provider: AuthProviderType.emailPassword,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}

