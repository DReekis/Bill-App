import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';
import 'api_client.dart';

enum SubscriptionTier {
  free,
  starter,
  silver,
  gold,
  businessPro;

  String get key {
    switch (this) {
      case SubscriptionTier.free:
        return 'free';
      case SubscriptionTier.starter:
        return 'starter';
      case SubscriptionTier.silver:
        return 'silver';
      case SubscriptionTier.gold:
        return 'gold';
      case SubscriptionTier.businessPro:
        return 'business_pro';
    }
  }

  String get displayName {
    switch (this) {
      case SubscriptionTier.free:
        return 'Free Plan';
      case SubscriptionTier.starter:
        return 'Starter';
      case SubscriptionTier.silver:
        return 'Silver';
      case SubscriptionTier.gold:
        return 'Gold';
      case SubscriptionTier.businessPro:
        return 'Business Pro';
    }
  }

  int get annualPriceInInr {
    switch (this) {
      case SubscriptionTier.free:
        return 0;
      case SubscriptionTier.starter:
        return 579;
      case SubscriptionTier.silver:
        return 1499;
      case SubscriptionTier.gold:
        return 2999;
      case SubscriptionTier.businessPro:
        return 4999;
    }
  }

  int get amountInPaise => annualPriceInInr * 100;

  String? get badge {
    switch (this) {
      case SubscriptionTier.silver:
        return 'MOST POPULAR';
      case SubscriptionTier.gold:
        return 'BEST VALUE';
      case SubscriptionTier.businessPro:
        return 'ENTERPRISE';
      default:
        return null;
    }
  }

  static SubscriptionTier fromString(String? val) {
    if (val == null) return SubscriptionTier.free;
    final clean = val.toLowerCase().replaceAll('-', '_').trim();
    if (clean == 'starter') return SubscriptionTier.starter;
    if (clean == 'silver') return SubscriptionTier.silver;
    if (clean == 'gold') return SubscriptionTier.gold;
    if (clean == 'business_pro' || clean == 'businesspro' || clean == 'pro') {
      return SubscriptionTier.businessPro;
    }
    return SubscriptionTier.free;
  }
}

class PlanLimits {
  const PlanLimits({
    required this.salesInvoices,
    required this.purchases,
    required this.customers,
    required this.suppliers,
    required this.items,
    required this.companies,
    required this.staffUsers,
    required this.eWayBillsPerMonth,
    required this.whatsAppInvoicesPerMonth,
  });

  final int salesInvoices; // -1 = Unlimited
  final int purchases;
  final int customers;
  final int suppliers;
  final int items;
  final int companies;
  final int staffUsers;
  final int eWayBillsPerMonth;
  final int whatsAppInvoicesPerMonth;

  bool get isSalesUnlimited => salesInvoices == -1;
  bool get isPurchasesUnlimited => purchases == -1;
  bool get isCustomersUnlimited => customers == -1;
  bool get isSuppliersUnlimited => suppliers == -1;
  bool get isItemsUnlimited => items == -1;
  bool get isStaffUnlimited => staffUsers == -1;
  bool get isEWayUnlimited => eWayBillsPerMonth == -1;
}

class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  SubscriptionTier _currentTier = SubscriptionTier.free;
  DateTime? _expiresAt;
  String _status = 'active';
  bool _initialized = false;

  SubscriptionTier get currentTier => _currentTier;
  DateTime? get expiresAt => _expiresAt;
  String get status => _status;
  bool get isInitialized => _initialized;

  bool get isExpired {
    if (_currentTier == SubscriptionTier.free) return false;
    if (_expiresAt == null) return false;
    return DateTime.now().isAfter(_expiresAt!);
  }

  int get daysRemaining {
    if (_expiresAt == null) return 0;
    final diff = _expiresAt!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Canonical Plan Limits Matrix (exact match to official spec)
  PlanLimits get limits {
    switch (_currentTier) {
      case SubscriptionTier.free:
        return const PlanLimits(
          salesInvoices: 10,
          purchases: 10,
          customers: 50,
          suppliers: 50,
          items: 100,
          companies: 1,
          staffUsers: 1,
          eWayBillsPerMonth: 0,
          whatsAppInvoicesPerMonth: 20,
        );
      case SubscriptionTier.starter:
        return const PlanLimits(
          salesInvoices: -1,
          purchases: -1,
          customers: 500,
          suppliers: 500,
          items: 1000,
          companies: 1,
          staffUsers: 1,
          eWayBillsPerMonth: 0,
          whatsAppInvoicesPerMonth: 500,
        );
      case SubscriptionTier.silver:
        return const PlanLimits(
          salesInvoices: -1,
          purchases: -1,
          customers: 2500,
          suppliers: 2500,
          items: 5000,
          companies: 2,
          staffUsers: 2,
          eWayBillsPerMonth: 10,
          whatsAppInvoicesPerMonth: -1,
        );
      case SubscriptionTier.gold:
        return const PlanLimits(
          salesInvoices: -1,
          purchases: -1,
          customers: 10000,
          suppliers: 10000,
          items: 25000,
          companies: 5,
          staffUsers: 5,
          eWayBillsPerMonth: -1,
          whatsAppInvoicesPerMonth: -1,
        );
      case SubscriptionTier.businessPro:
        return const PlanLimits(
          salesInvoices: -1,
          purchases: -1,
          customers: -1,
          suppliers: -1,
          items: -1,
          companies: 10,
          staffUsers: -1,
          eWayBillsPerMonth: -1,
          whatsAppInvoicesPerMonth: -1,
        );
    }
  }

  // Feature Gating Checks
  bool canCreateSalesInvoice(int currentCount) {
    if (isExpired) return currentCount < 10;
    if (limits.isSalesUnlimited) return true;
    return currentCount < limits.salesInvoices;
  }

  bool canCreatePurchase(int currentCount) {
    if (isExpired) return currentCount < 10;
    if (limits.isPurchasesUnlimited) return true;
    return currentCount < limits.purchases;
  }

  bool canAddCustomer(int currentCount) {
    if (isExpired) return currentCount < 50;
    if (limits.isCustomersUnlimited) return true;
    return currentCount < limits.customers;
  }

  bool canAddSupplier(int currentCount) {
    if (isExpired) return currentCount < 50;
    if (limits.isSuppliersUnlimited) return true;
    return currentCount < limits.suppliers;
  }

  bool canAddItem(int currentCount) {
    if (isExpired) return currentCount < 100;
    if (limits.isItemsUnlimited) return true;
    return currentCount < limits.items;
  }

  bool canAddCompany(int currentCount) {
    return currentCount < limits.companies;
  }

  bool canAddStaffUser(int currentCount) {
    if (limits.isStaffUnlimited) return true;
    return currentCount < limits.staffUsers;
  }

  // Advanced Document & Management Gates
  bool get canAccessReturns =>
      !isExpired && _currentTier != SubscriptionTier.free;

  bool get canAccessEstimates =>
      !isExpired && _currentTier != SubscriptionTier.free;

  bool get canAccessSalesOrders =>
      !isExpired &&
      (_currentTier == SubscriptionTier.silver ||
          _currentTier == SubscriptionTier.gold ||
          _currentTier == SubscriptionTier.businessPro);

  bool get canAccessPurchaseOrders => canAccessSalesOrders;

  bool get canAccessDeliveryChallans => canAccessSalesOrders;

  bool get canAccessBarcode => canAccessSalesOrders;

  bool get canAccessLowStockAlert => canAccessSalesOrders;

  bool get canAccessStockTransfer => canAccessSalesOrders;

  bool get canAccessEInvoice => canAccessSalesOrders;

  bool get canAccessBankManagement => canAccessSalesOrders;

  bool get canAccessTallyExport => canAccessSalesOrders;

  bool get canAccessMultiDeviceSync => canAccessSalesOrders;

  bool get canAccessInvoiceSettings => canAccessSalesOrders;

  bool get canAccessAccountingModule =>
      !isExpired &&
      (_currentTier == SubscriptionTier.gold ||
          _currentTier == SubscriptionTier.businessPro);

  bool get canAccessBalanceSheet => canAccessAccountingModule;

  bool get canAccessPartyWisePL => canAccessAccountingModule;

  bool get canAccessCustomerLoyalty =>
      !isExpired && _currentTier == SubscriptionTier.businessPro;

  bool get canAccessDesktop =>
      !isExpired &&
      (_currentTier == SubscriptionTier.gold ||
          _currentTier == SubscriptionTier.businessPro);

  bool get canExportExcel =>
      !isExpired && _currentTier != SubscriptionTier.free;

  bool get canAccessAutomaticBackup =>
      !isExpired &&
      (_currentTier == SubscriptionTier.silver ||
          _currentTier == SubscriptionTier.gold ||
          _currentTier == SubscriptionTier.businessPro);

  static const _kPrefTier = 'subscription.tier';
  static const _kPrefExpiresAt = 'subscription.expires_at';
  static const _kPrefStatus = 'subscription.status';

  /// Initializes subscription state from local SharedPreferences and SQLite
  Future<void> init({int? businessId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tierStr = prefs.getString(_kPrefTier);
      final expiresStr = prefs.getString(_kPrefExpiresAt);
      final statusStr = prefs.getString(_kPrefStatus) ?? 'active';

      if (tierStr != null) {
        _currentTier = SubscriptionTier.fromString(tierStr);
      }
      if (expiresStr != null) {
        _expiresAt = DateTime.tryParse(expiresStr);
      }
      _status = statusStr;

      // Also check SQLite database if businessId is available
      if (businessId != null) {
        final db = await AppDatabase.instance.database;
        final rows = await db.query(
          'businesses',
          columns: ['subscription_tier', 'subscription_status', 'subscription_expires_at'],
          where: 'id = ?',
          whereArgs: [businessId],
        );
        if (rows.isNotEmpty) {
          final r = rows.first;
          final dbTier = r['subscription_tier'] as String?;
          final dbExpires = r['subscription_expires_at'] as String?;
          final dbStatus = r['subscription_status'] as String?;

          if (dbTier != null && dbTier.isNotEmpty) {
            _currentTier = SubscriptionTier.fromString(dbTier);
          }
          if (dbExpires != null && dbExpires.isNotEmpty) {
            _expiresAt = DateTime.tryParse(dbExpires);
          }
          if (dbStatus != null && dbStatus.isNotEmpty) {
            _status = dbStatus;
          }
        }
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[SubscriptionService] init error: $e');
    }
  }

  /// Sets subscription tier and persists both locally and in SQLite
  Future<void> setSubscription({
    required SubscriptionTier tier,
    required DateTime expiresAt,
    String status = 'active',
    int? businessId,
  }) async {
    _currentTier = tier;
    _expiresAt = expiresAt;
    _status = status;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefTier, tier.key);
      await prefs.setString(_kPrefExpiresAt, expiresAt.toIso8601String());
      await prefs.setString(_kPrefStatus, status);

      if (businessId != null) {
        final db = await AppDatabase.instance.database;
        await db.update(
          'businesses',
          {
            'subscription_tier': tier.key,
            'subscription_status': status,
            'subscription_expires_at': expiresAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [businessId],
        );
      }
    } catch (e) {
      debugPrint('[SubscriptionService] persistence error: $e');
    }

    notifyListeners();
  }

  /// Synchronizes subscription status with remote backend server
  Future<void> syncWithServer({
    required String cloudBusinessId,
    required String token,
    int? localBusinessId,
  }) async {
    try {
      final res = await ApiClient.instance.get(
        '/api/v1/subscription/status/$cloudBusinessId',
        token: token,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tierStr = data['tier'] as String?;
        final expiresStr = data['expiresAt'] as String?;
        final statusStr = data['status'] as String? ?? 'active';

        if (tierStr != null) {
          final tier = SubscriptionTier.fromString(tierStr);
          final expires = expiresStr != null
              ? (DateTime.tryParse(expiresStr) ?? DateTime.now().add(const Duration(days: 365)))
              : DateTime.now().add(const Duration(days: 365));

          await setSubscription(
            tier: tier,
            expiresAt: expires,
            status: statusStr,
            businessId: localBusinessId,
          );
        }
      }
    } catch (e) {
      debugPrint('[SubscriptionService] syncWithServer error: $e');
    }
  }
}
