import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';
import 'auth_service.dart';
import 'security_service.dart';

enum UserRole {
  owner,
  admin,
  cashier,
  salesman,
  deliveryBoy,
  accountant;

  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.admin:
        return 'Admin';
      case UserRole.cashier:
        return 'Cashier (Biller)';
      case UserRole.salesman:
        return 'Salesman';
      case UserRole.deliveryBoy:
        return 'Delivery Agent';
      case UserRole.accountant:
        return 'Accountant / CA';
    }
  }

  static UserRole fromString(String? role) {
    if (role == null) return UserRole.owner;
    final r = role.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '').trim();
    if (r.contains('owner')) return UserRole.owner;
    if (r.contains('admin')) return UserRole.admin;
    if (r.contains('cashier') || r.contains('biller')) return UserRole.cashier;
    if (r.contains('salesman')) return UserRole.salesman;
    if (r.contains('delivery')) return UserRole.deliveryBoy;
    if (r.contains('accountant') || r == 'ca') return UserRole.accountant;
    return UserRole.owner;
  }

  static UserRole fromCode(String? code) {
    if (code == null) return UserRole.owner;
    final r = code.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '').trim();
    if (r.contains('owner')) return UserRole.owner;
    if (r.contains('admin')) return UserRole.admin;
    if (r.contains('cashier') || r.contains('biller')) return UserRole.cashier;
    if (r.contains('salesman')) return UserRole.salesman;
    if (r.contains('delivery')) return UserRole.deliveryBoy;
    if (r.contains('accountant') || r == 'ca') return UserRole.accountant;
    return UserRole.cashier;
  }
}

class Session extends ChangeNotifier {
  SharedPreferences? _prefs;
  String? mobile;
  String? token;
  int? businessId;
  String currentUser = 'Owner';
  String currentRole = 'Owner';
  String localeCode = 'en';
  bool flagSecureEnabled = false;
  bool biometricEnabled = false;
  bool _locked = true;
  /// Cloud Account profile & token
  String? cloudUserId;
  String? cloudEmail;
  String? cloudName;
  String? cloudAvatarUrl;
  String? cloudProvider;

  bool get isCloudLinked => token != null && token!.isNotEmpty && (cloudEmail != null && cloudEmail!.isNotEmpty);
  /// API key for gstincheck.co.in — free signup at https://gstincheck.co.in
  String gstnApiKey = '';

  Locale get locale => Locale(localeCode);

  UserRole get role => UserRole.fromString(currentRole);

  bool get canViewCosts =>
      role == UserRole.owner || role == UserRole.admin || role == UserRole.accountant;

  bool get canViewPL =>
      role == UserRole.owner || role == UserRole.admin || role == UserRole.accountant;

  bool get canViewBankBalances =>
      role == UserRole.owner || role == UserRole.admin || role == UserRole.accountant;

  bool get canManageStaff => role == UserRole.owner || role == UserRole.admin;

  bool get canExportTally =>
      role == UserRole.owner || role == UserRole.admin || role == UserRole.accountant;

  bool get canManageInventory => role == UserRole.owner || role == UserRole.admin;

  bool get canCreateSales =>
      role == UserRole.owner ||
      role == UserRole.admin ||
      role == UserRole.cashier ||
      role == UserRole.salesman;

  bool canEditInvoice(dynamic dateOrTime, {Duration lockWindow = const Duration(minutes: 15)}) {
    if (role == UserRole.owner || role == UserRole.admin || role == UserRole.accountant) {
      return true;
    }
    if (role == UserRole.cashier) {
      DateTime? dt;
      if (dateOrTime is DateTime) {
        dt = dateOrTime;
      } else if (dateOrTime is String) {
        dt = DateTime.tryParse(dateOrTime);
      }
      if (dt == null) return false;
      return DateTime.now().difference(dt) <= lockWindow;
    }
    return false;
  }

  bool can(String action) {
    switch (action) {
      case 'view_reports':
        return canViewPL || role == UserRole.cashier || role == UserRole.salesman;
      case 'view_costs':
        return canViewCosts;
      case 'view_pl':
        return canViewPL;
      case 'view_banking':
        return canViewBankBalances;
      case 'manage_staff':
        return canManageStaff;
      case 'export_tally':
        return canExportTally;
      case 'create_invoice':
        return canCreateSales;
      case 'view_products':
        return true;
      default:
        if (role == UserRole.owner || role == UserRole.admin) return true;
        return false;
    }
  }

  static const _kMobile = 'session.mobile';
  static const _kToken = 'session.token';
  static const _kBusinessId = 'session.businessId';
  static const _kPinHash = 'session.pin';
  static const _kOnboarded = 'session.onboarded';
  static const _kCurrentUser = 'session.currentUser';
  static const _kCurrentRole = 'session.currentRole';
  static const _kLocaleCode = 'session.localeCode';
  static const _kFlagSecure = 'session.flagSecure';
  static const _kBiometric = 'session.biometric';
  static const _kGstnApiKey = 'session.gstnApiKey';
  static const _kCloudUserId = 'session.cloudUserId';
  static const _kCloudEmail = 'session.cloudEmail';
  static const _kCloudName = 'session.cloudName';
  static const _kCloudAvatarUrl = 'session.cloudAvatarUrl';
  static const _kCloudProvider = 'session.cloudProvider';

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
    currentRole = _prefs!.getString(_kCurrentRole) ?? 'Owner';
    localeCode = _prefs!.getString(_kLocaleCode) ?? 'en';
    flagSecureEnabled = _prefs!.getBool(_kFlagSecure) ?? false;
    biometricEnabled = _prefs!.getBool(_kBiometric) ?? false;
    gstnApiKey = _prefs!.getString(_kGstnApiKey) ?? '';
    cloudUserId = _prefs!.getString(_kCloudUserId);
    cloudEmail = _prefs!.getString(_kCloudEmail);
    cloudName = _prefs!.getString(_kCloudName);
    cloudAvatarUrl = _prefs!.getString(_kCloudAvatarUrl);
    cloudProvider = _prefs!.getString(_kCloudProvider);

    if (flagSecureEnabled) {
      SecurityService.instance.setFlagSecure(true);
    }
    _locked = true; // stays locked only when a PIN exists — see `locked`
    notifyListeners();
  }

  Future<void> linkCloudSession(AuthSessionResult result) async {
    token = result.token;
    cloudUserId = result.user.id;
    cloudEmail = result.user.email;
    cloudName = result.user.displayName;
    cloudAvatarUrl = result.user.photoUrl;
    cloudProvider = result.user.provider.name;

    notifyListeners();

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kToken, result.token);
      await _prefs!.setString(_kCloudUserId, result.user.id);
      await _prefs!.setString(_kCloudEmail, result.user.email);
      await _prefs!.setString(_kCloudName, result.user.displayName);
      if (result.user.photoUrl != null) {
        await _prefs!.setString(_kCloudAvatarUrl, result.user.photoUrl!);
      }
      await _prefs!.setString(_kCloudProvider, result.user.provider.name);
    } catch (_) {}
  }

  Future<void> unlinkCloudSession() async {
    token = null;
    cloudUserId = null;
    cloudEmail = null;
    cloudName = null;
    cloudAvatarUrl = null;
    cloudProvider = null;

    notifyListeners();

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.remove(_kToken);
      await _prefs!.remove(_kCloudUserId);
      await _prefs!.remove(_kCloudEmail);
      await _prefs!.remove(_kCloudName);
      await _prefs!.remove(_kCloudAvatarUrl);
      await _prefs!.remove(_kCloudProvider);
    } catch (_) {}
  }

  Future<void> setRole(UserRole newRole) async {
    currentRole = newRole.label;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kCurrentRole, currentRole);
    } catch (_) {}
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

  Future<void> saveGstnApiKey(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    gstnApiKey = key.trim();
    await _prefs!.setString(_kGstnApiKey, gstnApiKey);
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
