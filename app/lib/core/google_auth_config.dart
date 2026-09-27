import 'package:flutter/foundation.dart';

/// Secure Google OAuth Configuration for Billket.
///
/// Public Client IDs:
/// - Android Client ID: Bound to package `com.pricepilot.bill` and signing SHA-1 fingerprint.
/// - iOS Client ID: Bound to bundle ID `com.pricepilot.bill`.
/// - Desktop / Web Client ID: Bound to Web application client credentials.
/// - Web / Server Client ID: Target audience for backend cryptographically verified idTokens.
///
/// Note: The Google OAuth Client Secret (GOCSPX-...) is CONFIDENTIAL
/// and is stored strictly on the backend server (`backend/.env`).
/// It is NEVER included in client code or application bundles.
class GoogleAuthConfig {
  const GoogleAuthConfig._();

  /// Server Client ID (Web Application Client ID)
  /// Used as serverClientId to obtain an OpenID Connect idToken verified by the backend.
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '594956382165-jgm12poc8g1lmtj38ilj87cu8upggban.apps.googleusercontent.com',
  );

  /// Android Client ID (bound to package com.pricepilot.bill & SHA-1 signature)
  static const String androidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '594956382165-f7qljarc4oepch4do89hmpe1sf2ro2is.apps.googleusercontent.com',
  );

  /// iOS Client ID (bound to bundle ID com.pricepilot.bill)
  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '594956382165-c8pqnkq6u5u75ldgohnuvjgv30t7i0pu.apps.googleusercontent.com',
  );

  /// Desktop / Web Client ID
  static const String desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '1088562819881-tesapmissm77nd7o5maom90nh4sjv87h.apps.googleusercontent.com',
  );

  /// Android application package name
  static const String appPackageName = 'com.pricepilot.bill';

  /// Active debug/build signing certificate SHA-1 fingerprint
  static const String debugSha1 = '7D:C8:69:0D:50:7F:30:38:A4:15:2E:C7:DE:0C:5E:40:B9:EB:68:E7';

  /// Active debug/build signing certificate SHA-256 fingerprint
  static const String debugSha256 =
      'CF:84:B7:DC:0C:C9:E7:54:9E:3B:DA:46:DC:6D:70:C1:CA:39:5A:A4:32:E1:4A:1F:55:5C:5A:93:E7:0A:A1:CB';

  /// Returns the appropriate platform client ID
  static String? get platformClientId {
    if (kIsWeb) {
      return desktopClientId;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // On Android, Google Play Services auto-discovers the client ID using
        // package name + SHA-1 certificate. Passing an Android client ID as
        // clientId to initialize() causes error 16 (Account reauth failed).
        return null;
      case TargetPlatform.iOS:
        return iosClientId;
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return desktopClientId;
      default:
        return null;
    }
  }
}
