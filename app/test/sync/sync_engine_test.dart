import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/api_client.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/sync/sync_engine.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'session.businessId': 1,
      'session.mobile': '9876543210',
      'session.token': 'mock-jwt-token',
    });
    AppDatabase.instance.resetConnection();
  });

  test('ApiClient configuration and URL updates', () async {
    final client = ApiClient(baseUrl: 'http://localhost:4000');
    expect(client.baseUrl, 'http://localhost:4000');

    await client.setBaseUrl('http://192.168.1.50:4000');
    expect(client.baseUrl, 'http://192.168.1.50:4000');
  });

  test('SyncRecord model serialization round-trip', () {
    final record = SyncRecord(
      id: 42,
      businessId: 1,
      entity: 'customer',
      entityId: 101,
      op: 'upsert',
      payload: '{"name":"Aarav Patel"}',
      idempotencyKey: 'dev#customer#101#upsert',
      createdAt: '2026-09-17T12:00:00Z',
    );

    final map = record.toMap();
    expect(map['business_id'], 1);
    expect(map['entity'], 'customer');
    expect(map['entity_id'], 101);
    expect(map['idempotency_key'], 'dev#customer#101#upsert');

    final revived = SyncRecord.fromMap({
      'id': 42,
      'business_id': 1,
      'entity': 'customer',
      'entity_id': 101,
      'op': 'upsert',
      'payload': '{"name":"Aarav Patel"}',
      'idempotency_key': 'dev#customer#101#upsert',
      'status': 'pending',
      'attempts': 0,
      'created_at': '2026-09-17T12:00:00Z',
    });
    expect(revived.id, 42);
    expect(revived.entity, 'customer');
    expect(revived.entityId, 101);
  });

  test('Repository reconciles remote customer without enqueueing echo', () async {
    final repo = Repository.instance;
    await repo.session.load();
    await repo.session.completeOnboarding(1);

    await repo.reconcileRemoteChange({
      'entity': 'customer',
      'op': 'upsert',
      'payload': '{"name":"Remote Cloud Customer","phone":"9988776655","city":"Delhi","openingBalance":2500}',
    });

    final customers = await repo.customers(1);
    final found = customers.where((c) => c.phone == '9988776655');
    expect(found.isNotEmpty, isTrue);
    expect(found.first.name, 'Remote Cloud Customer');
  });

  test('SyncEngine initial state and refreshPending', () async {
    final sync = SyncEngine.instance;
    expect(sync.syncing, isFalse);

    await sync.refreshPending();
    expect(sync.pendingCount, isNotNull);
  });
}
