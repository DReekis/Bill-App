import 'dart:convert';
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
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);
  });

  test('ApiClient configuration and URL updates', () async {
    final client = ApiClient(baseUrl: 'http://localhost:4000');
    expect(client.baseUrl, 'http://localhost:4000');

    await client.setBaseUrl('http://192.168.1.50:4000');
    expect(client.baseUrl, 'http://192.168.1.50:4000');
  });

  test('ApiClient constructor argument is not overwritten by cached URL', () async {
    final first = ApiClient(baseUrl: 'http://cached.example:4000');
    await first.setBaseUrl('http://cached.example:4000');

    final second = ApiClient(baseUrl: 'http://localhost:4000');
    expect(second.baseUrl, 'http://localhost:4000');
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

  test('Invoice conflict reconciliation writes to audit_log with CONFLICT_RECONCILE', () async {
    final repo = Repository.instance;
    final db = await AppDatabase.instance.database;
    await repo.session.load();
    await repo.session.completeOnboarding(1);

    // 1. Insert local invoice
    final invId = await db.insert('invoices', {
      'business_id': 1,
      'number': 'INV-CONFLICT-01',
      'customer_name': 'Original Customer',
      'date': '2026-09-20',
      'total': 10000,
      'amount_paid': 0,
      'status': 'Unpaid',
    });

    // 2. Simulate remote invoice arriving from another device with paid status
    await repo.reconcileRemoteChange({
      'entity': 'invoice',
      'op': 'upsert',
      'payload': jsonEncode({
        'number': 'INV-CONFLICT-01',
        'customer_name': 'Original Customer',
        'date': '2026-09-20',
        'total': 10000,
        'amount_paid': 10000,
        'status': 'Paid',
        'notes': 'Paid on terminal 2',
        'items': [
          {
            'name': 'Item A',
            'quantity': 2.0,
            'price': 5000,
            'total': 10000,
          }
        ],
      }),
    });

    // 3. Verify local invoice was updated
    final updated = await db.query('invoices', where: 'id = ?', whereArgs: [invId]);
    expect(updated.first['status'], 'Paid');
    expect(updated.first['amount_paid'], 10000);
    expect(updated.first['notes'], 'Paid on terminal 2');

    // 4. Verify audit_log entry was recorded for the conflict
    final auditLogs = await db.query('audit_log',
        where: 'business_id = ? AND action = ? AND entity_id = ?',
        whereArgs: [1, 'CONFLICT_RECONCILE', invId]);
    expect(auditLogs.isNotEmpty, isTrue);
    expect(auditLogs.first['actor'], 'cloud_sync');
    expect(auditLogs.first['entity'], 'invoice');
  });

  test('Inventory delta reconciliation records stock moves correctly', () async {
    final repo = Repository.instance;
    final db = await AppDatabase.instance.database;
    await repo.session.load();
    await repo.session.completeOnboarding(1);

    // 1. Create a product with stock = 25
    final prodId = await db.insert('products', {
      'business_id': 1,
      'name': 'Delta Test Product',
      'sku': 'DELTA-01',
      'stock': 25,
      'sale_price': 500,
    });

    // 2. Remote update arrives with stock = 20 (delta of -5)
    await repo.reconcileRemoteChange({
      'entity': 'product',
      'op': 'upsert',
      'payload': jsonEncode({
        'name': 'Delta Test Product',
        'sku': 'DELTA-01',
        'stock': 20,
        'sale_price': 500,
      }),
    });

    // Verify stock updated
    final prodRows = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
    expect(prodRows.first['stock'], 20);

    // Verify stock_moves has cloud_delta
    final moves = await db.query('stock_moves',
        where: 'product_id = ? AND move_type = ?',
        whereArgs: [prodId, 'cloud_delta']);
    expect(moves.isNotEmpty, isTrue);
    expect((moves.first['change_qty'] as num).toDouble(), -5.0);
    expect((moves.first['qty_after'] as num).toDouble(), 20.0);

    // 3. Remote stock_move entity arrives with change_qty = +8
    await repo.reconcileRemoteChange({
      'entity': 'stock_move',
      'op': 'create',
      'payload': jsonEncode({
        'product_id': prodId,
        'change_qty': 8.0,
        'move_type': 'purchase',
      }),
    });

    // Verify stock became 28
    final prodRowsAfter = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
    expect(prodRowsAfter.first['stock'], 28);
  });

  test('Remote payment reconciles and allocates to existing invoice and balances ledger', () async {
    final repo = Repository.instance;
    final db = await AppDatabase.instance.database;
    await repo.session.load();
    await repo.session.completeOnboarding(1);

    // 1. Create invoice with total = 15000, amountPaid = 0
    final invId = await db.insert('invoices', {
      'business_id': 1,
      'number': 'INV-PAY-SYNC',
      'customer_id': 10,
      'customer_name': 'Ramesh Kumar',
      'total': 15000,
      'amount_paid': 0,
      'status': 'Unpaid',
      'date': '2026-09-21',
    });

    // 2. Reconcile remote payment of 10000
    await repo.reconcileRemoteChange({
      'entity': 'payment',
      'op': 'create',
      'payload': jsonEncode({
        'invoice_number': 'INV-PAY-SYNC',
        'amount': 10000,
        'party_type': 'customer',
        'party_id': 10,
        'party_name': 'Ramesh Kumar',
        'mode': 'UPI',
        'type': 'in',
        'date': '2026-09-22',
      }),
    });

    // 3. Verify invoice amount_paid updated to 10000 and status Partial
    final inv = await db.query('invoices', where: 'id = ?', whereArgs: [invId]);
    expect(inv.first['amount_paid'], 10000);
    expect(inv.first['status'], 'Partially paid');

    // 4. Verify ledger has debit and credit entries
    final ledgerEntries = await db.query('ledger',
        where: 'business_id = ? AND ref_type = ?',
        whereArgs: [1, 'payment']);
    expect(ledgerEntries.length, greaterThanOrEqualTo(2));
    expect(ledgerEntries.any((e) => e['account'] == 'bank' && e['debit'] == 10000), isTrue);
    expect(ledgerEntries.any((e) => e['account'] == 'customer:10' && e['credit'] == 10000), isTrue);
  });

  test('resolveSyncPayload constructs self-healing JSON for queued entities', () async {
    final repo = Repository.instance;
    final db = await AppDatabase.instance.database;
    await repo.session.load();
    await repo.session.completeOnboarding(1);

    final invId = await db.insert('invoices', {
      'business_id': 1,
      'number': 'INV-HEAL-01',
      'customer_name': 'Self Healing Customer',
      'date': '2026-09-25',
      'total': 8500,
      'amount_paid': 8500,
      'status': 'Paid',
    });
    await db.insert('invoice_items', {
      'invoice_id': invId,
      'name': 'Healing Item',
      'quantity': 1.0,
      'price': 8500,
      'taxable': 8500,
      'tax': 0,
    });

    final payload = await repo.resolveSyncPayload('invoice', invId);
    expect(payload, isNotNull);
    final map = jsonDecode(payload!) as Map<String, dynamic>;
    expect(map['number'], 'INV-HEAL-01');
    expect(map['customer_name'], 'Self Healing Customer');
    expect(map['items'], isA<List>());
    expect((map['items'] as List).length, 1);
  });
}

