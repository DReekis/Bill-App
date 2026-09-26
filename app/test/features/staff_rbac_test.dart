import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('UserRole & RBAC Permissions Matrix Tests', () {
    test('UserRole enum parses string codes accurately', () {
      expect(UserRole.fromCode('owner'), UserRole.owner);
      expect(UserRole.fromCode('admin'), UserRole.admin);
      expect(UserRole.fromCode('cashier'), UserRole.cashier);
      expect(UserRole.fromCode('salesman'), UserRole.salesman);
      expect(UserRole.fromCode('delivery_boy'), UserRole.deliveryBoy);
      expect(UserRole.fromCode('deliveryBoy'), UserRole.deliveryBoy);
      expect(UserRole.fromCode('accountant'), UserRole.accountant);
      expect(UserRole.fromCode('unknown_role'), UserRole.cashier);
    });

    test('Owner has comprehensive business permissions', () {
      final session = Session();
      session.setRole(UserRole.owner);

      expect(session.canViewCosts, isTrue);
      expect(session.canViewPL, isTrue);
      expect(session.canViewBankBalances, isTrue);
      expect(session.canManageStaff, isTrue);
      expect(session.canExportTally, isTrue);
      expect(session.canManageInventory, isTrue);
      expect(session.canCreateSales, isTrue);
      expect(session.can('view_reports'), isTrue);
      expect(session.can('delete_invoice'), isTrue);
    });

    test('Cashier has billing access but costs and profits are strictly hidden', () {
      final session = Session();
      session.setRole(UserRole.cashier);

      expect(session.canViewCosts, isFalse);
      expect(session.canViewPL, isFalse);
      expect(session.canViewBankBalances, isFalse);
      expect(session.canManageStaff, isFalse);
      expect(session.canExportTally, isFalse);
      expect(session.canManageInventory, isFalse);
      expect(session.canCreateSales, isTrue);
      expect(session.can('view_reports'), isTrue); // Can view Daybook/Sales Summary, but P&L is guarded
    });

    test('Salesman has field sales access but confidential finances are hidden', () {
      final session = Session();
      session.setRole(UserRole.salesman);

      expect(session.canViewCosts, isFalse);
      expect(session.canViewPL, isFalse);
      expect(session.canViewBankBalances, isFalse);
      expect(session.canManageStaff, isFalse);
      expect(session.canExportTally, isFalse);
      expect(session.canManageInventory, isFalse);
      expect(session.canCreateSales, isTrue);
      expect(session.can('view_reports'), isTrue); // Can view Daybook/Sales Summary, but P&L is guarded
    });

    test('Accountant has full financial & report access but cannot alter staff or inventory', () {
      final session = Session();
      session.setRole(UserRole.accountant);

      expect(session.canViewCosts, isTrue);
      expect(session.canViewPL, isTrue);
      expect(session.canViewBankBalances, isTrue);
      expect(session.canManageStaff, isFalse);
      expect(session.canExportTally, isTrue);
      expect(session.canManageInventory, isFalse);
      expect(session.canCreateSales, isFalse);
      expect(session.can('view_reports'), isTrue);
    });

    test('canEditInvoice enforces 15-minute lock window for cashier', () {
      final session = Session();
      session.setRole(UserRole.cashier);

      final freshInvoice = DateTime.now().subtract(const Duration(minutes: 5));
      expect(session.canEditInvoice(freshInvoice), isTrue);

      final lockedInvoice = DateTime.now().subtract(const Duration(minutes: 20));
      expect(session.canEditInvoice(lockedInvoice), isFalse);

      session.setRole(UserRole.owner);
      expect(session.canEditInvoice(lockedInvoice), isTrue);

      session.setRole(UserRole.accountant);
      expect(session.canEditInvoice(lockedInvoice), isTrue);
    });

    test('Session notifies listeners upon role switch', () {
      final session = Session();
      session.setRole(UserRole.owner);

      var notified = false;
      session.addListener(() {
        notified = true;
      });

      session.setRole(UserRole.cashier);
      expect(notified, isTrue);
      expect(session.role, UserRole.cashier);
    });
  });

  group('StaffMember Model Serialization & Repository SQLite Tests', () {
    test('StaffMember converts to/from Map and JSON correctly', () {
      final staff = StaffMember(
        id: 1,
        businessId: 101,
        name: 'Ramesh Patel',
        phone: '9876543210',
        role: UserRole.cashier,
        pin: '1234',
        isActive: true,
      );

      final map = staff.toMap();
      expect(map['name'], 'Ramesh Patel');
      expect(map['phone'], '9876543210');
      expect(map['role'], 'cashier');
      expect(map['pin'], '1234');
      expect(map['is_active'], 1);

      final restored = StaffMember.fromMap(map);
      expect(restored.id, 1);
      expect(restored.name, 'Ramesh Patel');
      expect(restored.role, UserRole.cashier);
      expect(restored.pin, '1234');
      expect(restored.isActive, isTrue);
    });

    test('Database creates staff_members table and performs CRUD operations', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: AppDatabase.instance.createSchema,
        ),
      );
      AppDatabase.instance.useDatabaseForTesting(db);

      final repo = Repository.instance;
      final bizId = await repo.createBusiness(Business(
        name: 'Supermart Retail',
        state: 'Karnataka',
      ));

      // 1. Initially empty
      final initialStaff = await repo.staffMembers(bizId);
      expect(initialStaff, isEmpty);

      // 2. Add Cashier
      final cashierId = await repo.upsertStaffMember(StaffMember(
        businessId: bizId,
        name: 'Anjali Sharma',
        phone: '9811223344',
        role: UserRole.cashier,
        pin: '4321',
      ));
      expect(cashierId, isPositive);

      // 3. Add Salesman
      final salesmanId = await repo.upsertStaffMember(StaffMember(
        businessId: bizId,
        name: 'Vikram Singh',
        phone: '9877001122',
        role: UserRole.salesman,
      ));
      expect(salesmanId, isPositive);

      // 4. Retrieve staff list
      final staffList = await repo.staffMembers(bizId);
      expect(staffList.length, 2);
      expect(staffList.map((s) => s.name), containsAll(['Anjali Sharma', 'Vikram Singh']));
      expect(staffList.firstWhere((s) => s.id == cashierId).role, UserRole.cashier);

      // 5. Update Cashier to Admin
      await repo.upsertStaffMember(StaffMember(
        id: cashierId,
        businessId: bizId,
        name: 'Anjali Sharma (Promoted)',
        phone: '9811223344',
        role: UserRole.admin,
        pin: '9999',
      ));
      final updatedList = await repo.staffMembers(bizId);
      final promoted = updatedList.firstWhere((s) => s.id == cashierId);
      expect(promoted.name, 'Anjali Sharma (Promoted)');
      expect(promoted.role, UserRole.admin);
      expect(promoted.pin, '9999');

      // 6. Delete Salesman
      await repo.deleteStaffMember(bizId, salesmanId);

      final afterDeleteList = await repo.staffMembers(bizId);
      expect(afterDeleteList.length, 1);
      expect(afterDeleteList.first.id, cashierId);
    });
  });
}
