import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billket/core/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserRole & RBAC Permission Matrix', () {
    test('Owner has unrestricted access to all modules and financials', () {
      final session = Session();
      session.switchRole('Owner');

      expect(session.role, equals(UserRole.owner));
      expect(session.isStaff, isFalse);
      expect(session.canViewCosts, isTrue);
      expect(session.canViewPL, isTrue);
      expect(session.canViewBankBalances, isTrue);
      expect(session.canManageStaff, isTrue);
      expect(session.canManageBusinessSettings, isTrue);
      expect(session.canViewAuditTrail, isTrue);
      expect(session.canExportTally, isTrue);
      expect(session.canManageInventory, isTrue);
      expect(session.canCreateSales, isTrue);
      expect(session.can('view_reports'), isTrue);
      expect(session.can('view_costs'), isTrue);
      expect(session.can('view_pl'), isTrue);
      expect(session.can('view_banking'), isTrue);
      expect(session.can('manage_staff'), isTrue);
      expect(session.can('create_invoice'), isTrue);
      expect(session.canEditInvoice(DateTime.now().subtract(const Duration(days: 5))), isTrue);
    });

    test('Cashier has billing permissions but costs, profits & staff management are locked', () {
      final session = Session();
      session.switchRole('Cashier (Biller)');

      expect(session.role, equals(UserRole.cashier));
      expect(session.isStaff, isTrue);
      expect(session.canViewCosts, isFalse);
      expect(session.canViewPL, isFalse);
      expect(session.canViewBankBalances, isFalse);
      expect(session.canManageStaff, isFalse);
      expect(session.canManageBusinessSettings, isFalse);
      expect(session.canViewAuditTrail, isFalse);
      expect(session.canExportTally, isFalse);
      expect(session.canManageInventory, isFalse);
      expect(session.canCreateSales, isTrue);
      expect(session.can('create_invoice'), isTrue);
      expect(session.can('view_costs'), isFalse);
      expect(session.can('view_pl'), isFalse);
      expect(session.can('manage_staff'), isFalse);

      // Cashier can edit invoices only within the 15-minute lock window
      final recent = DateTime.now().subtract(const Duration(minutes: 5));
      final old = DateTime.now().subtract(const Duration(minutes: 30));
      expect(session.canEditInvoice(recent), isTrue);
      expect(session.canEditInvoice(old), isFalse);
    });

    test('Salesman can generate sales but costs and bank accounts are locked', () {
      final session = Session();
      session.switchRole('Salesman');

      expect(session.role, equals(UserRole.salesman));
      expect(session.isStaff, isTrue);
      expect(session.canViewCosts, isFalse);
      expect(session.canViewPL, isFalse);
      expect(session.canViewBankBalances, isFalse);
      expect(session.canManageStaff, isFalse);
      expect(session.canManageBusinessSettings, isFalse);
      expect(session.canCreateSales, isTrue);
    });

    test('Accountant can view ledgers, costs, P&L and audit logs but cannot manage staff', () {
      final session = Session();
      session.switchRole('Accountant / CA');

      expect(session.role, equals(UserRole.accountant));
      expect(session.isStaff, isTrue);
      expect(session.canViewCosts, isTrue);
      expect(session.canViewPL, isTrue);
      expect(session.canViewBankBalances, isTrue);
      expect(session.canViewAuditTrail, isTrue);
      expect(session.canExportTally, isTrue);
      expect(session.canManageStaff, isFalse);
      expect(session.canManageBusinessSettings, isFalse);
    });
  });

  group('Session persona switching & lifecycle', () {
    test('switchStaffSession stores employee persona, staff ID, and restricts access', () async {
      final session = Session();
      await session.load();

      await session.switchStaffSession(
        businessId: 42,
        name: 'Ramesh Cashier',
        role: UserRole.cashier,
        phone: '9876500001',
        staffId: 7,
      );

      expect(session.businessId, equals(42));
      expect(session.currentUser, equals('Ramesh Cashier'));
      expect(session.currentRole, equals('Cashier (Biller)'));
      expect(session.staffMemberId, equals(7));
      expect(session.mobile, equals('9876500001'));
      expect(session.isStaff, isTrue);
      expect(session.canViewCosts, isFalse);
      expect(session.canManageStaff, isFalse);

      // Reloading from SharedPreferences preserves the staff session
      final session2 = Session();
      await session2.load();
      expect(session2.currentUser, equals('Ramesh Cashier'));
      expect(session2.currentRole, equals('Cashier (Biller)'));
      expect(session2.staffMemberId, equals(7));
      expect(session2.isStaff, isTrue);
    });

    test('switchOwnerSession switches back to Owner with full access', () async {
      final session = Session();
      await session.load();

      await session.switchStaffSession(
        businessId: 42,
        name: 'Sunil Sales',
        role: UserRole.salesman,
        phone: '9876500002',
        staffId: 8,
      );
      expect(session.isStaff, isTrue);

      await session.switchOwnerSession(name: 'Aditya Gupta');
      expect(session.currentUser, equals('Aditya Gupta'));
      expect(session.currentRole, equals('Owner'));
      expect(session.staffMemberId, isNull);
      expect(session.isStaff, isFalse);
      expect(session.canViewCosts, isTrue);
      expect(session.canManageStaff, isTrue);
    });

    test('logout clears staff session and resets to Owner defaults', () async {
      final session = Session();
      await session.load();

      await session.switchStaffSession(
        businessId: 10,
        name: 'Staff 1',
        role: UserRole.cashier,
        phone: '9876500001',
        staffId: 99,
      );

      await session.logout();
      expect(session.currentUser, equals('Owner'));
      expect(session.currentRole, equals('Owner'));
      expect(session.staffMemberId, isNull);
      expect(session.mobile, isNull);
      expect(session.isStaff, isFalse);
    });
  });
}
