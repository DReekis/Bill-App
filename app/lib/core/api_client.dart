import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://43.204.237.49',
  );

  static final ApiClient instance = ApiClient();

  ApiClient({String? baseUrl})
      : _explicitBaseUrl = baseUrl != null,
        _baseUrl = baseUrl ?? _cachedBaseUrl ?? defaultBaseUrl {
    _ready = _loadBaseUrl();
  }

  static const String _kBaseUrlKey = 'api.base_url';
  static String? _cachedBaseUrl;
  final bool _explicitBaseUrl;
  String _baseUrl;
  String? _token;
  String? _businessId;
  Future<void>? _ready;

  String get baseUrl => _baseUrl;

  Future<void> ensureReady() async {
    await (_ready ??= _loadBaseUrl());
  }

  Future<void> _loadBaseUrl() async {
    if (_explicitBaseUrl) return;
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
  String? get token => _token;
  bool get hasAuth => _token != null && _token!.isNotEmpty;

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
      await ensureReady();
      final uri = Uri.parse('$_baseUrl/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _errorFromResponse(http.Response res, String fallback) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    if (res.body.isEmpty) {
      return '$fallback (HTTP ${res.statusCode})';
    }
    return '$fallback (HTTP ${res.statusCode})';
  }

  AuthSessionResult _parseAuth(http.Response res, String fallback) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw Exception(fallback);
      }
      final result = AuthSessionResult.fromMap(Map<String, dynamic>.from(decoded));
      setToken(result.token);
      if (result.businessId != null) {
        setBusinessId(result.businessId);
      }
      return result;
    }
    throw Exception(_errorFromResponse(res, fallback));
  }

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await ensureReady();
    final effectiveHeaders = _headers(extra: headers);
    if (token != null && token.isNotEmpty) {
      effectiveHeaders['Authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('$_baseUrl$path');
    return await http
        .post(uri, headers: effectiveHeaders, body: jsonEncode(body))
        .timeout(timeout);
  }

  Future<http.Response> get(
    String path, {
    String? token,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await ensureReady();
    final effectiveHeaders = _headers(extra: headers);
    if (token != null && token.isNotEmpty) {
      effectiveHeaders['Authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('$_baseUrl$path');
    return await http
        .get(uri, headers: effectiveHeaders)
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
    return _parseAuth(res, 'Google authentication failed');
  }

  Future<AuthSessionResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final res = await post('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
    return _parseAuth(res, 'Login failed');
  }

  Future<AuthSessionResult> registerWithEmail({
    required String name,
    required String email,
    required String password,
    String? businessName,
  }) async {
    final res = await post('/api/v1/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      if (businessName != null && businessName.isNotEmpty)
        'businessName': businessName,
    });
    return _parseAuth(res, 'Registration failed');
  }

  Future<AuthSessionResult> loginWithPhone({
    required String phone,
    required String otp,
    String? sessionId,
    String? name,
  }) async {
    final res = await post('/api/v1/auth/phone/verify', {
      'phone': phone,
      'otp': otp,
      if (sessionId != null) 'sessionId': sessionId,
      if (name != null) 'name': name,
    });

    return _parseAuth(res, 'Phone verification failed');
  }

  Future<Map<String, dynamic>> requestPhoneOtp(String phone) async {
    final res = await post('/api/v1/auth/phone/otp', {'phone': phone});
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final dynamic body = jsonDecode(res.body);
    throw Exception(body is Map && body['error'] != null ? body['error'] : 'Failed to send OTP');
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
    throw Exception(_errorFromResponse(res, 'Backup upload failed'));
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
    await ensureReady();
    final uri = Uri.parse('$_baseUrl/api/v1/backup/$backupId');
    await http.delete(uri, headers: _headers());
  }
}

