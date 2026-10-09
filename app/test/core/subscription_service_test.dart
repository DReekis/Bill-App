import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:billket/core/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Subscription Tier Canonical Definition Tests', () {
    test('All 5 tiers parse correctly from keys and aliases', () {
      expect(SubscriptionTier.fromString('free'), SubscriptionTier.free);
      expect(SubscriptionTier.fromString('starter'), SubscriptionTier.starter);
      expect(SubscriptionTier.fromString('silver'), SubscriptionTier.silver);
      expect(SubscriptionTier.fromString('gold'), SubscriptionTier.gold);
      expect(SubscriptionTier.fromString('business_pro'), SubscriptionTier.businessPro);
      expect(SubscriptionTier.fromString('business-pro'), SubscriptionTier.businessPro);
      expect(SubscriptionTier.fromString('pro'), SubscriptionTier.businessPro);
      expect(SubscriptionTier.fromString('unknown_tier'), SubscriptionTier.free);
    });

    test('Pricing matches exact specification from PDF matrix', () {
      expect(SubscriptionTier.free.annualPriceInInr, 0);
      expect(SubscriptionTier.free.amountInPaise, 0);

      expect(SubscriptionTier.starter.annualPriceInInr, 579);
      expect(SubscriptionTier.starter.amountInPaise, 57900);

      expect(SubscriptionTier.silver.annualPriceInInr, 1499);
      expect(SubscriptionTier.silver.amountInPaise, 149900);

      expect(SubscriptionTier.gold.annualPriceInInr, 2999);
      expect(SubscriptionTier.gold.amountInPaise, 299900);

      expect(SubscriptionTier.businessPro.annualPriceInInr, 4999);
      expect(SubscriptionTier.businessPro.amountInPaise, 499900);
    });
  });

  group('Feature Gating & Limits Matrix Verification', () {
    final sub = SubscriptionService.instance;

    test('Free Plan enforces 10 invoices, 50 customers, basic stock, locks advanced ERP', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.free,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(sub.currentTier, SubscriptionTier.free);
      expect(sub.isExpired, false);

      // Invoicing limits
      expect(sub.canCreateSalesInvoice(0), true);
      expect(sub.canCreateSalesInvoice(9), true);
      expect(sub.canCreateSalesInvoice(10), false);
      expect(sub.canCreateSalesInvoice(11), false);

      // Customer limits
      expect(sub.canAddCustomer(49), true);
      expect(sub.canAddCustomer(50), false);

      // Supplier limits
      expect(sub.canAddSupplier(49), true);
      expect(sub.canAddSupplier(50), false);

      // Item limits
      expect(sub.canAddItem(99), true);
      expect(sub.canAddItem(100), false);

      // Company limit
      expect(sub.canAddCompany(0), true);
      expect(sub.canAddCompany(1), false);

      // Locked features
      expect(sub.canAccessReturns, false);
      expect(sub.canAccessEstimates, false);
      expect(sub.canAccessSalesOrders, false);
      expect(sub.canAccessPurchaseOrders, false);
      expect(sub.canAccessDeliveryChallans, false);
      expect(sub.canAccessBankManagement, false);
      expect(sub.canAccessEInvoice, false);
      expect(sub.canAccessAccountingModule, false);
      expect(sub.canAccessDesktop, false);
      expect(sub.canAccessCustomerLoyalty, false);
    });

    test('Starter Plan grants unlimited billing, returns/estimates, 500 customers, 1,000 items', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.starter,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(sub.currentTier, SubscriptionTier.starter);

      // Invoicing limits (unlimited)
      expect(sub.canCreateSalesInvoice(10), true);
      expect(sub.canCreateSalesInvoice(1000), true);
      expect(sub.canCreatePurchase(500), true);

      // Returns & Estimates unlocked
      expect(sub.canAccessReturns, true);
      expect(sub.canAccessEstimates, true);

      // Limits
      expect(sub.canAddCustomer(499), true);
      expect(sub.canAddCustomer(500), false);

      expect(sub.canAddItem(999), true);
      expect(sub.canAddItem(1000), false);

      // Orders still locked
      expect(sub.canAccessSalesOrders, false);
      expect(sub.canAccessBankManagement, false);
    });

    test('Silver Plan unlocks Sales/PO orders, Challans, Bank Hub, Barcode, E-Invoice, 2 companies', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.silver,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(sub.currentTier, SubscriptionTier.silver);

      // Orders and Challans unlocked
      expect(sub.canAccessSalesOrders, true);
      expect(sub.canAccessPurchaseOrders, true);
      expect(sub.canAccessDeliveryChallans, true);

      // Bank Hub & E-Invoice unlocked
      expect(sub.canAccessBankManagement, true);
      expect(sub.canAccessEInvoice, true);
      expect(sub.canAccessBarcode, true);
      expect(sub.canAccessLowStockAlert, true);
      expect(sub.canAccessStockTransfer, true);
      expect(sub.canAccessTallyExport, true);

      // Higher capacity
      expect(sub.canAddCustomer(2499), true);
      expect(sub.canAddCustomer(2500), false);
      expect(sub.canAddItem(4999), true);
      expect(sub.canAddItem(5000), false);

      // 2 companies & 2 users
      expect(sub.canAddCompany(1), true);
      expect(sub.canAddCompany(2), false);
      expect(sub.canAddStaffUser(1), true);
      expect(sub.canAddStaffUser(2), false);

      // Accounting and Desktop still locked (Gold+)
      expect(sub.canAccessAccountingModule, false);
      expect(sub.canAccessDesktop, false);
    });

    test('Gold Plan unlocks Desktop, Full Accounting, 10k customers, 25k items, 5 companies', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.gold,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(sub.currentTier, SubscriptionTier.gold);

      expect(sub.canAccessDesktop, true);
      expect(sub.canAccessAccountingModule, true);
      expect(sub.canAccessBalanceSheet, true);
      expect(sub.canAccessPartyWisePL, true);

      expect(sub.canAddCustomer(9999), true);
      expect(sub.canAddCustomer(10000), false);

      expect(sub.canAddItem(24999), true);
      expect(sub.canAddItem(25000), false);

      expect(sub.canAddCompany(4), true);
      expect(sub.canAddCompany(5), false);
      expect(sub.canAddStaffUser(4), true);
      expect(sub.canAddStaffUser(5), false);

      expect(sub.canAccessCustomerLoyalty, false); // Enterprise only
    });

    test('Business Pro Plan unlocks Unlimited Everything and Customer Loyalty program', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.businessPro,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(sub.currentTier, SubscriptionTier.businessPro);

      expect(sub.canAccessCustomerLoyalty, true);
      expect(sub.canAddCustomer(100000), true);
      expect(sub.canAddSupplier(100000), true);
      expect(sub.canAddItem(500000), true);
      expect(sub.canAddStaffUser(999), true);
      expect(sub.canAddCompany(9), true);
      expect(sub.canAddCompany(10), false);
    });

    test('Expired subscription falls back to strict Free tier restrictions', () async {
      await sub.setSubscription(
        tier: SubscriptionTier.gold,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)), // Expired yesterday
      );

      expect(sub.isExpired, true);

      // Invoicing and limits fall back
      expect(sub.canCreateSalesInvoice(10), false);
      expect(sub.canAddCustomer(50), false);
      expect(sub.canAddItem(100), false);

      // Advanced features locked
      expect(sub.canAccessSalesOrders, false);
      expect(sub.canAccessBankManagement, false);
      expect(sub.canAccessAccountingModule, false);
      expect(sub.canAccessDesktop, false);
    });
  });
}
