import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';
import 'security_service.dart';

class Session extends ChangeNotifier {
  SharedPreferences? _prefs;
  String? mobile;
  String? token;
  int? businessId;
  String currentUser = 'Owner';
  String currentRole = 'Admin';
  String localeCode = 'en';
  bool flagSecureEnabled = false;
  bool biometricEnabled = false;
  bool _locked = true;

  Locale get locale => Locale(localeCode);

  bool can(String action) {
    if (currentRole == 'Admin' || currentRole == 'Owner') return true;
    if (currentRole == 'Salesman') {
      return ['create_invoice', 'view_products'].contains(action);
    }
    return false;
  }

  static const _kMobile = 'session.mobile';
  static const _kToken = 'session.token';
  static const _kBusinessId = 'session.businessId';
  static const _kPinHash = 'session.pin';
  static const _kOnboarded = 'session.onboarded';
  static const _kCurrentUser = 'session.currentUser';
  static const _kLocaleCode = 'session.localeCode';
  static const _kFlagSecure = 'session.flagSecure';
  static const _kBiometric = 'session.biometric';

  bool get hasPin => (_prefs?.getString(_kPinHash) ?? '').isNotEmpty;
  bool get locked => _locked && hasPin;
  bool get onboarded => _prefs?.getBool(_kOnboarded) ?? false;
  bool get hasSession =>
      mobile != null && (_prefs?.getBool(_kOnboarded) ?? false);

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    mobile = _prefs!.getString(_kMobile);
    token = _prefs!.getString(_kToken);
    businessId = _prefs!.getInt(_kBusinessId);
    currentUser = _prefs!.getString(_kCurrentUser) ?? 'Owner';
    localeCode = _prefs!.getString(_kLocaleCode) ?? 'en';
    flagSecureEnabled = _prefs!.getBool(_kFlagSecure) ?? false;
    biometricEnabled = _prefs!.getBool(_kBiometric) ?? false;
    if (flagSecureEnabled) {
      SecurityService.instance.setFlagSecure(true);
    }
    _locked = true; // stays locked only when a PIN exists — see `locked`
    notifyListeners();
  }

  Future<void> savePhone(String value) async {
    _prefs ??= await SharedPreferences.getInstance();
    mobile = value;
    await _prefs!.setString(_kMobile, value);
    notifyListeners();
  }

  Future<void> saveAuthToken(String value) async {
    _prefs ??= await SharedPreferences.getInstance();
    token = value;
    await _prefs!.setString(_kToken, value);
    notifyListeners();
  }

  Future<void> completeOnboarding(int businessId, {String? pin}) async {
    _prefs ??= await SharedPreferences.getInstance();
    this.businessId = businessId;
    await _prefs!.setInt(_kBusinessId, businessId);
    await _prefs!.setBool(_kOnboarded, true);
    if (pin != null && pin.isNotEmpty) {
      await _prefs!.setString(_kPinHash, _djb2(pin));
    }
    notifyListeners();
  }

  Future<void> updatePin(String? pin) async {
    _prefs ??= await SharedPreferences.getInstance();
    _locked = false; // changing the PIN must not lock the live session
    if (pin == null || pin.isEmpty) {
      await _prefs!.remove(_kPinHash);
    } else {
      await _prefs!.setString(_kPinHash, _djb2(pin));
    }
    notifyListeners();
  }

  bool verifyPin(String input) {
    final stored = _prefs?.getString(_kPinHash) ?? '';
    if (stored.isEmpty) return true;
    if (input.length < 4) return false;
    return _djb2(input).toString() == stored;
  }

  static String _djb2(String input) {
    var hash = 5381;
    for (final unit in input.codeUnits) {
      hash = ((hash << 5) + hash) + unit;
    }
    return hash.toUnsigned(31).toString();
  }

  Future<void> setPin(String pin) async {
    _prefs ??= await SharedPreferences.getInstance();
    _locked = false; // the user is right here; only a cold start should lock
    await _prefs!.setString(_kPinHash, _djb2(pin));
    notifyListeners();
  }

  void unlock() {
    _locked = false;
    notifyListeners();
  }

  Future<void> lock() async {
    _locked = hasPin;
    notifyListeners();
  }

  Future<void> logout() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_kMobile);
    await _prefs!.remove(_kToken);
    await _prefs!.remove(_kBusinessId);
    await _prefs!.remove(_kOnboarded);
    await _prefs!.remove(_kCurrentUser);
    mobile = null;
    token = null;
    businessId = null;
    currentUser = 'Owner';
    _locked = false;
    notifyListeners();
  }

  Future<void> switchBusiness(int newBusinessId) async {
    _prefs ??= await SharedPreferences.getInstance();
    businessId = newBusinessId;
    await _prefs!.setInt(_kBusinessId, newBusinessId);
    notifyListeners();
  }

  Future<void> switchUser(String name) async {
    _prefs ??= await SharedPreferences.getInstance();
    currentUser = name;
    await _prefs!.setString(_kCurrentUser, name);
    notifyListeners();
  }

  void switchRole(String role) {
    currentRole = role;
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    _prefs ??= await SharedPreferences.getInstance();
    localeCode = code;
    await _prefs!.setString(_kLocaleCode, code);
    notifyListeners();
  }

  Future<void> setFlagSecure(bool enabled) async {
    _prefs ??= await SharedPreferences.getInstance();
    flagSecureEnabled = enabled;
    await _prefs!.setBool(_kFlagSecure, enabled);
    await SecurityService.instance.setFlagSecure(enabled);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    _prefs ??= await SharedPreferences.getInstance();
    biometricEnabled = enabled;
    await _prefs!.setBool(_kBiometric, enabled);
    notifyListeners();
  }

  Future<void> deleteBusinessData(int targetBusinessId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('invoices', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('invoice_items', where: 'invoice_id NOT IN (SELECT id FROM invoices)');
      await txn.delete('customers', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('suppliers', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('products', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('payments', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('expenses', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('bank_accounts', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('cheques', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('ledger_entries', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('sync_queue', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('audit_logs', where: 'business_id = ?', whereArgs: [targetBusinessId]);
      await txn.delete('businesses', where: 'id = ?', whereArgs: [targetBusinessId]);
    });
    await logout();
  }

  void refresh() => notifyListeners();
}
