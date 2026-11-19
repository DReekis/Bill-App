import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:billket/core/session.dart';
import 'package:billket/core/subscription_service.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/core/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('deleteEntireAccount wipes local SQLite database and resets session and subscriptions', () async {
    final session = Session();

    // 1. Create a business and customer
    final repo = Repository.instance;
    final bizId = await repo.createBusiness(Business(
      name: 'Business To Be Deleted',
      phone: '9988776655',
      subscriptionTier: 'free',
    ));
    await session.completeOnboarding(bizId);

    final custId = await repo.upsertCustomer(
      Customer(name: 'Customer Delete Target', phone: '9988776655'),
      businessIdOverride: bizId,
    );
    expect(custId, greaterThan(0));

    // Verify data exists
    final businessesBefore = await repo.allBusinesses();
    expect(businessesBefore.length, greaterThanOrEqualTo(1));

    // 2. Perform Account Deletion
    await session.deleteEntireAccount();

    // 3. Verify local data is wiped
    final businessesAfter = await repo.allBusinesses();
    expect(businessesAfter.isEmpty, true);

    expect(session.businessId, isNull);
    expect(session.mobile, isNull);
    expect(session.onboarded, false);
    expect(SubscriptionService.instance.currentTier, SubscriptionTier.free);
  });
}
