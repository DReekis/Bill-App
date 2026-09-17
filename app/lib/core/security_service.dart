import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const MethodChannel _channel = MethodChannel('com.pricepilot.bill/security');
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Toggles Android FLAG_SECURE to block screen recording and screenshots.
  Future<bool> setFlagSecure(bool enabled) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('setFlagSecure', {'enabled': enabled});
      return res ?? false;
    } catch (e) {
      debugPrint('SecurityService.setFlagSecure error: $e');
      return false;
    }
  }

  /// Checks if the hardware supports biometric authentication (Fingerprint / Face).
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      debugPrint('SecurityService.canCheckBiometrics error: $e');
      return false;
    }
  }

  /// Prompts user to authenticate with Fingerprint / Face.
  Future<bool> authenticateBiometric({String reason = 'Authenticate to unlock Billket'}) async {
    if (kIsWeb) return false;
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
      );
      return didAuthenticate;
    } catch (e) {
      debugPrint('SecurityService.authenticateBiometric error: $e');
      return false;
    }
  }
}
