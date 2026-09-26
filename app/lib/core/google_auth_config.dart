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
    defaultValue: '594956382165-jgm12poc8g1lmtj38ilj87cu8upggban.apps.googleusercontent.com',
  );

  /// Returns the appropriate platform client ID
  static String? get platformClientId {
    if (kIsWeb) {
      return desktopClientId;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return androidClientId;
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
