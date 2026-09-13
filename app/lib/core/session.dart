import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Session extends ChangeNotifier {
  SharedPreferences? _prefs;
  String? mobile;
  String? token;
  int? businessId;
  String currentUser = 'Owner';
  bool _locked = true;

  static const _kMobile = 'session.mobile';
  static const _kToken = 'session.token';
  static const _kBusinessId = 'session.businessId';
  static const _kPinHash = 'session.pin';
  static const _kOnboarded = 'session.onboarded';
  static const _kCurrentUser = 'session.currentUser';

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

  Future<void> switchUser(String name) async {
    _prefs ??= await SharedPreferences.getInstance();
    currentUser = name;
    await _prefs!.setString(_kCurrentUser, name);
    notifyListeners();
  }
}
