import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  ApiClient({String baseUrl = 'http://10.0.2.2:4000'}) : _baseUrl = baseUrl {
    _loadBaseUrl();
  }

  static const String _kBaseUrlKey = 'api.base_url';
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
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
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
}
