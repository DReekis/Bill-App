import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  ApiClient({String? baseUrl}) : _baseUrl = _cachedBaseUrl ?? baseUrl ?? defaultBaseUrl {
    _loadBaseUrl();
  }

  static const String _kBaseUrlKey = 'api.base_url';
  static String? _cachedBaseUrl;
  String _baseUrl;
  String? _token;
  String? _businessId;

  String get baseUrl => _baseUrl;

  Future<void> _loadBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kBaseUrlKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _baseUrl = saved.trim();
        _cachedBaseUrl = saved.trim();
      }
    } catch (_) {}
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim();
    if (clean.isNotEmpty) {
      _baseUrl = clean;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kBaseUrlKey, clean);
      } catch (_) {}
    }
  }

  void setToken(String? token) => _token = token;
  void setBusinessId(String? businessId) => _businessId = businessId;
  void clearToken() => _token = null;

  Map<String, String> _headers({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    if (_businessId != null && _businessId!.isNotEmpty) {
      headers['X-Business-Id'] = _businessId!;
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Future<bool> ping() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 600));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return await http
        .post(uri, headers: _headers(extra: headers), body: jsonEncode(body))
        .timeout(timeout);
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return await http
        .get(uri, headers: _headers(extra: headers))
        .timeout(timeout);
  }

  Future<AuthSessionResult> loginWithGoogle({
    required String email,
    required String name,
    String? avatarUrl,
    String? idToken,
    String? businessName,
  }) async {
    final res = await post('/api/v1/auth/google', {
      'email': email,
      'name': name,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (idToken != null) 'idToken': idToken,
      if (businessName != null) 'businessName': businessName,
    });

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = AuthSessionResult.fromMap(data);
      setToken(result.token);
      if (result.businessId != null) {
        setBusinessId(result.businessId);
      }
      return result;
    }

    final err = jsonDecode(res.body);
    throw Exception(err is Map ? (err['error'] ?? 'Google authentication failed') : 'Google authentication failed');
  }

  Future<AuthSessionResult> loginWithPhone({
    required String phone,
    required String otp,
    String? name,
  }) async {
    final res = await post('/api/v1/auth/phone/verify', {
      'phone': phone,
      'otp': otp,
      if (name != null) 'name': name,
    });

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = AuthSessionResult.fromMap(data);
      setToken(result.token);
      if (result.businessId != null) {
        setBusinessId(result.businessId);
      }
      return result;
    }

    final err = jsonDecode(res.body);
    throw Exception(err is Map ? (err['error'] ?? 'Phone verification failed') : 'Phone verification failed');
  }

  Future<void> requestPhoneOtp(String phone) async {
    try {
      await post('/api/v1/auth/phone/otp', {'phone': phone});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> uploadBackup({
    required String base64Data,
    String? filename,
    String? checksum,
    String? deviceName,
    String? notes,
  }) async {
    final res = await post('/api/v1/backup/upload', {
      'base64Data': base64Data,
      if (filename != null) 'filename': filename,
      if (checksum != null) 'checksum': checksum,
      if (deviceName != null) 'deviceName': deviceName,
      if (notes != null) 'notes': notes,
    });
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body);
    throw Exception(err is Map ? (err['error'] ?? 'Backup upload failed') : 'Backup upload failed');
  }

  Future<List<Map<String, dynamic>>> fetchBackups() async {
    final res = await get('/api/v1/backup/list');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['backups'] as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> downloadBackup(String backupId) async {
    final res = await get('/api/v1/backup/download/$backupId');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['backup'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('Failed to download backup');
  }

  Future<void> deleteBackup(String backupId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/backup/$backupId');
    await http.delete(uri, headers: _headers());
  }
}

