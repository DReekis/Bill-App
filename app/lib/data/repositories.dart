import 'dart:convert';

import 'package:sqflite/sqflite.dart' hide Batch;

import '../core/billing_engine.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/session.dart';
import '../sync/sync_engine.dart';
import 'app_database.dart';

class Repository {
  Repository._();
  static final Repository instance = Repository._();
  final Session session = Session();
  AppDatabase get _db => AppDatabase.instance;

  Future<Database> get _database async => _db.database;

  Future<void> _audit(int businessId, {
    String action = '',
    String entity = '',
    int? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    final db = await _database;
    await db.insert('audit_log', {
      'business_id': businessId,
      'actor': session.mobile ?? 'owner',
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'before': before == null ? null : jsonEncode(before),
      'after': after == null ? null : jsonEncode(after),
      'timestamp': timestampNow(),
    });
  }

  static int? _safeInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    final s = val.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return null;
    final clean = s.contains('_') ? s.split('_').last : s;
    return int.tryParse(clean);
  }

  static double? _safeDouble(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is num) return val.toDouble();
    final s = val.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return null;
    return double.tryParse(s);
  }

  Future<void> _enqueueSync(int businessId, {
    required String entity,
    required int entityId,
    required String op,
    String? payload,
  }) async {
    final db = await _database;
    await db.insert('sync_queue', {
      'business_id': businessId,
      'entity': entity,
      'entity_id': entityId,
      'op': op,
      'payload': payload,
      'idempotency_key': '${session.mobile ?? 'device'}#$entity#$entityId#$op#${DateTime.now().millisecondsSinceEpoch}',
      'status': 'pending',
      'attempts': 0,
      'created_at': timestampNow(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    SyncEngine.instance.triggerSync();
  }

  Future<void> _syncOpeningBalance(Database db, int businessId, {
    required String account,
    required int amount,
    required String name,
    bool opening = true,
    bool supplierCredit = false,
  }) async {
    if (amount == 0) return;
    final isCustomer = !supplierCredit;
    final debit = isCustomer
        ? (amount > 0 ? amount : 0)
        : (amount < 0 ? -amount : 0);
    final credit = isCustomer
        ? (amount < 0 ? -amount : 0)
        : (amount > 0 ? amount : 0);
    await db.insert('ledger', {
      'business_id': businessId,
      'date': todayIso(),
      'account': account,
      'debit': debit,
      'credit': credit,
      'note': opening ? 'Opening balance $name' : 'Opening balance adjustment $name',
    });
  }

  Future<int> createBusiness(Business business) async {
    final db = await _database;
    final id = await db.insert('businesses', business.toMap());
    await _audit(id,
        action: 'create', entity: 'business', entityId: id, after: business.toMap());
    return id;
  }

  Future<Business?> getBusiness(int id) async {
    final db = await _database;
    final rows = await db.query('businesses', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Business.fromMap(rows.first);
  }

  Future<List<Business>> allBusinesses() async {
    final db = await _database;
    final rows = await db.query('businesses', orderBy: 'id ASC');
    return rows.map(Business.fromMap).toList();
  }

  Future<void> updateBusiness(Business business, {int? businessIdOverride}) async {
    final db = await _database;
    final id = businessIdOverride ?? business.id ?? session.businessId;
    if (id == null) return;
    await db.update('businesses', business.toMap(), where: 'id = ?', whereArgs: [id]);
    await _audit(id, action: 'update', entity: 'business', entityId: id, after: business.toMap());
  }

  Future<int> _resolveHighestInvoiceSequence(DatabaseExecutor db, int businessId, String prefix) async {
    final rows = await db.query('businesses',
        columns: ['invoice_sequence'], where: 'id = ?', whereArgs: [businessId]);
    int highest = rows.isNotEmpty ? (rows.first['invoice_sequence'] as int? ?? 0) : 0;

    final pfx = prefix.trim().isEmpty ? 'INV' : prefix.trim().toUpperCase();
    final invRows = await db.rawQuery(
      "SELECT number FROM invoices WHERE business_id = ? AND (number LIKE ? OR number LIKE ?)",
      [businessId, '$pfx-%', '$pfx%'],
    );
    for (final r in invRows) {
      final numStr = r['number'] as String?;
      if (numStr != null) {
        final seq = InvoiceNumbering.extractSequence(numStr);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextInvoiceNumber(int businessId, String prefix) async {
    final db = await _database;
    return db.transaction((txn) async {
      final highest = await _resolveHighestInvoiceSequence(txn, businessId, prefix);
      int candidateSeq = highest + 1;
      while (true) {
        final candidate = InvoiceNumbering.format(prefix, candidateSeq);
        final exists = await txn.query('invoices',
            columns: ['id'],
            where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
            whereArgs: [businessId, candidate.trim().toLowerCase()],
            limit: 1);
        if (exists.isEmpty) {
          await txn.update('businesses', {'invoice_sequence': candidateSeq},
              where: 'id = ?', whereArgs: [businessId]);
          return candidate;
        }
        candidateSeq++;
      }
    });
  }

  Future<String> peekNextInvoiceNumber(int businessId, String prefix) async {
    final db = await _database;
    final highest = await _resolveHighestInvoiceSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('invoices',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<bool> isInvoiceNumberAvailable(int businessId, String number, {int? excludeInvoiceId}) async {
    final db = await _database;
    final where = <String>['business_id = ?', 'LOWER(TRIM(number)) = ?'];
    final args = <Object?>[businessId, number.trim().toLowerCase()];
    if (excludeInvoiceId != null) {
      where.add('id != ?');
      args.add(excludeInvoiceId);
    }
    final rows = await db.query('invoices',
        columns: ['id'],
        where: where.join(' AND '),
        whereArgs: args,
        limit: 1);
    return rows.isEmpty;
  }

  Future<int> _resolveHighestQuotationSequence(DatabaseExecutor db, int businessId, String prefix) async {
    final rows = await db.query('businesses',
        columns: ['quotation_sequence'], where: 'id = ?', whereArgs: [businessId]);
    int highest = rows.isNotEmpty ? (rows.first['quotation_sequence'] as int? ?? 0) : 0;

    final pfx = prefix.trim().isEmpty ? 'EST' : prefix.trim().toUpperCase();
    final qRows = await db.rawQuery(
      "SELECT number FROM quotations WHERE business_id = ? AND (number LIKE ? OR number LIKE ?)",
      [businessId, '$pfx-%', '$pfx%'],
    );
    for (final r in qRows) {
      final numStr = r['number'] as String?;
      if (numStr != null) {
        final seq = InvoiceNumbering.extractSequence(numStr);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextQuotationNumber(int businessId, String prefix) async {
    final db = await _database;
    return db.transaction((txn) async {
      final highest = await _resolveHighestQuotationSequence(txn, businessId, prefix);
      int candidateSeq = highest + 1;
      while (true) {
        final candidate = InvoiceNumbering.format(prefix, candidateSeq);
        final exists = await txn.query('quotations',
            columns: ['id'],
            where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
            whereArgs: [businessId, candidate.trim().toLowerCase()],
            limit: 1);
        if (exists.isEmpty) {
          await txn.update('businesses', {'quotation_sequence': candidateSeq},
              where: 'id = ?', whereArgs: [businessId]);
          return candidate;
        }
        candidateSeq++;
      }
    });
  }

  Future<String> peekNextQuotationNumber(int businessId, String prefix) async {
    final db = await _database;
    final highest = await _resolveHighestQuotationSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('quotations',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<int> _resolveHighestPurchaseSequence(DatabaseExecutor db, int businessId, String prefix) async {
    final rows = await db.query('businesses',
        columns: ['purchase_sequence'], where: 'id = ?', whereArgs: [businessId]);
    int highest = rows.isNotEmpty ? (rows.first['purchase_sequence'] as int? ?? 0) : 0;

    final pfx = prefix.trim().isEmpty ? 'PUR' : prefix.trim().toUpperCase();
    final expRows = await db.rawQuery(
      "SELECT description FROM expenses WHERE business_id = ? AND category = 'Purchase'",
      [businessId],
    );
    for (final r in expRows) {
      final desc = r['description'] as String?;
      if (desc != null && desc.contains(pfx)) {
        final seq = InvoiceNumbering.extractSequence(desc);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextPurchaseNumber(int businessId, String prefix) async {
    final db = await _database;
    return db.transaction((txn) async {
      final highest = await _resolveHighestPurchaseSequence(txn, businessId, prefix);
      final next = highest + 1;
      await txn.update('businesses', {'purchase_sequence': next},
          where: 'id = ?', whereArgs: [businessId]);
      return InvoiceNumbering.format(prefix, next);
    });
  }

  Future<String> peekNextPurchaseNumber(int businessId, String prefix) async {
    final db = await _database;
    final highest = await _resolveHighestPurchaseSequence(db, businessId, prefix);
    return InvoiceNumbering.format(prefix, highest + 1);
  }

  Future<int> _resolveHighestSalesOrderSequence(DatabaseExecutor db, int businessId, String prefix) async {
    int highest = 0;
    final pfx = prefix.trim().isEmpty ? 'SO' : prefix.trim().toUpperCase();
    final rows = await db.rawQuery(
      "SELECT number FROM sales_orders WHERE business_id = ? AND (number LIKE ? OR number LIKE ?)",
      [businessId, '$pfx-%', '$pfx%'],
    );
    for (final r in rows) {
      final numStr = r['number'] as String?;
      if (numStr != null) {
        final seq = InvoiceNumbering.extractSequence(numStr);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextSalesOrderNumber(int businessId, [String prefix = 'SO']) async {
    final db = await _database;
    final highest = await _resolveHighestSalesOrderSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('sales_orders',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<String> peekNextSalesOrderNumber(int businessId, [String prefix = 'SO']) async {
    final db = await _database;
    final highest = await _resolveHighestSalesOrderSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('sales_orders',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<int> _resolveHighestPurchaseOrderSequence(DatabaseExecutor db, int businessId, String prefix) async {
    int highest = 0;
    final pfx = prefix.trim().isEmpty ? 'PO' : prefix.trim().toUpperCase();
    final rows = await db.rawQuery(
      "SELECT number FROM purchase_orders WHERE business_id = ? AND (number LIKE ? OR number LIKE ?)",
      [businessId, '$pfx-%', '$pfx%'],
    );
    for (final r in rows) {
      final numStr = r['number'] as String?;
      if (numStr != null) {
        final seq = InvoiceNumbering.extractSequence(numStr);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextPurchaseOrderNumber(int businessId, [String prefix = 'PO']) async {
    final db = await _database;
    final highest = await _resolveHighestPurchaseOrderSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('purchase_orders',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<String> peekNextPurchaseOrderNumber(int businessId, [String prefix = 'PO']) async {
    final db = await _database;
    final highest = await _resolveHighestPurchaseOrderSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('purchase_orders',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<int> _resolveHighestChallanSequence(DatabaseExecutor db, int businessId, String prefix) async {
    int highest = 0;
    final pfx = prefix.trim().isEmpty ? 'DC' : prefix.trim().toUpperCase();
    final rows = await db.rawQuery(
      "SELECT number FROM delivery_challans WHERE business_id = ? AND (number LIKE ? OR number LIKE ?)",
      [businessId, '$pfx-%', '$pfx%'],
    );
    for (final r in rows) {
      final numStr = r['number'] as String?;
      if (numStr != null) {
        final seq = InvoiceNumbering.extractSequence(numStr);
        if (seq != null && seq > highest) {
          highest = seq;
        }
      }
    }
    return highest;
  }

  Future<String> nextChallanNumber(int businessId, [String prefix = 'DC']) async {
    final db = await _database;
    final highest = await _resolveHighestChallanSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('delivery_challans',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<String> peekNextChallanNumber(int businessId, [String prefix = 'DC']) async {
    final db = await _database;
    final highest = await _resolveHighestChallanSequence(db, businessId, prefix);
    int candidateSeq = highest + 1;
    while (true) {
      final candidate = InvoiceNumbering.format(prefix, candidateSeq);
      final exists = await db.query('delivery_challans',
          columns: ['id'],
          where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
          whereArgs: [businessId, candidate.trim().toLowerCase()],
          limit: 1);
      if (exists.isEmpty) {
        return candidate;
      }
      candidateSeq++;
    }
  }

  Future<int> upsertCustomer(Customer customer, {int? businessIdOverride}) async {
    final db = await _database;
    final businessId = businessIdOverride ?? session.businessId;
    if (businessId == null) throw StateError('no active business');
    final map = customer.toMap()..['business_id'] = businessId;
    if (customer.id == null) {
      final id = await db.insert('customers', map);
      await _audit(businessId,
          action: 'create', entity: 'customer', entityId: id, after: map);
      await _enqueueSync(businessId, entity: 'customer', entityId: id, op: 'upsert', payload: jsonEncode(map));
      await _syncOpeningBalance(db, businessId, account: 'customer:$id',
          amount: customer.openingBalance, name: customer.name);
      return id;
    }
    final before = await db.query('customers',
        where: 'id = ?', whereArgs: [customer.id]);
    await db.update('customers', map, where: 'id = ?', whereArgs: [customer.id]);
    await _audit(businessId,
        action: 'update',
        entity: 'customer',
        entityId: customer.id,
        before: before.isEmpty ? null : before.first,
        after: map);
    if (before.isNotEmpty) {
      final oldOpening = (before.first['opening_balance'] as num?)?.toInt() ?? 0;
      final delta = customer.openingBalance - oldOpening;
      if (delta != 0) {
        await _syncOpeningBalance(db, businessId, account: 'customer:${customer.id}',
            amount: delta, name: customer.name, opening: false);
      }
    }
    await _enqueueSync(businessId,
        entity: 'customer', entityId: customer.id!, op: 'upsert', payload: jsonEncode(map));
    return customer.id!;
  }

  Future<List<Customer>> customers(int businessId, {bool includeInactive = false}) async {
    final db = await _database;
    final rows = await db.query('customers',
        where: 'business_id = ?${includeInactive ? '' : ' AND inactive = 0'}',
        whereArgs: [businessId],
        orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> customer(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('customers',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<void> softDeleteCustomer(int businessId, int id) async {
    final db = await _database;
    await db.update('customers', {'inactive': 1}, where: 'id = ?', whereArgs: [id]);
    await _audit(businessId, action: 'delete', entity: 'customer', entityId: id);
  }

  Future<int> upsertSupplier(Supplier supplier, {int? businessIdOverride}) async {
    final db = await _database;
    final businessId = businessIdOverride ?? session.businessId;
    if (businessId == null) throw StateError('no active business');
    final map = supplier.toMap()..['business_id'] = businessId;
    if (supplier.id == null) {
      final id = await db.insert('suppliers', map);
      await _audit(businessId,
          action: 'create', entity: 'supplier', entityId: id, after: map);
      await _enqueueSync(businessId, entity: 'supplier', entityId: id, op: 'upsert', payload: jsonEncode(map));
      await _syncOpeningBalance(db, businessId, account: 'supplier:$id',
          amount: supplier.openingBalance, name: supplier.name, supplierCredit: true);
      return id;
    }
    final before = await db.query('suppliers',
        where: 'id = ?', whereArgs: [supplier.id]);
    await db.update('suppliers', map, where: 'id = ?', whereArgs: [supplier.id]);
    await _audit(businessId,
        action: 'update',
        entity: 'supplier',
        entityId: supplier.id,
        before: before.isEmpty ? null : before.first,
        after: map);
    if (before.isNotEmpty) {
      final oldOpening = (before.first['opening_balance'] as num?)?.toInt() ?? 0;
      final delta = supplier.openingBalance - oldOpening;
      if (delta != 0) {
        await _syncOpeningBalance(db, businessId, account: 'supplier:${supplier.id}',
            amount: delta, name: supplier.name, opening: false, supplierCredit: true);
      }
    }
    await _enqueueSync(businessId,
        entity: 'supplier', entityId: supplier.id!, op: 'upsert', payload: jsonEncode(map));
    return supplier.id!;
  }

  Future<List<Supplier>> suppliers(int businessId, {bool includeInactive = false}) async {
    final db = await _database;
    final rows = await db.query('suppliers',
        where: 'business_id = ?${includeInactive ? '' : ' AND inactive = 0'}',
        whereArgs: [businessId],
        orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> supplier(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('suppliers',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    return rows.isEmpty ? null : Supplier.fromMap(rows.first);
  }

  Future<void> softDeleteSupplier(int businessId, int id) async {
    final db = await _database;
    await db.update('suppliers', {'inactive': 1}, where: 'id = ?', whereArgs: [id]);
    await _audit(businessId, action: 'delete', entity: 'supplier', entityId: id);
  }

  Future<List<Invoice>> invoicesForParty(int businessId, String partyType, int? partyId) async {
    final db = await _database;
    final column = partyType == 'customer' ? 'customer_id' : 'party_id';
    final table = partyType == 'customer' ? 'invoices' : 'payments';
    final String whereClause;
    final List<Object?> whereArgs;
    if (partyId == null || partyId == 0) {
      whereClause = 'business_id = ? AND ($column IS NULL OR $column = 0)';
      whereArgs = [businessId];
    } else {
      whereClause = 'business_id = ? AND $column = ?';
      whereArgs = [businessId, partyId];
    }
    final rows = await db.query(table,
        where: whereClause, whereArgs: whereArgs,
        orderBy: 'date DESC, id DESC');
    if (partyType != 'customer') return const [];
    return rows.map(Invoice.fromMap).toList();
  }

  Future<int> upsertProduct(Product product, {int? businessIdOverride}) async {
    final db = await _database;
    final businessId = businessIdOverride ?? session.businessId;
    if (businessId == null) throw StateError('no active business');
    final map = product.toMap()..['business_id'] = businessId;
    if (product.id == null) {
      // only compare the identifiers that were actually filled in; passing a
      // null whereArg is unsupported by sqflite and matches nothing anyway
      final sku = product.sku?.trim() ?? '';
      final barcode = product.barcode?.trim() ?? '';
      final clauses = <String>[];
      final args = <Object?>[businessId];
      if (sku.isNotEmpty) {
        clauses.add('sku = ?');
        args.add(sku);
      }
      if (barcode.isNotEmpty) {
        clauses.add('barcode = ?');
        args.add(barcode);
      }
      if (clauses.isNotEmpty) {
        final check = await db.query('products',
            where: 'business_id = ? AND (${clauses.join(' OR ')})',
            whereArgs: args,
            limit: 1);
        if (check.isNotEmpty) {
          throw StateError('Product with same SKU/barcode exists');
        }
      }
      final id = await db.insert('products', map);
      await _audit(businessId,
          action: 'create', entity: 'product', entityId: id, after: map);
      await _enqueueSync(businessId, entity: 'product', entityId: id, op: 'upsert', payload: jsonEncode(map));
      if (product.stock != 0) {
        await db.insert('stock_moves', {
          'business_id': businessId,
          'product_id': id,
          'change_qty': product.stock,
          'qty_after': product.stock,
          'move_type': 'opening',
          'date': todayIso(),
        });
      }
      return id;
    }
    final before = await db.query('products', where: 'id = ?', whereArgs: [product.id]);
    final beforeStock = before.isNotEmpty ? ((before.first['stock'] as num?)?.toInt() ?? 0) : 0;
    await db.update('products', map, where: 'id = ?', whereArgs: [product.id]);
    if (product.stock != beforeStock) {
      await db.insert('stock_moves', {
        'business_id': businessId,
        'product_id': product.id,
        'change_qty': (product.stock - beforeStock).toDouble(),
        'qty_after': product.stock.toDouble(),
        'move_type': 'adjustment',
        'date': todayIso(),
      });
    }
    await _audit(businessId,
        action: 'update',
        entity: 'product',
        entityId: product.id,
        before: before.isEmpty ? null : before.first,
        after: map);
    await _enqueueSync(businessId,
        entity: 'product', entityId: product.id!, op: 'upsert', payload: jsonEncode(map));
    return product.id!;
  }

  Future<List<Product>> products(int businessId, {bool includeInactive = false}) async {
    final db = await _database;
    final rows = await db.query('products',
        where: 'business_id = ?${includeInactive ? '' : ' AND inactive = 0'}',
        whereArgs: [businessId],
        orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> productBySku(int businessId, String query) async {
    final db = await _database;
    final rows = await db.query('products',
        where: 'business_id = ? AND (sku = ? OR barcode = ? OR name LIKE ?)',
        whereArgs: [businessId, query, query, '%$query%'],
        limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<void> adjustStock(Product product, double change, String moveType,
      {String? refType,
      int? refId,
      String? reason,
      int? newPurchasePrice,
      int? newSalePrice,
      String? newExpiryDate}) async {
    final db = await _database;
    final businessId = session.businessId;
    if (businessId == null) return;
    final newQty = (product.stock + change).round();

    final updates = <String, Object?>{'stock': newQty};

    if (newSalePrice != null && newSalePrice > 0) {
      updates['sale_price'] = newSalePrice;
      product.salePrice = newSalePrice;
    }

    if (newPurchasePrice != null && newPurchasePrice > 0) {
      updates['purchase_price'] = newPurchasePrice;
      product.purchasePrice = newPurchasePrice;

      if (change > 0) {
        final oldStock = product.stock > 0 ? product.stock : 0;
        final oldCost = oldStock *
            (product.costAverage > 0
                ? product.costAverage
                : product.purchasePrice);
        final addedCost = (change * newPurchasePrice).round();
        final totalQty = oldStock + change;
        if (totalQty > 0) {
          final newAvg = ((oldCost + addedCost) / totalQty).round();
          updates['cost_average'] = newAvg;
          product.costAverage = newAvg;
        }
      }
    }

    if (newExpiryDate != null && newExpiryDate.trim().isNotEmpty) {
      final exp = newExpiryDate.trim();
      updates['expiry_date'] = exp;
      product.expiryDate = exp;
      try {
        await db.insert('batches', {
          'business_id': businessId,
          'product_id': product.id,
          'batch_number':
              'ADJ-${DateTime.now().millisecondsSinceEpoch % 1000000}',
          'expiry_date': exp,
          'quantity':
              change > 0 ? change : (newQty > 0 ? newQty.toDouble() : 0.0),
          'purchase_price': newPurchasePrice ?? product.purchasePrice,
          'sale_price': newSalePrice ?? product.salePrice,
        });
      } catch (_) {}
    }

    final success = await db.update(
      'products',
      updates,
      where: 'id = ?',
      whereArgs: [product.id],
    );
    if (success == 0) return;
    final effectiveMoveType = (reason != null && reason.trim().isNotEmpty)
        ? '$moveType: ${reason.trim()}'
        : moveType;
    await db.insert('stock_moves', {
      'business_id': businessId,
      'product_id': product.id,
      'change_qty': change,
      'qty_after': newQty.toDouble(),
      'move_type': effectiveMoveType,
      'ref_type': refType,
      'ref_id': refId,
      'date': todayIso(),
    });
    product.stock = newQty;
    if (product.id != null) {
      await _enqueueSync(
        businessId,
        entity: 'product',
        entityId: product.id!,
        op: 'upsert',
        payload: jsonEncode(updates),
      );
    }
  }

  Future<int> finalizeSale({
    required int businessId,
    required String number,
    required int? customerId,
    required String customerName,
    required String date,
    String? dueDate,
    required String gstType,
    required QuoteResult quote,
    required List<InvoiceLine> lines,
    String? paymentMode,
    String? notes,
    required int amountPaid,
    String? shipToName,
    String? shipToAddress,
    String? shipToState,
    String? shipToPincode,
    String? placeOfSupply,
    String? poNumber,
    String? poDate,
    String? vehicleNumber,
    String? ewayBillNumber,
    String? lrRrNumber,
    bool reverseCharge = false,
    String? customFieldsJson,
  }) async {
    final db = await _database;
    String finalNumber = number;
    final invoiceId = await db.transaction<int>((txn) async {
      final total = quote.total.paise;
      final status = resolveInvoiceStatus(total: total, amountPaid: amountPaid);

      // Verify number availability; if taken, automatically resolve to next sequence candidate
      final exists = await txn.query(
        'invoices',
        columns: ['id'],
        where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
        whereArgs: [businessId, number.trim().toLowerCase()],
        limit: 1,
      );
      if (exists.isNotEmpty) {
        final bizRows = await txn.query('businesses',
            columns: ['invoice_prefix'], where: 'id = ?', whereArgs: [businessId], limit: 1);
        final pfx = bizRows.isNotEmpty ? (bizRows.first['invoice_prefix'] as String? ?? 'INV') : 'INV';
        final highest = await _resolveHighestInvoiceSequence(txn, businessId, pfx);
        int cand = highest + 1;
        while (true) {
          final testNum = InvoiceNumbering.format(pfx, cand);
          final clash = await txn.query(
            'invoices',
            columns: ['id'],
            where: 'business_id = ? AND LOWER(TRIM(number)) = ?',
            whereArgs: [businessId, testNum.trim().toLowerCase()],
            limit: 1,
          );
          if (clash.isEmpty) {
            finalNumber = testNum;
            break;
          }
          cand++;
        }
      }

      final invoiceId = await txn.insert('invoices', {
        'business_id': businessId,
        'number': finalNumber,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'due_date': dueDate,
        'gst_type': gstType,
        'subtotal': quote.subtotal.paise,
        'discount': quote.itemDiscount.paise + quote.invoiceDiscount.paise,
        'discount_type': quote.lines.any((l) => l.discount.paise > 0) ? 'item' : null,
        'taxable': quote.taxable.paise,
        'cgst': quote.cgst.paise,
        'sgst': quote.sgst.paise,
        'igst': quote.igst.paise,
        'cess': quote.cess.paise,
        'round_off': quote.roundOff.paise,
        'total': total,
        'amount_paid': amountPaid,
        'payment_mode': paymentMode,
        'status': status,
        'notes': notes,
        'ship_to_name': shipToName,
        'ship_to_address': shipToAddress,
        'ship_to_state': shipToState,
        'ship_to_pincode': shipToPincode,
        'place_of_supply': placeOfSupply,
        'po_number': poNumber,
        'po_date': poDate,
        'vehicle_number': vehicleNumber,
        'eway_bill_number': ewayBillNumber,
        'lr_rr_number': lrRrNumber,
        'reverse_charge': reverseCharge ? 1 : 0,
        'custom_fields_json': customFieldsJson ?? '{}',
      });

      // Automatically advance invoice_sequence in businesses table
      final seq = InvoiceNumbering.extractSequence(finalNumber);
      if (seq != null) {
        final currentSeqRows = await txn.query('businesses',
            columns: ['invoice_sequence'], where: 'id = ?', whereArgs: [businessId]);
        final curSeq = currentSeqRows.isNotEmpty ? (currentSeqRows.first['invoice_sequence'] as int? ?? 0) : 0;
        if (seq > curSeq) {
          await txn.update('businesses', {'invoice_sequence': seq},
              where: 'id = ?', whereArgs: [businessId]);
        }
      }

      for (final line in lines) {
        await txn.insert('invoice_items', {
          'invoice_id': invoiceId,
          'product_id': line.productId,
          'name': line.name,
          'hsn': line.hsn,
          'gst_rate': line.gstRate,
          'quantity': line.quantity,
          'price': line.price,
          'discount': line.discount,
          'discount_percent': line.discountPercent,
          'taxable': line.taxable,
          'tax': line.tax,
          'unit': line.unit,
        });
      }

      final bizRows = await txn.query('businesses',
          columns: ['allow_negative_stock'], where: 'id = ?', whereArgs: [businessId], limit: 1);
      final allowNegative = (bizRows.isEmpty ? 1 : (bizRows.first['allow_negative_stock'] as int? ?? 1)) == 1;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.productId == null) continue;

        // Serial Validation
        if (line.serialNumber != null) {
          final sRows = await txn.query('serial_numbers', where: 'serial_number = ? AND status = ?', whereArgs: [line.serialNumber, 'Available'], limit: 1);
          if (sRows.isEmpty) throw StateError('Serial Number ${line.serialNumber} not available');
          await txn.update('serial_numbers', {'status': 'Sold', 'sale_ref': finalNumber}, where: 'serial_number = ?', whereArgs: [line.serialNumber]);
        }

        // Batch Validation (Simple check for expiry)
        if (line.batchNumber != null) {
          final bRows = await txn.query('batches', where: 'batch_number = ? AND product_id = ?', whereArgs: [line.batchNumber, line.productId], limit: 1);
          if (bRows.isNotEmpty) {
            final expiry = bRows.first['expiry_date'] as String?;
            if (expiry != null && DateTime.parse(expiry).isBefore(DateTime.now())) {
              throw StateError('Batch ${line.batchNumber} has expired');
            }
          }
        }

        final product = await txn.query('products',
            where: 'id = ?', whereArgs: [line.productId], limit: 1);
        if (product.isEmpty) continue;

        // Unit Conversion Logic
        double qtyToDeduct = line.quantity;
        // Check if there's a conversion for this product
        final convRows = await txn.query('unit_conversions', where: 'product_id = ? AND from_unit = ?', whereArgs: [line.productId, line.unit ?? ''], limit: 1);
        if (convRows.isNotEmpty) {
          final multiplier = (convRows.first['multiplier'] as num).toDouble();
          qtyToDeduct = line.quantity * multiplier;
        }

        final current = (product.first['stock'] as num?)?.toDouble() ?? 0;
        final next = current - qtyToDeduct;
        if (!allowNegative && next < 0) {
          throw StateError('Not enough stock for ${line.name} — only ${_qty(current)} in stock');
        }
        await txn.update('products', {'stock': next.round()},
            where: 'id = ?', whereArgs: [line.productId]);
        await txn.insert('stock_moves', {
          'business_id': businessId,
          'product_id': line.productId,
          'change_qty': -qtyToDeduct,
          'qty_after': next,
          'move_type': 'sale',
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'date': date,
        });

        final cost = (product.first['cost_average'] as int? ?? 0);
        final cogs = Money(cost).multiply(line.quantity).paise;
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'cogs',
          'debit': cogs,
          'credit': 0,
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'note': 'COGS ${line.name} x${_qty(line.quantity)}',
        });
      }

      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': 'income:sales',
        'debit': 0,
        'credit': quote.taxable.paise,
        'ref_type': 'invoice',
        'ref_id': invoiceId,
        'note': 'Sales $finalNumber',
      });
      final taxAmount = quote.cgst.paise + quote.sgst.paise + quote.igst.paise;
      if (taxAmount > 0) {
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'gst:output',
          'debit': 0,
          'credit': taxAmount,
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'note': 'GST output $finalNumber',
        });
      }
      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': 'customer:${customerId ?? 0}',
        'debit': total,
        'credit': 0,
        'ref_type': 'invoice',
        'ref_id': invoiceId,
        'note': '$customerName — $finalNumber',
      });
      if (amountPaid > 0) {
        final paymentId = await txn.insert('payments', {
          'business_id': businessId,
          'party_type': 'customer',
          'party_id': customerId,
          'party_name': customerName,
          'invoice_id': invoiceId,
          'invoice_number': finalNumber,
          'amount': amountPaid,
          'mode': paymentMode ?? 'Cash',
          'date': date,
          'type': 'in',
          'reference': 'initial_sale',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': paymentMode == 'Cash' ? 'cash' : 'bank',
          'debit': amountPaid,
          'credit': 0,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Payment in $finalNumber',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'customer:${customerId ?? 0}',
          'debit': 0,
          'credit': amountPaid,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Receipt $finalNumber',
        });
      }
      return invoiceId;
    });
    await _audit(businessId,
        action: 'create', entity: 'invoice', entityId: invoiceId, after: {'number': finalNumber, 'total': quote.total.paise});
    final invoicePayload = {
      'id': invoiceId,
      'businessId': businessId.toString(),
      'number': finalNumber,
      'customerId': customerId?.toString(),
      'customerName': customerName,
      'date': date,
      'dueDate': dueDate,
      'gstType': gstType,
      'subtotal': quote.subtotal.paise,
      'discount': quote.itemDiscount.paise + quote.invoiceDiscount.paise,
      'taxable': quote.taxable.paise,
      'cgst': quote.cgst.paise,
      'sgst': quote.sgst.paise,
      'igst': quote.igst.paise,
      'roundOff': quote.roundOff.paise,
      'total': quote.total.paise,
      'amountPaid': amountPaid,
      'paymentMode': paymentMode,
      'status': resolveInvoiceStatus(total: quote.total.paise, amountPaid: amountPaid),
      'notes': notes,
      'items': lines.map((l) => {
        'productId': l.productId?.toString(),
        'name': l.name,
        'hsn': l.hsn,
        'quantity': l.quantity,
        'price': l.price,
        'discount': l.discount,
        'gstRate': l.gstRate,
        'taxable': l.taxable,
        'tax': l.tax,
      }).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _enqueueSync(businessId, entity: 'invoice', entityId: invoiceId, op: 'create', payload: jsonEncode(invoicePayload));
    return invoiceId;
  }

  Future<void> updateSale({
    required int businessId,
    required int invoiceId,
    required String number,
    required int? customerId,
    required String customerName,
    required String date,
    String? dueDate,
    required String gstType,
    required QuoteResult quote,
    required List<InvoiceLine> lines,
    String? paymentMode,
    String? notes,
    required int amountPaid,
    String? shipToName,
    String? shipToAddress,
    String? shipToState,
    String? shipToPincode,
    String? placeOfSupply,
    String? poNumber,
    String? poDate,
    String? vehicleNumber,
    String? ewayBillNumber,
    String? lrRrNumber,
    bool reverseCharge = false,
    String? customFieldsJson,
  }) async {
    final db = await _database;
    Map<String, Object?>? beforeAudit;
    await db.transaction<void>((txn) async {
      // 1. Verify existence of invoice
      final existingRows = await txn.query('invoices',
          where: 'business_id = ? AND id = ?',
          whereArgs: [businessId, invoiceId],
          limit: 1);
      if (existingRows.isEmpty) {
        throw StateError('Invoice $invoiceId not found');
      }
      final oldInv = existingRows.first;
      final oldItems = await txn.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      beforeAudit = {
        'id': invoiceId,
        'number': oldInv['number'],
        'customer_name': oldInv['customer_name'],
        'customer_id': oldInv['customer_id'],
        'total': oldInv['total'],
        'subtotal': oldInv['subtotal'],
        'taxable': oldInv['taxable'],
        'status': oldInv['status'],
        'items_count': oldItems.length,
      };

      // Check number availability if changed
      final oldNumber = existingRows.first['number'] as String;
      if (number.trim().toLowerCase() != oldNumber.trim().toLowerCase()) {
        final clashRows = await txn.query('invoices',
            columns: ['id'],
            where: 'business_id = ? AND LOWER(TRIM(number)) = ? AND id != ?',
            whereArgs: [businessId, number.trim().toLowerCase(), invoiceId],
            limit: 1);
        if (clashRows.isNotEmpty) {
          throw StateError('Invoice number $number is already taken');
        }
      }

      // 2. Revert previous inventory deductions from stock moves
      final oldMoves = await txn.query('stock_moves',
          where: 'ref_type = ? AND ref_id = ?', whereArgs: ['invoice', invoiceId]);
      for (final m in oldMoves) {
        final prodId = m['product_id'] as int?;
        final changeQty = (m['change_qty'] as num?)?.toDouble() ?? 0.0;
        if (prodId != null && changeQty < 0) {
          final qtyToRestore = -changeQty;
          final pRows = await txn.query('products',
              where: 'id = ?', whereArgs: [prodId], limit: 1);
          if (pRows.isNotEmpty) {
            final curStock = (pRows.first['stock'] as num?)?.toDouble() ?? 0.0;
            await txn.update('products', {'stock': curStock + qtyToRestore},
                where: 'id = ?', whereArgs: [prodId]);
          }
        }
      }

      // Revert old serials marked Sold under the old invoice number
      await txn.update('serial_numbers', {'status': 'Available', 'sale_ref': null},
          where: 'sale_ref = ?', whereArgs: [oldNumber]);

      // Delete old stock moves for this invoice
      await txn.delete('stock_moves',
          where: 'ref_type = ? AND ref_id = ?', whereArgs: ['invoice', invoiceId]);

      // 3. Revert old ledger entries for this invoice
      await txn.delete('ledger',
          where: 'ref_type = ? AND ref_id = ?', whereArgs: ['invoice', invoiceId]);

      // 4. Remove previous linked payment records and payment ledger entries
      final linkedPayments = await txn.query('payments',
          where: 'invoice_id = ? AND type = ?', whereArgs: [invoiceId, 'in']);
      for (final p in linkedPayments) {
        final pId = p['id'] as int;
        await txn.delete('ledger',
            where: 'ref_type = ? AND ref_id = ?', whereArgs: ['payment', pId]);
        await txn.delete('payments', where: 'id = ?', whereArgs: [pId]);
      }

      // 5. Delete old invoice items
      await txn.delete('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);

      // 6. Insert updated invoice items
      for (final line in lines) {
        await txn.insert('invoice_items', {
          'invoice_id': invoiceId,
          'product_id': line.productId,
          'name': line.name,
          'hsn': line.hsn,
          'gst_rate': line.gstRate,
          'quantity': line.quantity,
          'price': line.price,
          'discount': line.discount,
          'discount_percent': line.discountPercent,
          'taxable': line.taxable,
          'tax': line.tax,
          'unit': line.unit,
        });
      }

      // 7. Apply new stock deductions, serials, batches and COGS
      final bizRows = await txn.query('businesses',
          columns: ['allow_negative_stock'],
          where: 'id = ?',
          whereArgs: [businessId],
          limit: 1);
      final allowNegative = (bizRows.isEmpty
              ? 1
              : (bizRows.first['allow_negative_stock'] as int? ?? 1)) ==
          1;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.productId == null) continue;

        // Serial validation
        if (line.serialNumber != null) {
          final sRows = await txn.query('serial_numbers',
              where: 'serial_number = ? AND status = ?',
              whereArgs: [line.serialNumber, 'Available'],
              limit: 1);
          if (sRows.isEmpty) {
            throw StateError('Serial Number ${line.serialNumber} not available');
          }
          await txn.update('serial_numbers', {'status': 'Sold', 'sale_ref': number},
              where: 'serial_number = ?', whereArgs: [line.serialNumber]);
        }

        // Batch validation
        if (line.batchNumber != null) {
          final bRows = await txn.query('batches',
              where: 'batch_number = ? AND product_id = ?',
              whereArgs: [line.batchNumber, line.productId],
              limit: 1);
          if (bRows.isNotEmpty) {
            final expiry = bRows.first['expiry_date'] as String?;
            if (expiry != null && DateTime.parse(expiry).isBefore(DateTime.now())) {
              throw StateError('Batch ${line.batchNumber} has expired');
            }
          }
        }

        final product = await txn.query('products',
            where: 'id = ?', whereArgs: [line.productId], limit: 1);
        if (product.isEmpty) continue;

        double qtyToDeduct = line.quantity;
        final convRows = await txn.query('unit_conversions',
            where: 'product_id = ? AND from_unit = ?',
            whereArgs: [line.productId, line.unit ?? ''],
            limit: 1);
        if (convRows.isNotEmpty) {
          final multiplier = (convRows.first['multiplier'] as num).toDouble();
          qtyToDeduct = line.quantity * multiplier;
        }

        final current = (product.first['stock'] as num?)?.toDouble() ?? 0;
        final next = current - qtyToDeduct;
        if (!allowNegative && next < 0) {
          throw StateError(
              'Not enough stock for ${line.name} — only ${_qty(current)} in stock');
        }
        await txn.update('products', {'stock': next.round()},
            where: 'id = ?', whereArgs: [line.productId]);
        await txn.insert('stock_moves', {
          'business_id': businessId,
          'product_id': line.productId,
          'change_qty': -qtyToDeduct,
          'qty_after': next,
          'move_type': 'sale',
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'date': date,
        });

        final cost = (product.first['cost_average'] as int? ?? 0);
        final cogs = Money(cost).multiply(line.quantity).paise;
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'cogs',
          'debit': cogs,
          'credit': 0,
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'note': 'COGS ${line.name} x${_qty(line.quantity)}',
        });
      }

      // 8. Insert updated ledger entries for invoice
      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': 'income:sales',
        'debit': 0,
        'credit': quote.taxable.paise,
        'ref_type': 'invoice',
        'ref_id': invoiceId,
        'note': 'Sales $number',
      });
      final taxAmount = quote.cgst.paise + quote.sgst.paise + quote.igst.paise;
      if (taxAmount > 0) {
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'gst:output',
          'debit': 0,
          'credit': taxAmount,
          'ref_type': 'invoice',
          'ref_id': invoiceId,
          'note': 'GST output $number',
        });
      }
      final total = quote.total.paise;
      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': 'customer:${customerId ?? 0}',
        'debit': total,
        'credit': 0,
        'ref_type': 'invoice',
        'ref_id': invoiceId,
        'note': '$customerName — $number',
      });

      // 9. Payment ledger and payments record
      if (amountPaid > 0) {
        final paymentId = await txn.insert('payments', {
          'business_id': businessId,
          'party_type': 'customer',
          'party_id': customerId,
          'party_name': customerName,
          'invoice_id': invoiceId,
          'invoice_number': number,
          'amount': amountPaid,
          'mode': paymentMode ?? 'Cash',
          'date': date,
          'type': 'in',
          'reference': 'initial_sale',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': paymentMode == 'Cash' ? 'cash' : 'bank',
          'debit': amountPaid,
          'credit': 0,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Payment in $number',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'customer:${customerId ?? 0}',
          'debit': 0,
          'credit': amountPaid,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Receipt $number',
        });
      }

      // 10. Update invoices table record
      final status = resolveInvoiceStatus(total: total, amountPaid: amountPaid);
      await txn.update('invoices', {
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'due_date': dueDate,
        'gst_type': gstType,
        'subtotal': quote.subtotal.paise,
        'discount': quote.itemDiscount.paise + quote.invoiceDiscount.paise,
        'discount_type': quote.lines.any((l) => l.discount.paise > 0) ? 'item' : null,
        'taxable': quote.taxable.paise,
        'cgst': quote.cgst.paise,
        'sgst': quote.sgst.paise,
        'igst': quote.igst.paise,
        'cess': quote.cess.paise,
        'round_off': quote.roundOff.paise,
        'total': total,
        'amount_paid': amountPaid,
        'payment_mode': paymentMode,
        'status': status,
        'notes': notes,
        'ship_to_name': shipToName,
        'ship_to_address': shipToAddress,
        'ship_to_state': shipToState,
        'ship_to_pincode': shipToPincode,
        'place_of_supply': placeOfSupply,
        'po_number': poNumber,
        'po_date': poDate,
        'vehicle_number': vehicleNumber,
        'eway_bill_number': ewayBillNumber,
        'lr_rr_number': lrRrNumber,
        'reverse_charge': reverseCharge ? 1 : 0,
        'custom_fields_json': customFieldsJson ?? '{}',
      }, where: 'id = ?', whereArgs: [invoiceId]);
    });

    await _audit(
      businessId,
      action: 'update',
      entity: 'invoice',
      entityId: invoiceId,
      before: beforeAudit,
      after: {
        'id': invoiceId,
        'number': number,
        'customer_name': customerName,
        'customer_id': customerId,
        'total': quote.total.paise,
        'subtotal': quote.subtotal.paise,
        'taxable': quote.taxable.paise,
        'status': resolveInvoiceStatus(total: quote.total.paise, amountPaid: amountPaid),
        'items_count': lines.length,
      },
    );
    final invoicePayload = {
      'id': invoiceId,
      'businessId': businessId.toString(),
      'number': number,
      'customerId': customerId?.toString(),
      'customerName': customerName,
      'date': date,
      'dueDate': dueDate,
      'gstType': gstType,
      'subtotal': quote.subtotal.paise,
      'discount': quote.itemDiscount.paise + quote.invoiceDiscount.paise,
      'taxable': quote.taxable.paise,
      'cgst': quote.cgst.paise,
      'sgst': quote.sgst.paise,
      'igst': quote.igst.paise,
      'roundOff': quote.roundOff.paise,
      'total': quote.total.paise,
      'amountPaid': amountPaid,
      'paymentMode': paymentMode,
      'status': resolveInvoiceStatus(total: quote.total.paise, amountPaid: amountPaid),
      'notes': notes,
      'items': lines.map((l) => {
        'productId': l.productId?.toString(),
        'name': l.name,
        'hsn': l.hsn,
        'quantity': l.quantity,
        'price': l.price,
        'discount': l.discount,
        'gstRate': l.gstRate,
        'taxable': l.taxable,
        'tax': l.tax,
      }).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _enqueueSync(businessId,
        entity: 'invoice', entityId: invoiceId, op: 'update', payload: jsonEncode(invoicePayload));
  }

  /// MCA Audit Trail & Statutory Compliance: Cancels an invoice.
  /// Reverts stock moves, restores inventory quantities, restores sold serial numbers,
  /// voids ledger entries and initial payments, updates invoice status to 'Cancelled',
  /// and writes an immutable entry into `audit_log` with before and after state.
  Future<void> cancelInvoice(
    int businessId,
    int invoiceId, {
    String? reason,
  }) async {
    final db = await _database;
    String invoiceNumber = '';
    Map<String, Object?>? beforeAudit;

    await db.transaction<void>((txn) async {
      // 1. Verify existence of invoice
      final invRows = await txn.query('invoices',
          where: 'business_id = ? AND id = ?',
          whereArgs: [businessId, invoiceId],
          limit: 1);
      if (invRows.isEmpty) {
        throw StateError('Invoice $invoiceId not found');
      }
      final inv = invRows.first;
      if ((inv['status'] as String?)?.toLowerCase() == 'cancelled') {
        throw StateError('Invoice $invoiceId is already cancelled');
      }
      invoiceNumber = inv['number'] as String? ?? 'INV-$invoiceId';

      // Capture before state for MCA audit trail
      final items = await txn.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      beforeAudit = {
        'id': invoiceId,
        'number': invoiceNumber,
        'customer_name': inv['customer_name'],
        'customer_id': inv['customer_id'],
        'total': inv['total'],
        'taxable': inv['taxable'],
        'status': inv['status'],
        'date': inv['date'],
        'items_count': items.length,
      };

      // 2. Revert inventory deductions from stock moves
      final oldMoves = await txn.query('stock_moves',
          where: 'ref_type = ? AND ref_id = ?', whereArgs: ['invoice', invoiceId]);
      for (final m in oldMoves) {
        final prodId = m['product_id'] as int?;
        final changeQty = (m['change_qty'] as num?)?.toDouble() ?? 0.0;
        if (prodId != null && changeQty < 0) {
          final qtyToRestore = -changeQty;
          final pRows = await txn.query('products',
              where: 'id = ?', whereArgs: [prodId], limit: 1);
          if (pRows.isNotEmpty) {
            final curStock = (pRows.first['stock'] as num?)?.toDouble() ?? 0.0;
            final newStock = curStock + qtyToRestore;
            await txn.update('products', {'stock': newStock},
                where: 'id = ?', whereArgs: [prodId]);
            await txn.insert('stock_moves', {
              'business_id': businessId,
              'product_id': prodId,
              'change_qty': qtyToRestore,
              'qty_after': newStock,
              'move_type': 'cancel',
              'ref_type': 'invoice_cancel',
              'ref_id': invoiceId,
              'date': isoDate(DateTime.now()),
            });
          }
        }
      }

      // 3. Revert serial numbers marked sold
      await txn.update('serial_numbers', {'status': 'Available', 'sale_ref': null},
          where: 'sale_ref = ?', whereArgs: [invoiceNumber]);

      // 4. Void/delete ledger entries for this invoice
      await txn.delete('ledger',
          where: 'business_id = ? AND ref_type = ? AND ref_id = ?',
          whereArgs: [businessId, 'invoice', invoiceId]);

      // 5. Void/delete linked payment records and payment ledger entries
      final linkedPayments = await txn.query('payments',
          where: 'invoice_id = ? AND type = ?', whereArgs: [invoiceId, 'in']);
      for (final p in linkedPayments) {
        final pId = p['id'] as int;
        await txn.delete('ledger',
            where: 'business_id = ? AND ref_type = ? AND ref_id = ?',
            whereArgs: [businessId, 'payment', pId]);
        await txn.delete('payments', where: 'id = ?', whereArgs: [pId]);
      }

      // 6. Update invoice status to 'Cancelled'
      final originalNotes = inv['notes'] as String? ?? '';
      final cancelNote = reason != null && reason.trim().isNotEmpty
          ? '[CANCELLED: ${reason.trim()}]'
          : '[CANCELLED]';
      final updatedNotes = originalNotes.isEmpty ? cancelNote : '$originalNotes\n$cancelNote';

      await txn.update('invoices', {
        'status': 'Cancelled',
        'notes': updatedNotes,
        'amount_paid': 0,
      }, where: 'id = ?', whereArgs: [invoiceId]);
    });

    // 7. Write immutable MCA Audit Trail entry
    await _audit(
      businessId,
      action: 'cancel',
      entity: 'invoice',
      entityId: invoiceId,
      before: beforeAudit,
      after: {
        'id': invoiceId,
        'number': invoiceNumber,
        'status': 'Cancelled',
        'reason': reason ?? 'Voided by user',
        'cancelled_at': timestampNow(),
      },
    );

    // 8. Enqueue sync
    await _enqueueSync(
      businessId,
      entity: 'invoice',
      entityId: invoiceId,
      op: 'update',
      payload: jsonEncode({
        'id': invoiceId,
        'businessId': businessId.toString(),
        'number': invoiceNumber,
        'status': 'Cancelled',
        'notes': reason ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<int> createPurchase({
    required int businessId,
    required int? supplierId,
    required String supplierName,
    required String date,
    required List<(int?, String, double, int, int)> items,
    required int amountPaid,
    String? paymentMode,
    String? notes,
    String? purchaseNumber,
  }) async {
    final db = await _database;
    final purchaseId = await db.transaction<int>((txn) async {
      final bizRows = await txn.query('businesses',
          columns: ['purchase_prefix', 'purchase_sequence'], where: 'id = ?', whereArgs: [businessId]);
      final pfx = bizRows.isNotEmpty ? (bizRows.first['purchase_prefix'] as String? ?? 'PUR') : 'PUR';
      final highest = await _resolveHighestPurchaseSequence(txn, businessId, pfx);
      final nextSeq = highest + 1;
      final number = (purchaseNumber != null && purchaseNumber.trim().isNotEmpty)
          ? purchaseNumber.trim()
          : InvoiceNumbering.format(pfx, nextSeq);

      final seq = InvoiceNumbering.extractSequence(number);
      if (seq != null) {
        final curSeq = bizRows.isNotEmpty ? (bizRows.first['purchase_sequence'] as int? ?? 0) : 0;
        if (seq > curSeq) {
          await txn.update('businesses', {'purchase_sequence': seq},
              where: 'id = ?', whereArgs: [businessId]);
        }
      }

      final purchaseId = await txn.insert('expenses', {
        'business_id': businessId,
        'category': 'Purchase',
        'amount': 0,
        'mode': paymentMode ?? 'Credit',
        'date': date,
        'description': notes == null || notes.isEmpty
            ? 'Purchase $number from $supplierName'
            : 'Purchase $number from $supplierName — $notes',
        'vendor': supplierName,
      });
      var total = 0;
      for (final item in items) {
        final (productId, name, qty, price, gstRate) = item;
        final lineAmount = (price * qty).round();
        final taxAmount = (price * qty * gstRate / 100).round();
        total += lineAmount + taxAmount;
        final product = productId == null
            ? null
            : (await txn.query('products',
                where: 'id = ?', whereArgs: [productId], limit: 1)).firstOrNull;
        if (product != null) {
          final stock = (product['stock'] as num?)?.toDouble() ?? 0;
          final costAvg = (product['cost_average'] as int? ?? 0);
          final newStock = stock + qty;
          final newAvg =
              newStock == 0 ? costAvg : (costAvg * stock + price * qty) / newStock;
          await txn.update('products', {
            'stock': newStock,
            'cost_average': newAvg.round(),
          }, where: 'id = ?', whereArgs: [productId]);
          await txn.insert('stock_moves', {
            'business_id': businessId,
            'product_id': productId,
            'change_qty': qty,
            'qty_after': stock + qty,
            'move_type': 'purchase',
            'ref_type': 'purchase',
            'ref_id': purchaseId,
            'date': date,
          });
        }
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'purchases',
          'debit': lineAmount + taxAmount,
          'credit': 0,
          'ref_type': 'purchase',
          'ref_id': purchaseId,
          'note': '$name x${_qty(qty)} from $supplierName',
        });
      }
      await txn.update('expenses', {'amount': total}, where: 'id = ?', whereArgs: [purchaseId]);
      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': 'supplier:${supplierId ?? 0}',
        'debit': 0,
        'credit': total,
        'ref_type': 'purchase',
        'ref_id': purchaseId,
        'note': '$supplierName — $number',
      });
      if (amountPaid > 0) {
        final paymentId = await txn.insert('payments', {
          'business_id': businessId,
          'party_type': 'supplier',
          'party_id': supplierId,
          'party_name': supplierName,
          'invoice_number': number,
          'amount': amountPaid,
          'mode': paymentMode ?? 'Cash',
          'date': date,
          'type': 'out',
          'reference': 'initial_purchase',
          'notes': 'Payment for $number',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': paymentMode == 'Cash' ? 'cash' : 'bank',
          'debit': 0,
          'credit': amountPaid,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Payment out $number',
        });
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': 'supplier:${supplierId ?? 0}',
          'debit': amountPaid,
          'credit': 0,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Paid $supplierName',
        });
      }
      return purchaseId;
    });
    await _audit(businessId, action: 'create', entity: 'purchase', entityId: purchaseId);
    await _enqueueSync(businessId, entity: 'purchase', entityId: purchaseId, op: 'create');
    return purchaseId;
  }

  Future<int> recordExpense({
    required int businessId,
    required String category,
    required int amount,
    required String mode,
    required String date,
    String? description,
    String? vendor,
  }) async {
    final db = await _database;
    final id = await db.insert('expenses', {
      'business_id': businessId,
      'category': category,
      'amount': amount,
      'mode': mode,
      'date': date,
      'description': description,
      'vendor': vendor,
    });
    await db.insert('ledger', {
      'business_id': businessId,
      'date': date,
      'account': 'expense:$category',
      'debit': amount,
      'credit': 0,
      'ref_type': 'expense',
      'ref_id': id,
      'note': description,
    });
    final isCash = mode == 'Cash';
    final paymentId = await db.insert('payments', {
      'business_id': businessId,
      'party_type': 'other',
      'party_id': 0,
      'amount': amount,
      'mode': mode,
      'date': date,
      'notes': description,
      'type': 'expense',
    });
    await db.insert('ledger', {
      'business_id': businessId,
      'date': date,
      'account': isCash ? 'cash' : 'bank',
      'debit': 0,
      'credit': amount,
      'ref_type': 'expense',
      'ref_id': paymentId,
      'note': description,
    });
    await _audit(businessId, action: 'create', entity: 'expense', entityId: id);
    final expMap = {
      'id': id,
      'businessId': businessId.toString(),
      'category': category,
      'amount': amount,
      'mode': mode,
      'date': date,
      'description': description,
      'vendor': vendor,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _enqueueSync(businessId, entity: 'expense', entityId: id, op: 'create', payload: jsonEncode(expMap));
    return id;
  }

  Future<int> recordPayment({
    required int businessId,
    required String partyType,
    required int amount,
    required String date,
    String? mode,
    List<int>? invoiceIds,
    int? partyId,
    String? partyName,
  }) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final isIn = partyType == 'customer';
      final paymentId = await txn.insert('payments', {
        'business_id': businessId,
        'party_type': partyType,
        'party_id': partyId ?? 0,
        'party_name': partyName,
        'amount': amount,
        'mode': mode ?? 'Cash',
        'date': date,
        'type': isIn ? 'in' : 'out',
        'reference': 'receipt',
      });

      final cashAccount = mode == 'Cash' ? 'cash' : 'bank';
      await txn.insert('ledger', {
        'business_id': businessId,
        'date': date,
        'account': cashAccount,
        'debit': isIn ? amount : 0,
        'credit': isIn ? 0 : amount,
        'ref_type': 'payment',
        'ref_id': paymentId,
        'note': '${isIn ? 'Payment in' : 'Payment out'} $date',
      });

      var remaining = amount;
      var allocated = 0;
      var resolvedPartyId = partyId;
      var resolvedPartyName = partyName;
      if (invoiceIds != null) {
        for (final invoiceId in invoiceIds) {
          if (remaining <= 0) break;
          final rows = await txn.query('invoices',
              where: 'id = ?', whereArgs: [invoiceId], limit: 1);
          if (rows.isEmpty) continue;
          final map = rows.first;
          final total = (map['total'] as int? ?? 0);
          final paid = (map['amount_paid'] as int? ?? 0);
          final outstanding = total - paid;
          final allocate = outstanding > remaining ? remaining : outstanding;
          if (allocate <= 0) continue;
          remaining -= allocate;
          allocated += allocate;
          resolvedPartyId ??= map['customer_id'] as int?;
          resolvedPartyName ??= map['customer_name'] as String?;
          await txn.update('invoices', {
            'amount_paid': paid + allocate,
            'status': resolveInvoiceStatus(total: total, amountPaid: paid + allocate),
          }, where: 'id = ?', whereArgs: [invoiceId]);
          await txn.update('payments', {
            'invoice_id': invoiceId,
            'invoice_number': map['number'],
            'party_id': resolvedPartyId,
            'party_name': resolvedPartyName,
          }, where: 'id = ?', whereArgs: [paymentId]);
        }
      }

      final partyAccount = isIn
          ? 'customer:${resolvedPartyId ?? 0}'
          : 'supplier:${resolvedPartyId ?? 0}';
      final advanceOnly = invoiceIds == null || allocated <= 0;
      if (isIn) {
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': partyAccount,
          'debit': 0,
          'credit': amount,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': '${advanceOnly ? 'Advance' : 'Receipt'} $date',
        });
      } else {
        await txn.insert('ledger', {
          'business_id': businessId,
          'date': date,
          'account': partyAccount,
          'debit': amount,
          'credit': 0,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': '${advanceOnly ? 'Advance' : 'Payment'} $date',
        });
      }
      return paymentId;
    });
    await _audit(businessId, action: 'create', entity: 'payment', entityId: id);
    final payMap = {
      'id': id,
      'businessId': businessId.toString(),
      'partyType': partyType,
      'partyId': partyId?.toString(),
      'partyName': partyName,
      'amount': amount,
      'mode': mode ?? 'Cash',
      'date': date,
      'type': partyType == 'customer' ? 'in' : 'out',
      'reference': 'receipt',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _enqueueSync(businessId, entity: 'payment', entityId: id, op: 'create', payload: jsonEncode(payMap));
    return id;
  }

  Future<List<Invoice>> invoices(int businessId) async {
    final db = await _database;
    final rows = await db.query('invoices',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(Invoice.fromMap).toList();
  }

  Future<Invoice?> invoice(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('invoices',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final invoice = Invoice.fromMap(rows.first);
    final items = await db.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [id], orderBy: 'id ASC');
    invoice.lines = items.map(InvoiceLine.fromMap).toList();
    return invoice;
  }

  Future<int> finalizeQuotation(Quotation quote) async {
    final db = await _database;
    final bizId = quote.businessId ?? session.businessId!;
    final id = await db.transaction<int>((txn) async {
      final qMap = <String, Object?>{
        'business_id': bizId,
        'number': quote.number,
        'customer_id': quote.customerId,
        'customer_name': quote.customerName,
        'date': quote.date,
        'expiry_date': quote.expiryDate,
        'gst_type': quote.gstType,
        'subtotal': quote.subtotal,
        'discount': quote.discount,
        'taxable': quote.taxable,
        'cgst': quote.cgst,
        'sgst': quote.sgst,
        'igst': quote.igst,
        'total': quote.total,
        'status': quote.status,
        'notes': quote.notes,
        'is_proforma': quote.isProforma ? 1 : 0,
      };

      int qId;
      try {
        qId = await txn.insert('quotations', qMap);
      } catch (e) {
        final fallbackMap = Map<String, Object?>.from(qMap)..remove('is_proforma');
        qId = await txn.insert('quotations', fallbackMap);
      }

      for (final line in quote.lines) {
        final itemMap = <String, Object?>{
          'quotation_id': qId,
          'product_id': line.productId,
          'name': line.name,
          'hsn': line.hsn,
          'gst_rate': line.gstRate,
          'quantity': line.quantity,
          'price': line.price,
          'discount': line.discount,
          'discount_percent': line.discountPercent,
          'taxable': line.taxable,
          'tax': line.tax,
          'unit': line.unit,
        };
        try {
          await txn.insert('quotation_items', itemMap);
        } catch (_) {
          final fallbackItemMap = Map<String, Object?>.from(itemMap)
            ..remove('discount_percent')
            ..remove('unit');
          await txn.insert('quotation_items', fallbackItemMap);
        }
      }
      final seq = InvoiceNumbering.extractSequence(quote.number);
      if (seq != null) {
        final currentSeqRows = await txn.query('businesses',
            columns: ['quotation_sequence'], where: 'id = ?', whereArgs: [bizId]);
        final curSeq = currentSeqRows.isNotEmpty ? (currentSeqRows.first['quotation_sequence'] as int? ?? 0) : 0;
        if (seq > curSeq) {
          await txn.update('businesses', {'quotation_sequence': seq},
              where: 'id = ?', whereArgs: [bizId]);
        }
      }
      return qId;
    });
    await _audit(bizId, action: 'create', entity: 'quotation', entityId: id);
    return id;
  }

  Future<List<Quotation>> quotations(int businessId) async {
    final db = await _database;
    final rows = await db.query('quotations',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(Quotation.fromMap).toList();
  }

  Future<Quotation?> quotation(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('quotations',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final quote = Quotation.fromMap(rows.first);
    final items = await db.query('quotation_items',
        where: 'quotation_id = ?', whereArgs: [id], orderBy: 'id ASC');
    quote.lines = items.map(InvoiceLine.fromMap).toList();
    return quote;
  }

  Future<List<Quotation>> quotationsForParty(int businessId, int customerId) async {
    final db = await _database;
    final rows = await db.query(
      'quotations',
      where: 'business_id = ? AND customer_id = ?',
      whereArgs: [businessId, customerId],
      orderBy: 'date DESC, id DESC',
    );
    final quotes = rows.map(Quotation.fromMap).toList();
    for (final q in quotes) {
      if (q.id != null) {
        final items = await db.query('quotation_items',
            where: 'quotation_id = ?', whereArgs: [q.id], orderBy: 'id ASC');
        q.lines = items.map(InvoiceLine.fromMap).toList();
      }
    }
    return quotes;
  }

  Future<void> deleteQuotation(int businessId, int quotationId) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('quotation_items', where: 'quotation_id = ?', whereArgs: [quotationId]);
      await txn.delete('quotations', where: 'business_id = ? AND id = ?', whereArgs: [businessId, quotationId]);
    });
    await _audit(businessId, action: 'delete', entity: 'quotation', entityId: quotationId);
  }

  Future<int> finalizeReturn(TransactionReturn ret) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final bizId = ret.businessId ?? session.businessId!;
      final retId = await txn.insert('returns', ret.toMap()..['business_id'] = bizId);

      for (final line in ret.lines) {
        await txn.insert('return_items', {
          'return_id': retId,
          'product_id': line.productId,
          'name': line.name,
          'hsn': line.hsn,
          'gst_rate': line.gstRate,
          'quantity': line.quantity,
          'price': line.price,
          'taxable': line.taxable,
          'tax': line.tax,
        });

        if (line.productId != null) {
          final product = await txn.query('products',
              where: 'id = ?', whereArgs: [line.productId], limit: 1);
          if (product.isNotEmpty) {
            final current = (product.first['stock'] as num?)?.toDouble() ?? 0;
            // Sales Return increases stock, Purchase Return decreases it
            final change = ret.partyType == 'customer' ? line.quantity : -line.quantity;
            final next = current + change;

            await txn.update('products', {'stock': next},
                where: 'id = ?', whereArgs: [line.productId]);

            await txn.insert('stock_moves', {
              'business_id': bizId,
              'product_id': line.productId,
              'change_qty': change,
              'qty_after': next,
              'move_type': ret.partyType == 'customer' ? 'sale_return' : 'purchase_return',
              'ref_type': 'return',
              'ref_id': retId,
              'date': ret.date,
            });
          }
        }
      }

      final partyAccount = ret.partyType == 'customer'
          ? 'customer:${ret.partyId ?? 0}'
          : 'supplier:${ret.partyId ?? 0}';

      if (ret.partyType == 'customer') {
        // Sales Return: Revenue down, Customer balance down
        await txn.insert('ledger', {
          'business_id': bizId,
          'date': ret.date,
          'account': 'income:sales_return',
          'debit': ret.taxable,
          'credit': 0,
          'ref_type': 'return',
          'ref_id': retId,
          'note': 'Sales Return ${ret.number}',
        });
        if (ret.tax > 0) {
          await txn.insert('ledger', {
            'business_id': bizId,
            'date': ret.date,
            'account': 'gst:output',
            'debit': ret.tax,
            'credit': 0,
            'ref_type': 'return',
            'ref_id': retId,
            'note': 'GST Reversal ${ret.number}',
          });
        }
        await txn.insert('ledger', {
          'business_id': bizId,
          'date': ret.date,
          'account': partyAccount,
          'debit': 0,
          'credit': ret.total,
          'ref_type': 'return',
          'ref_id': retId,
          'note': 'Credit Note ${ret.number}',
        });
      } else {
        // Purchase Return: Supplier balance down, Purchases down
        await txn.insert('ledger', {
          'business_id': bizId,
          'date': ret.date,
          'account': partyAccount,
          'debit': ret.total,
          'credit': 0,
          'ref_type': 'return',
          'ref_id': retId,
          'note': 'Debit Note ${ret.number}',
        });
        await txn.insert('ledger', {
          'business_id': bizId,
          'date': ret.date,
          'account': 'purchases',
          'debit': 0,
          'credit': ret.taxable + ret.tax,
          'ref_type': 'return',
          'ref_id': retId,
          'note': 'Purchase Return ${ret.number}',
        });
      }

      return retId;
    });
    await _audit(ret.businessId ?? session.businessId!,
        action: 'create', entity: 'return', entityId: id);
    return id;
  }

  Future<List<TransactionReturn>> returns(int businessId) async {
    final db = await _database;
    final rows = await db.query('returns',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(TransactionReturn.fromMap).toList();
  }

  Future<TransactionReturn?> returnDetails(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('returns',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final ret = TransactionReturn.fromMap(rows.first);
    final items = await db.query('return_items',
        where: 'return_id = ?', whereArgs: [id], orderBy: 'id ASC');
    ret.lines = items.map(InvoiceLine.fromMap).toList();
    return ret;
  }

  Future<void> markQuotationConverted(int businessId, int id, int invoiceId) async {
    final db = await _database;
    await db.update('quotations', {
      'status': 'Converted',
      'notes': 'Converted to Invoice ID: $invoiceId'
    }, where: 'business_id = ? AND id = ?', whereArgs: [businessId, id]);
  }

  Future<int> finalizeSalesOrder(SalesOrder order) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final orderId = await txn.insert('sales_orders', order.toMap()..['business_id'] = order.businessId ?? session.businessId);
      for (final line in order.lines) {
        await txn.insert('sales_order_items', {
          'order_id': orderId,
          'product_id': line.productId,
          'name': line.name,
          'quantity': line.quantity,
          'price': line.price,
        });
      }
      return orderId;
    });
    await _audit(order.businessId ?? session.businessId!, action: 'create', entity: 'sales_order', entityId: id);
    return id;
  }

  Future<int> finalizePurchaseOrder(PurchaseOrder order) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final orderId = await txn.insert('purchase_orders', order.toMap()..['business_id'] = order.businessId ?? session.businessId);
      for (final line in order.lines) {
        await txn.insert('purchase_order_items', {
          'order_id': orderId,
          'product_id': line.productId,
          'name': line.name,
          'quantity': line.quantity,
          'price': line.price,
        });
      }
      return orderId;
    });
    await _audit(order.businessId ?? session.businessId!, action: 'create', entity: 'purchase_order', entityId: id);
    return id;
  }

  Future<int> finalizeDeliveryChallan(DeliveryChallan challan) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final challanId = await txn.insert('delivery_challans', challan.toMap()..['business_id'] = challan.businessId ?? session.businessId);
      for (final line in challan.lines) {
        await txn.insert('delivery_challan_items', {
          'challan_id': challanId,
          'product_id': line.productId,
          'name': line.name,
          'quantity': line.quantity,
          'price': line.price,
          'unit': line.unit,
        });
      }
      return challanId;
    });
    await _audit(challan.businessId ?? session.businessId!, action: 'create', entity: 'delivery_challan', entityId: id);
    return id;
  }

  Future<int> upsertBankAccount(BankAccount account) async {
    final db = await _database;
    final bizId = session.businessId!;
    final map = account.toMap()..['business_id'] = bizId;
    if (account.id == null) {
      final id = await db.insert('bank_accounts', map);
      await _syncOpeningBalance(db, bizId, account: 'bank:$id', amount: account.openingBalance, name: account.bankName);
      return id;
    }
    await db.update('bank_accounts', map, where: 'id = ?', whereArgs: [account.id]);
    return account.id!;
  }

  Future<void> recordBankTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required String date,
    String? note,
  }) async {
    final db = await _database;
    final bizId = session.businessId!;
    await db.transaction((txn) async {
      await txn.insert('ledger', {
        'business_id': bizId,
        'date': date,
        'account': 'bank:$fromAccountId',
        'debit': 0,
        'credit': amount,
        'note': 'Transfer to Bank $toAccountId ${note ?? ''}',
      });
      await txn.insert('ledger', {
        'business_id': bizId,
        'date': date,
        'account': 'bank:$toAccountId',
        'debit': amount,
        'credit': 0,
        'note': 'Transfer from Bank $fromAccountId ${note ?? ''}',
      });
    });
  }

  Future<void> recordTransfer({
    required String fromAccount,
    required String toAccount,
    required int amount,
    required String date,
    String? note,
  }) async {
    final db = await _database;
    final bizId = session.businessId!;
    await db.transaction((txn) async {
      await txn.insert('ledger', {
        'business_id': bizId,
        'date': date,
        'account': fromAccount,
        'debit': 0,
        'credit': amount,
        'note': 'Transfer to $toAccount ${note ?? ''}'.trim(),
      });
      await txn.insert('ledger', {
        'business_id': bizId,
        'date': date,
        'account': toAccount,
        'debit': amount,
        'credit': 0,
        'note': 'Transfer from $fromAccount ${note ?? ''}'.trim(),
      });
    });
  }

  Future<List<BankAccount>> bankAccounts(int businessId) async {
    final db = await _database;
    final rows = await db.query('bank_accounts', where: 'business_id = ? AND inactive = 0', whereArgs: [businessId]);
    return rows.map(BankAccount.fromMap).toList();
  }

  Future<BankAccount?> getBankAccount(int id) async {
    final db = await _database;
    final rows = await db.query('bank_accounts', where: 'id = ? AND inactive = 0', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BankAccount.fromMap(rows.first);
  }

  Future<void> deleteBankAccount(int id) async {
    final db = await _database;
    await db.update('bank_accounts', {'inactive': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<CashBankSummary> getCashAndBankSummary(int businessId) async {
    final db = await _database;
    final cashRows = await db.rawQuery(
      "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM ledger WHERE business_id = ? AND account = 'cash'",
      [businessId],
    );
    final cashInHand = cashRows.isEmpty ? 0 : (cashRows.first['balance'] as num).toInt();

    final acctRows = await db.query('bank_accounts', where: 'business_id = ? AND inactive = 0', whereArgs: [businessId]);
    final accounts = acctRows.map(BankAccount.fromMap).toList();
    
    final List<BankAccountWithBalance> accountsWithBalance = [];
    int totalBank = 0;

    for (final acc in accounts) {
      final balRows = await db.rawQuery(
        "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM ledger WHERE business_id = ? AND account = ?",
        [businessId, 'bank:${acc.id}'],
      );
      var bal = balRows.isEmpty ? 0 : (balRows.first['balance'] as num).toInt();
      if (bal == 0 && acc.openingBalance != 0) {
        bal = acc.openingBalance;
      }
      accountsWithBalance.add(BankAccountWithBalance(account: acc, currentBalance: bal));
      totalBank += bal;
    }

    final genericBankRows = await db.rawQuery(
      "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM ledger WHERE business_id = ? AND account = 'bank'",
      [businessId],
    );
    final genericBank = genericBankRows.isEmpty ? 0 : (genericBankRows.first['balance'] as num).toInt();
    totalBank += genericBank;

    final pendingInwardRows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM cheques WHERE business_id = ? AND type = 'inward' AND status = 'Pending'",
      [businessId],
    );
    final pendingInward = pendingInwardRows.isEmpty ? 0 : (pendingInwardRows.first['total'] as num).toInt();

    final pendingOutwardRows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM cheques WHERE business_id = ? AND type = 'outward' AND status = 'Pending'",
      [businessId],
    );
    final pendingOutward = pendingOutwardRows.isEmpty ? 0 : (pendingOutwardRows.first['total'] as num).toInt();

    return CashBankSummary(
      totalLiquidAssets: cashInHand + totalBank,
      cashInHand: cashInHand,
      totalBankBalance: totalBank,
      pendingChequesInward: pendingInward,
      pendingChequesOutward: pendingOutward,
      accounts: accountsWithBalance,
    );
  }

  Future<List<Cheque>> cheques(int businessId, {String? type, String? status}) async {
    final db = await _database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];
    if (type != null && type.isNotEmpty && type != 'all') {
      where.add('type = ?');
      args.add(type);
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      where.add('status = ?');
      args.add(status);
    }
    final rows = await db.query(
      'cheques',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'id DESC',
    );
    return rows.map(Cheque.fromMap).toList();
  }

  Future<int> upsertCheque(Cheque cheque) async {
    final db = await _database;
    final bizId = session.businessId!;
    final map = cheque.toMap()..['business_id'] = bizId;
    if (cheque.id == null) {
      final id = await db.insert('cheques', map);
      if (cheque.status == 'Cleared') {
        await _recordChequeLedger(db, bizId, cheque, id, isClear: true);
      }
      await _audit(bizId, action: 'create', entity: 'cheque', entityId: id, after: {'number': cheque.chequeNumber, 'amount': cheque.amount});
      return id;
    }
    await db.update('cheques', map, where: 'id = ?', whereArgs: [cheque.id]);
    await _audit(bizId, action: 'update', entity: 'cheque', entityId: cheque.id!, after: {'status': cheque.status, 'amount': cheque.amount});
    return cheque.id!;
  }

  Future<void> updateChequeStatus(int chequeId, String newStatus, {String? bounceReason, String? clearingDate}) async {
    final db = await _database;
    final bizId = session.businessId!;
    final rows = await db.query('cheques', where: 'id = ?', whereArgs: [chequeId]);
    if (rows.isEmpty) return;
    final chq = Cheque.fromMap(rows.first);
    final oldStatus = chq.status;

    await db.transaction((txn) async {
      await txn.update(
        'cheques',
        {
          'status': newStatus,
          if (bounceReason != null) 'bounce_reason': bounceReason,
          if (clearingDate != null) 'clearing_date': clearingDate,
        },
        where: 'id = ?',
        whereArgs: [chequeId],
      );

      if (oldStatus == 'Pending' && newStatus == 'Cleared') {
        chq.clearingDate = clearingDate;
        await _recordChequeLedger(txn, bizId, chq, chequeId, isClear: true);
      } else if (oldStatus == 'Cleared' && newStatus == 'Bounced') {
        await _recordChequeLedger(txn, bizId, chq, chequeId, isClear: false, isBounce: true, reason: bounceReason);
      }
    });

    await _audit(bizId, action: 'update_status', entity: 'cheque', entityId: chequeId, after: {'status': newStatus, 'bounce_reason': bounceReason});
  }

  Future<void> _recordChequeLedger(
    DatabaseExecutor db,
    int bizId,
    Cheque cheque,
    int chequeId, {
    required bool isClear,
    bool isBounce = false,
    String? reason,
  }) async {
    final bankAccount = cheque.bankAccountId != null ? 'bank:${cheque.bankAccountId}' : 'bank';
    final partyAccount = cheque.partyType == 'supplier' ? 'supplier:${cheque.partyId ?? 0}' : 'customer:${cheque.partyId ?? 0}';
    final date = cheque.clearingDate ?? cheque.date;

    if (isClear) {
      if (cheque.type == 'inward') {
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': bankAccount,
          'debit': cheque.amount,
          'credit': 0,
          'ref_type': 'cheque_clear',
          'ref_id': chequeId,
          'note': 'Cheque ${cheque.chequeNumber} cleared from ${cheque.partyName ?? 'Party'}',
        });
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': partyAccount,
          'debit': 0,
          'credit': cheque.amount,
          'ref_type': 'cheque_clear',
          'ref_id': chequeId,
          'note': 'Cheque ${cheque.chequeNumber} received & cleared',
        });
      } else {
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': partyAccount,
          'debit': cheque.amount,
          'credit': 0,
          'ref_type': 'cheque_clear',
          'ref_id': chequeId,
          'note': 'Cheque ${cheque.chequeNumber} to ${cheque.partyName ?? 'Supplier'} cleared',
        });
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': bankAccount,
          'debit': 0,
          'credit': cheque.amount,
          'ref_type': 'cheque_clear',
          'ref_id': chequeId,
          'note': 'Cheque ${cheque.chequeNumber} cleared',
        });
      }
    } else if (isBounce) {
      if (cheque.type == 'inward') {
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': partyAccount,
          'debit': cheque.amount,
          'credit': 0,
          'ref_type': 'cheque_bounce',
          'ref_id': chequeId,
          'note': 'BOUNCE REVERSAL: Cheque ${cheque.chequeNumber} (${reason ?? 'Insufficient Funds'})',
        });
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': bankAccount,
          'debit': 0,
          'credit': cheque.amount,
          'ref_type': 'cheque_bounce',
          'ref_id': chequeId,
          'note': 'BOUNCE REVERSAL: Cheque ${cheque.chequeNumber}',
        });
      } else {
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': bankAccount,
          'debit': cheque.amount,
          'credit': 0,
          'ref_type': 'cheque_bounce',
          'ref_id': chequeId,
          'note': 'BOUNCE REVERSAL: Cheque ${cheque.chequeNumber}',
        });
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': partyAccount,
          'debit': 0,
          'credit': cheque.amount,
          'ref_type': 'cheque_bounce',
          'ref_id': chequeId,
          'note': 'BOUNCE REVERSAL: Cheque ${cheque.chequeNumber} (${reason ?? 'Bounce'})',
        });
      }
    }
  }

  Future<SalesOrder?> salesOrder(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('sales_orders',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final order = SalesOrder.fromMap(rows.first);
    final items = await db.query('sales_order_items',
        where: 'order_id = ?', whereArgs: [id], orderBy: 'id ASC');
    order.lines = items.map(InvoiceLine.fromMap).toList();
    return order;
  }

  Future<PurchaseOrder?> purchaseOrder(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('purchase_orders',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final po = PurchaseOrder.fromMap(rows.first);
    final items = await db.query('purchase_order_items',
        where: 'order_id = ?', whereArgs: [id], orderBy: 'id ASC');
    po.lines = items.map(InvoiceLine.fromMap).toList();
    return po;
  }

  Future<List<SalesOrder>> salesOrders(int businessId) async {
    final db = await _database;
    final rows = await db.query('sales_orders',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    final orders = rows.map(SalesOrder.fromMap).toList();
    for (final o in orders) {
      if (o.id != null) {
        final items = await db.query('sales_order_items',
            where: 'order_id = ?', whereArgs: [o.id], orderBy: 'id ASC');
        o.lines = items.map(InvoiceLine.fromMap).toList();
      }
    }
    return orders;
  }

  Future<void> deleteSalesOrder(int businessId, int orderId) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('sales_order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await txn.delete('sales_orders', where: 'business_id = ? AND id = ?', whereArgs: [businessId, orderId]);
    });
    await _audit(businessId, action: 'delete', entity: 'sales_order', entityId: orderId);
  }

  Future<List<PurchaseOrder>> purchaseOrders(int businessId) async {
    final db = await _database;
    final rows = await db.query('purchase_orders',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    final orders = rows.map(PurchaseOrder.fromMap).toList();
    for (final o in orders) {
      if (o.id != null) {
        final items = await db.query('purchase_order_items',
            where: 'order_id = ?', whereArgs: [o.id], orderBy: 'id ASC');
        o.lines = items.map(InvoiceLine.fromMap).toList();
      }
    }
    return orders;
  }

  Future<void> deletePurchaseOrder(int businessId, int orderId) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('purchase_order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await txn.delete('purchase_orders', where: 'business_id = ? AND id = ?', whereArgs: [businessId, orderId]);
    });
    await _audit(businessId, action: 'delete', entity: 'purchase_order', entityId: orderId);
  }

  Future<DeliveryChallan?> deliveryChallan(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('delivery_challans',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final dc = DeliveryChallan.fromMap(rows.first);
    final items = await db.query('delivery_challan_items',
        where: 'challan_id = ?', whereArgs: [id], orderBy: 'id ASC');
    dc.lines = items.map((m) => InvoiceLine(
      productId: m['product_id'] as int?,
      name: m['name'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
      price: (m['price'] as num?)?.toInt() ?? 0,
      unit: m['unit'] as String?,
    )).toList();
    return dc;
  }

  Future<List<DeliveryChallan>> deliveryChallansForInvoice(int businessId, int invoiceId) async {
    final db = await _database;
    final rows = await db.query('delivery_challans',
        where: 'business_id = ? AND invoice_id = ?',
        whereArgs: [businessId, invoiceId],
        orderBy: 'id DESC');
    final list = <DeliveryChallan>[];
    for (final row in rows) {
      final dc = DeliveryChallan.fromMap(row);
      final items = await db.query('delivery_challan_items',
          where: 'challan_id = ?', whereArgs: [dc.id], orderBy: 'id ASC');
      dc.lines = items.map((m) => InvoiceLine(
        productId: m['product_id'] as int?,
        name: m['name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        price: (m['price'] as num?)?.toInt() ?? 0,
        unit: m['unit'] as String?,
      )).toList();
      list.add(dc);
    }
    return list;
  }

  Future<List<DeliveryChallan>> allDeliveryChallans(int businessId) async {
    final db = await _database;
    final rows = await db.query('delivery_challans',
        where: 'business_id = ?', whereArgs: [businessId], orderBy: 'date DESC, id DESC');
    final list = <DeliveryChallan>[];
    for (final row in rows) {
      final dc = DeliveryChallan.fromMap(row);
      final items = await db.query('delivery_challan_items',
          where: 'challan_id = ?', whereArgs: [dc.id], orderBy: 'id ASC');
      dc.lines = items.map((m) => InvoiceLine(
        productId: m['product_id'] as int?,
        name: m['name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        price: (m['price'] as num?)?.toInt() ?? 0,
        unit: m['unit'] as String?,
      )).toList();
      list.add(dc);
    }
    return list;
  }

  Future<void> deleteDeliveryChallan(int businessId, int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('delivery_challan_items', where: 'challan_id = ?', whereArgs: [id]);
      await txn.delete('delivery_challans', where: 'business_id = ? AND id = ?', whereArgs: [businessId, id]);
    });
    await _audit(businessId, action: 'delete', entity: 'delivery_challan', entityId: id);
  }

  Future<List<SalesOrder>> allSalesOrders(int businessId) async {
    final db = await _database;
    final rows = await db.query('sales_orders', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'date DESC, id DESC');
    return rows.map(SalesOrder.fromMap).toList();
  }

  Future<List<PurchaseOrder>> allPurchaseOrders(int businessId) async {
    final db = await _database;
    final rows = await db.query('purchase_orders', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'date DESC, id DESC');
    return rows.map(PurchaseOrder.fromMap).toList();
  }

  Future<int> convertQuotationToInvoice(int quotationId, {String? invoiceNumber}) async {
    final bizId = session.businessId!;
    final q = await quotation(bizId, quotationId);
    if (q == null) throw StateError('Quotation not found');
    final biz = await getBusiness(bizId);
    if (biz == null) throw StateError('Business not found');

    Customer? cust;
    if (q.customerId != null) {
      cust = await customer(bizId, q.customerId!);
    }

    final number = invoiceNumber ?? await nextInvoiceNumber(bizId, biz.invoicePrefix);

    final lineInputs = q.lines.map((l) => LineCalcInput(
      quantity: l.quantity,
      price: l.price,
      discountPercent: l.discountPercent,
      gstRate: l.gstRate,
      taxIncluded: false,
    )).toList();

    final quoteResult = BillingEngine.calculateQuote(
      lines: lineInputs,
      invoiceDiscount: const InvoiceDiscountInput.none(),
      gstEnabled: biz.taxRegistered,
      businessTaxRegistered: biz.taxRegistered,
      businessState: biz.state,
      customerState: cust?.state,
    );

    final invoiceId = await finalizeSale(
      businessId: bizId,
      number: number,
      customerId: q.customerId,
      customerName: q.customerName ?? 'Walk-in',
      date: todayIso(),
      dueDate: cust != null && cust.paymentTermsDays > 0
          ? isoDate(DateTime.now().add(Duration(days: cust.paymentTermsDays)))
          : null,
      gstType: quoteResult.intraState ? 'intra' : 'inter',
      quote: quoteResult,
      lines: q.lines,
      amountPaid: 0,
      notes: 'Converted from Quotation ${q.number}',
    );

    await markQuotationConverted(bizId, quotationId, invoiceId);
    return invoiceId;
  }

  Future<int> convertSalesOrderToInvoice(int orderId, {String? invoiceNumber}) async {
    final db = await _database;
    final bizId = session.businessId!;
    final so = await salesOrder(bizId, orderId);
    if (so == null) throw StateError('Sales order not found');
    final biz = await getBusiness(bizId);
    if (biz == null) throw StateError('Business not found');

    Customer? cust;
    if (so.customerId != null) {
      cust = await customer(bizId, so.customerId!);
    }

    final number = invoiceNumber ?? await nextInvoiceNumber(bizId, biz.invoicePrefix);

    final lineInputs = <LineCalcInput>[];
    final invoiceLines = <InvoiceLine>[];

    for (final l in so.lines) {
      int gstRate = 0;
      if (l.productId != null) {
        final pRows = await db.query('products', where: 'id = ?', whereArgs: [l.productId], limit: 1);
        if (pRows.isNotEmpty) {
          gstRate = (pRows.first['gst_rate'] as num?)?.toInt() ?? 0;
        }
      }
      lineInputs.add(LineCalcInput(
        quantity: l.quantity,
        price: l.price,
        gstRate: gstRate,
      ));
      invoiceLines.add(InvoiceLine(
        productId: l.productId,
        name: l.name,
        quantity: l.quantity,
        price: l.price,
        gstRate: gstRate,
        taxable: (l.price * l.quantity).round(),
      ));
    }

    final quoteResult = BillingEngine.calculateQuote(
      lines: lineInputs,
      invoiceDiscount: const InvoiceDiscountInput.none(),
      gstEnabled: biz.taxRegistered,
      businessTaxRegistered: biz.taxRegistered,
      businessState: biz.state,
      customerState: cust?.state,
    );

    final invoiceId = await finalizeSale(
      businessId: bizId,
      number: number,
      customerId: so.customerId,
      customerName: so.customerName ?? 'Walk-in',
      date: todayIso(),
      dueDate: so.dueDate ?? (cust != null && cust.paymentTermsDays > 0
          ? isoDate(DateTime.now().add(Duration(days: cust.paymentTermsDays)))
          : null),
      gstType: quoteResult.intraState ? 'intra' : 'inter',
      quote: quoteResult,
      lines: invoiceLines,
      amountPaid: 0,
      notes: 'Converted from Sales Order ${so.number}',
    );

    await db.update('sales_orders', {
      'status': 'Converted',
      'notes': 'Converted to Invoice ID: $invoiceId'
    }, where: 'business_id = ? AND id = ?', whereArgs: [bizId, orderId]);

    return invoiceId;
  }

  Future<int> convertDeliveryChallanToInvoice(int challanId, {String? invoiceNumber}) async {
    final db = await _database;
    final bizId = session.businessId!;
    final dc = await deliveryChallan(bizId, challanId);
    if (dc == null) throw StateError('Delivery challan not found');
    final biz = await getBusiness(bizId);
    if (biz == null) throw StateError('Business not found');

    Customer? cust;
    if (dc.customerId != null) {
      cust = await customer(bizId, dc.customerId!);
    }

    final number = invoiceNumber ?? await nextInvoiceNumber(bizId, biz.invoicePrefix);

    final lineInputs = <LineCalcInput>[];
    final invoiceLines = <InvoiceLine>[];

    for (final l in dc.lines) {
      int price = l.price;
      int gstRate = 0;
      if (l.productId != null) {
        final pRows = await db.query('products', where: 'id = ?', whereArgs: [l.productId], limit: 1);
        if (pRows.isNotEmpty) {
          if (price <= 0) {
            price = (pRows.first['sale_price'] as num?)?.toInt() ?? 0;
          }
          gstRate = (pRows.first['gst_rate'] as num?)?.toInt() ?? 0;
        }
      }
      lineInputs.add(LineCalcInput(
        quantity: l.quantity,
        price: price,
        gstRate: gstRate,
      ));
      invoiceLines.add(InvoiceLine(
        productId: l.productId,
        name: l.name,
        quantity: l.quantity,
        price: price,
        gstRate: gstRate,
        taxable: (price * l.quantity).round(),
      ));
    }

    final quoteResult = BillingEngine.calculateQuote(
      lines: lineInputs,
      invoiceDiscount: const InvoiceDiscountInput.none(),
      gstEnabled: biz.taxRegistered,
      businessTaxRegistered: biz.taxRegistered,
      businessState: biz.state,
      customerState: cust?.state,
    );

    final invoiceId = await finalizeSale(
      businessId: bizId,
      number: number,
      customerId: dc.customerId,
      customerName: dc.customerName ?? 'Walk-in',
      date: todayIso(),
      dueDate: cust != null && cust.paymentTermsDays > 0
          ? isoDate(DateTime.now().add(Duration(days: cust.paymentTermsDays)))
          : null,
      gstType: quoteResult.intraState ? 'intra' : 'inter',
      quote: quoteResult,
      lines: invoiceLines,
      amountPaid: 0,
      notes: 'Converted from Delivery Challan ${dc.number}',
    );

    await db.update('delivery_challans', {
      'status': 'Converted',
    }, where: 'business_id = ? AND id = ?', whereArgs: [bizId, challanId]);

    return invoiceId;
  }

  Future<int> convertPurchaseOrderToPurchase(int orderId) async {
    final db = await _database;
    final bizId = session.businessId!;
    final po = await purchaseOrder(bizId, orderId);
    if (po == null) throw StateError('Purchase order not found');

    final items = <(int?, String, double, int, int)>[];
    for (final l in po.lines) {
      int gstRate = 0;
      if (l.productId != null) {
        final pRows = await db.query('products', where: 'id = ?', whereArgs: [l.productId], limit: 1);
        if (pRows.isNotEmpty) {
          gstRate = (pRows.first['gst_rate'] as num?)?.toInt() ?? 0;
        }
      }
      items.add((l.productId, l.name, l.quantity, l.price, gstRate));
    }

    final purchaseId = await createPurchase(
      businessId: bizId,
      supplierId: po.supplierId,
      supplierName: po.supplierName ?? 'Direct vendor',
      date: todayIso(),
      items: items,
      amountPaid: 0,
      notes: 'Converted from Purchase Order ${po.number}',
    );

    await db.update('purchase_orders', {
      'status': 'Converted',
      'notes': 'Converted to Purchase ID: $purchaseId'
    }, where: 'business_id = ? AND id = ?', whereArgs: [bizId, orderId]);

    return purchaseId;
  }

  Future<void> recordStockTransfer({
    required int productId,
    required double quantity,
    required String fromLocation,
    required String toLocation,
    required String date,
  }) async {
    final db = await _database;
    final bizId = session.businessId!;
    await db.transaction((txn) async {
      await txn.insert('stock_moves', {
        'business_id': bizId,
        'product_id': productId,
        'change_qty': -quantity,
        'move_type': 'transfer_out',
        'note': 'Transfer from $fromLocation to $toLocation',
        'date': date,
      });
      await txn.insert('stock_moves', {
        'business_id': bizId,
        'product_id': productId,
        'change_qty': quantity,
        'move_type': 'transfer_in',
        'note': 'Transfer from $fromLocation to $toLocation',
        'date': date,
      });
    });
  }

  Future<void> upsertUnitConversion(UnitConversion conv) async {
    final db = await _database;
    final bizId = session.businessId!;
    final map = conv.toMap()..['business_id'] = bizId;
    if (conv.id == null) {
      await db.insert('unit_conversions', map);
    } else {
      await db.update('unit_conversions', map, where: 'id = ?', whereArgs: [conv.id]);
    }
  }

  Future<void> upsertBatch(Batch batch) async {
    final db = await _database;
    final bizId = session.businessId!;
    final map = batch.toMap()..['business_id'] = bizId;
    if (batch.id == null) {
      await db.insert('batches', map);
    } else {
      await db.update('batches', map, where: 'id = ?', whereArgs: [batch.id]);
    }
  }

  Future<void> upsertSerialNumber(SerialNumber sn) async {
    final db = await _database;
    final bizId = session.businessId!;
    final map = sn.toMap()..['business_id'] = bizId;
    if (sn.id == null) {
      // Check for duplicate serial
      final check = await db.query('serial_numbers', where: 'business_id = ? AND serial_number = ?', whereArgs: [bizId, sn.serialNumber], limit: 1);
      if (check.isNotEmpty) throw StateError('Serial Number already exists');
      await db.insert('serial_numbers', map);
    } else {
      await db.update('serial_numbers', map, where: 'id = ?', whereArgs: [sn.id]);
    }
  }

  Future<List<SearchResult>> globalSearch(int businessId, String query) async {
    if (query.trim().isEmpty) return [];
    final db = await _database;
    final List<SearchResult> results = [];
    final q = '%$query%';

    final custs = await db.query('customers',
        where: 'business_id = ? AND (name LIKE ? OR phone LIKE ?)',
        whereArgs: [businessId, q, q], limit: 5);
    results.addAll(custs.map((r) => SearchResult(
        type: 'customer', id: r['id'] as int, title: r['name'] as String, subtitle: r['phone'] as String?)));

    final prods = await db.query('products',
        where: 'business_id = ? AND (name LIKE ? OR sku LIKE ? OR barcode LIKE ?)',
        whereArgs: [businessId, q, q, q], limit: 5);
    results.addAll(prods.map((r) => SearchResult(
        type: 'product', id: r['id'] as int, title: r['name'] as String, subtitle: 'Stock: ${r['stock']}')));

    final invs = await db.query('invoices',
        where: 'business_id = ? AND (number LIKE ? OR customer_name LIKE ?)',
        whereArgs: [businessId, q, q], limit: 5);
    results.addAll(invs.map((r) => SearchResult(
        type: 'invoice', id: r['id'] as int, title: r['number'] as String, subtitle: r['customer_name'] as String?, amount: r['total'] as int?)));

    return results;
  }

  Future<Map<String, int>> balanceSheet(int businessId) async {
    final db = await _database;
    final Map<String, int> sheet = {};

    // Assets
    final cash = await db.rawQuery("SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account = 'cash'", [businessId]);
    final bank = await db.rawQuery("SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account = 'bank'", [businessId]);
    final receivables = await db.rawQuery("SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account LIKE 'customer:%'", [businessId]);
    final stock = await db.rawQuery("SELECT COALESCE(SUM(stock * cost_average), 0) AS s FROM products WHERE business_id = ?", [businessId]);

    sheet['cash'] = (cash.first['s'] as num).toInt();
    sheet['bank'] = (bank.first['s'] as num).toInt();
    sheet['receivables'] = (receivables.first['s'] as num).toInt();
    sheet['stock'] = (stock.first['s'] as num).toInt();
    sheet['totalAssets'] = sheet['cash']! + sheet['bank']! + sheet['receivables']! + sheet['stock']!;

    // Liabilities
    final payables = await db.rawQuery("SELECT COALESCE(SUM(credit - debit), 0) AS s FROM ledger WHERE business_id = ? AND account LIKE 'supplier:%'", [businessId]);
    sheet['payables'] = (payables.first['s'] as num).toInt();
    sheet['totalLiabilities'] = sheet['payables']!;

    // Equity (Net Worth)
    sheet['equity'] = sheet['totalAssets']! - sheet['totalLiabilities']!;

    return sheet;
  }

  Future<Map<String, int>> profitAndLossReport(int businessId, String fromDate, String toDate) async {
    final db = await _database;
    Future<int> sumLedger(String account, {bool isDebit = true}) async {
      final col = isDebit ? 'debit - credit' : 'credit - debit';
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($col), 0) AS s FROM ledger WHERE business_id = ? AND account = ? AND date >= ? AND date <= ?',
          [businessId, account, fromDate, toDate]);
      return (rows.first['s'] as num).toInt();
    }

    final sales = await db.rawQuery(
        "SELECT COALESCE(SUM(credit - debit), 0) AS s FROM ledger WHERE business_id = ? AND account = 'income:sales' AND date >= ? AND date <= ?",
        [businessId, fromDate, toDate]);
    final salesReturn = await sumLedger('income:sales_return', isDebit: true);
    final cogs = await sumLedger('cogs', isDebit: true);

    final rows = await db.rawQuery(
        "SELECT category, SUM(amount) AS s FROM expenses WHERE business_id = ? AND date >= ? AND date <= ? AND category != 'Purchase' GROUP BY category",
        [businessId, fromDate, toDate]);
    final Map<String, int> expenseMap = {};
    int totalExpenses = 0;
    for (final r in rows) {
      final cat = r['category'] as String;
      final amt = (r['s'] as num).toInt();
      expenseMap[cat] = amt;
      totalExpenses += amt;
    }

    final netSales = (sales.first['s'] as num).toInt() - salesReturn;
    final grossProfit = netSales - cogs;
    final netProfit = grossProfit - totalExpenses;

    return {
      'grossSales': (sales.first['s'] as num).toInt(),
      'salesReturn': salesReturn,
      'netSales': netSales,
      'cogs': cogs,
      'grossProfit': grossProfit,
      ...expenseMap,
      'totalExpenses': totalExpenses,
      'netProfit': netProfit,
    };
  }

  Future<List<Payment>> payments(int businessId) async {
    final db = await _database;
    final rows = await db.query('payments',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<Expense>> expenses(int businessId) async {
    final db = await _database;
    final rows = await db.query('expenses',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC');
    return rows.map(Expense.fromMap).toList();
  }

  Future<int> partyBalance(int businessId, String partyType, int partyId) async {
    final db = await _database;
    final suffix = partyType == 'customer' ? 'customer:$partyId' : 'supplier:$partyId';
    if (partyType == 'supplier') {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM(credit - debit), 0) AS s '
          'FROM ledger WHERE business_id = ? AND account = ?',
          [businessId, suffix]);
      return rows.isEmpty ? 0 : (rows.first['s'] as int);
    }
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS s '
        'FROM ledger WHERE business_id = ? AND account = ?',
        [businessId, suffix]);
    return rows.isEmpty ? 0 : (rows.first['s'] as int);
  }

  Future<int> customerBalance(int businessId, int customerId) =>
      partyBalance(businessId, 'customer', customerId);

  Future<int> supplierBalance(int businessId, int supplierId) =>
      partyBalance(businessId, 'supplier', supplierId);

  Future<List<LedgerEntry>> partyLedger(int businessId, String partyType, int partyId) async {
    final db = await _database;
    final suffix = partyType == 'customer' ? 'customer:$partyId' : 'supplier:$partyId';
    final rows = await db.query('ledger',
        where: 'business_id = ? AND account = ?', whereArgs: [businessId, suffix],
        orderBy: 'date ASC, id ASC');
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<List<LedgerEntry>> accountLedger(
    int businessId,
    String account, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];

    if (account == 'bank') {
      where.add("(account = 'bank' OR account LIKE 'bank:%')");
    } else {
      where.add('account = ?');
      args.add(account);
    }

    if (from != null) {
      where.add('date >= ?');
      args.add(isoDate(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(isoDate(to));
    }

    final rows = await db.query(
      'ledger',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<List<StockMove>> stockMoves(int businessId, int productId) async {
    final db = await _database;
    final rows = await db.query('stock_moves',
        where: 'business_id = ? AND product_id = ?', whereArgs: [businessId, productId],
        orderBy: 'date ASC, id ASC');
    return rows.map(StockMove.fromMap).toList();
  }

  Future<List<AuditEntry>> auditLog(
    int businessId, {
    String? entity,
    int? entityId,
    String? action,
    String? startDate,
    String? endDate,
    int limit = 500,
  }) async {
    final db = await _database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];

    if (entity != null && entity.trim().isNotEmpty && entity != 'all') {
      where.add('LOWER(entity) = ?');
      args.add(entity.trim().toLowerCase());
    }
    if (entityId != null) {
      where.add('entity_id = ?');
      args.add(entityId);
    }
    if (action != null && action.trim().isNotEmpty && action != 'all') {
      where.add('LOWER(action) = ?');
      args.add(action.trim().toLowerCase());
    }
    if (startDate != null && startDate.isNotEmpty) {
      where.add('timestamp >= ?');
      args.add(startDate);
    }
    if (endDate != null && endDate.isNotEmpty) {
      where.add('timestamp <= ?');
      args.add(endDate);
    }

    final rows = await db.query(
      'audit_log',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<int> pendingSyncCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sync_queue WHERE status != ?', ['synced']);
    return rows.isEmpty ? 0 : rows.first['c'] as int;
  }

  Future<List<SyncRecord>> syncQueue() async {
    final db = await _database;
    final rows = await db.query('sync_queue',
        orderBy: 'id ASC', where: 'status != ?', whereArgs: ['synced']);
    return rows.map(SyncRecord.fromMap).toList();
  }

  Future<void> markSyncSuccess(int id) async {
    final db = await _database;
    final attempts = await attemptsFor(id);
    await db.update('sync_queue', {
      'status': 'synced',
      'attempts': attempts + 1,
      'synced_at': timestampNow(),
      'last_error': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> attemptsFor(int id) async {
    final db = await _database;
    final rows = await db.query('sync_queue',
        columns: ['attempts'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['attempts'] as int? ?? 0);
  }

  Future<void> markSyncFailed(int id, String error) async {
    final db = await _database;
    final attempts = await attemptsFor(id);
    await db.update('sync_queue', {
      'status': 'failed',
      'attempts': attempts + 1,
      'last_error': error,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> resolveSyncPayload(String entity, int entityId) async {
    final db = await _database;
    switch (entity.toLowerCase()) {
      case 'invoice':
      case 'invoices':
        final rows = await db.query('invoices', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        final inv = Map<String, dynamic>.from(rows.first);
        final itemRows = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [entityId]);
        inv['items'] = itemRows.map((it) => Map<String, dynamic>.from(it)).toList();
        return jsonEncode(inv);

      case 'payment':
      case 'payments':
        final rows = await db.query('payments', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'expense':
      case 'expenses':
        final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'product':
      case 'products':
        final rows = await db.query('products', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'customer':
      case 'customers':
        final rows = await db.query('customers', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'supplier':
      case 'suppliers':
        final rows = await db.query('suppliers', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'stock_move':
      case 'stock_moves':
        final rows = await db.query('stock_moves', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'cheque':
      case 'cheques':
        final rows = await db.query('cheques', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'purchase':
      case 'purchases':
        final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      case 'staff':
      case 'staff_members':
        final rows = await db.query('staff_members', where: 'id = ?', whereArgs: [entityId], limit: 1);
        if (rows.isEmpty) return null;
        return jsonEncode(rows.first);

      default:
        return null;
    }
  }

  Future<void> reconcileRemoteChange(Map<String, dynamic> change) async {
    final entity = (change['entity'] as String? ?? '').toLowerCase();
    final payloadStr = change['payload'] as String?;
    if (payloadStr == null || payloadStr.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(payloadStr) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final db = await _database;
    final bizId = session.businessId;
    if (bizId == null) return;

    switch (entity) {
      case 'customer':
      case 'customers':
        final name = data['name'] as String? ?? '';
        if (name.isEmpty) return;
        final phone = data['phone'] as String?;
        final existing = await db.query(
          'customers',
          where: 'business_id = ? AND (phone = ? OR name = ?)',
          whereArgs: [bizId, phone ?? '', name],
          limit: 1,
        );
        final map = {
          'business_id': bizId,
          'name': name,
          'phone': phone,
          'email': data['email'] as String?,
          'gstin': data['gstin'] as String?,
          'billing_address': data['billingAddress'] ?? data['billing_address'],
          'city': data['city'] as String?,
          'state': data['state'] as String?,
          'opening_balance': _safeInt(data['openingBalance'] ?? data['opening_balance']) ?? 0,
        };
        if (existing.isNotEmpty) {
          await db.update('customers', map,
              where: 'id = ?', whereArgs: [existing.first['id']]);
        } else {
          await db.insert('customers', map);
        }
        break;

      case 'product':
      case 'products':
        final name = data['name'] as String? ?? '';
        if (name.isEmpty) return;
        final sku = data['sku'] as String?;
        final barcode = data['barcode'] as String?;
        final existing = await db.query(
          'products',
          where:
              'business_id = ? AND ((sku IS NOT NULL AND sku = ?) OR (barcode IS NOT NULL AND barcode = ?) OR name = ?)',
          whereArgs: [bizId, sku ?? '', barcode ?? '', name],
          limit: 1,
        );
        final remoteStock = _safeDouble(data['stock'])?.round() ?? 0;
        final map = {
          'business_id': bizId,
          'name': name,
          'sku': sku,
          'barcode': barcode,
          'category': data['category'] as String?,
          'unit': data['unit'] as String? ?? 'pc',
          'sale_price': _safeInt(data['salePrice'] ?? data['sale_price']) ?? 0,
          'purchase_price': _safeInt(data['purchasePrice'] ?? data['purchase_price']) ?? 0,
          'stock': remoteStock,
          'gst_rate': _safeInt(data['gstRate'] ?? data['gst_rate']) ?? 0,
        };
        if (existing.isNotEmpty) {
          final currentStock = (existing.first['stock'] as num?)?.toInt() ?? 0;
          final delta = remoteStock - currentStock;
          if (delta != 0) {
            await db.insert('stock_moves', {
              'business_id': bizId,
              'product_id': existing.first['id'],
              'change_qty': delta.toDouble(),
              'qty_after': remoteStock.toDouble(),
              'move_type': 'cloud_delta',
              'ref_type': 'sync',
              'date': todayIso(),
            });
          }
          await db.update('products', map,
              where: 'id = ?', whereArgs: [existing.first['id']]);
        } else {
          final prodId = await db.insert('products', map);
          if (remoteStock != 0) {
            await db.insert('stock_moves', {
              'business_id': bizId,
              'product_id': prodId,
              'change_qty': remoteStock.toDouble(),
              'qty_after': remoteStock.toDouble(),
              'move_type': 'opening',
              'ref_type': 'sync',
              'date': todayIso(),
            });
          }
        }
        break;

      case 'stock_move':
      case 'stock_moves':
        final prodId = _safeInt(data['product_id'] ?? data['productId']);
        final changeQty = _safeDouble(data['change_qty'] ?? data['changeQty']) ?? 0.0;
        if (prodId != null) {
          final prodRows = await db.query('products', where: 'id = ? AND business_id = ?', whereArgs: [prodId, bizId], limit: 1);
          if (prodRows.isNotEmpty) {
            final current = (prodRows.first['stock'] as num?)?.toDouble() ?? 0;
            final updated = current + changeQty;
            await db.update('products', {'stock': updated.round()}, where: 'id = ?', whereArgs: [prodId]);
            await db.insert('stock_moves', {
              'business_id': bizId,
              'product_id': prodId,
              'change_qty': changeQty,
              'qty_after': updated,
              'move_type': data['move_type'] ?? data['moveType'] ?? 'cloud_delta',
              'ref_type': data['ref_type'] ?? data['refType'] ?? 'sync',
              'ref_id': data['ref_id'] ?? data['refId'],
              'date': data['date'] ?? todayIso(),
            });
          }
        }
        break;

      case 'invoice':
      case 'invoices':
        final number = data['number'] as String? ?? '';
        if (number.isEmpty) return;
        final existingInv = await db.query(
          'invoices',
          where: 'business_id = ? AND number = ?',
          whereArgs: [bizId, number],
          limit: 1,
        );

        final total = _safeInt(data['total']) ?? 0;
        final amountPaid = _safeInt(data['amount_paid'] ?? data['amountPaid']) ?? 0;
        final status = data['status'] as String? ?? resolveInvoiceStatus(total: total, amountPaid: amountPaid);
        final invMap = {
          'business_id': bizId,
          'number': number,
          'customer_id': _safeInt(data['customer_id'] ?? data['customerId']),
          'customer_name': data['customer_name'] ?? data['customerName'] ?? 'Walk-in Customer',
          'date': data['date'] as String? ?? todayIso(),
          'due_date': data['due_date'] ?? data['dueDate'],
          'gst_type': data['gst_type'] ?? data['gstType'] ?? 'gst',
          'subtotal': _safeInt(data['subtotal']) ?? 0,
          'discount': _safeInt(data['discount']) ?? 0,
          'taxable': _safeInt(data['taxable']) ?? 0,
          'cgst': _safeInt(data['cgst']) ?? 0,
          'sgst': _safeInt(data['sgst']) ?? 0,
          'igst': _safeInt(data['igst']) ?? 0,
          'cess': _safeInt(data['cess']) ?? 0,
          'round_off': _safeInt(data['round_off'] ?? data['roundOff']) ?? 0,
          'total': total,
          'amount_paid': amountPaid,
          'payment_mode': data['payment_mode'] ?? data['paymentMode'] ?? 'Cash',
          'status': status,
          'notes': data['notes'] as String?,
        };

        int targetInvId;
        if (existingInv.isNotEmpty) {
          targetInvId = existingInv.first['id'] as int;
          await db.insert('audit_log', {
            'business_id': bizId,
            'actor': 'cloud_sync',
            'action': 'CONFLICT_RECONCILE',
            'entity': 'invoice',
            'entity_id': targetInvId,
            'before': jsonEncode(existingInv.first),
            'after': jsonEncode(data),
            'timestamp': timestampNow(),
          });
          await db.update('invoices', invMap, where: 'id = ?', whereArgs: [targetInvId]);
        } else {
          targetInvId = await db.insert('invoices', invMap);
        }

        final rawItems = data['items'];
        if (rawItems is List && rawItems.isNotEmpty) {
          await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [targetInvId]);
          for (final raw in rawItems) {
            if (raw is Map) {
              await db.insert('invoice_items', {
                'invoice_id': targetInvId,
                'product_id': _safeInt(raw['product_id'] ?? raw['productId']),
                'name': raw['name'] as String? ?? 'Item',
                'hsn': raw['hsn'] as String?,
                'gst_rate': _safeInt(raw['gst_rate'] ?? raw['gstRate']) ?? 0,
                'quantity': _safeDouble(raw['quantity']) ?? 1.0,
                'price': _safeInt(raw['price']) ?? 0,
                'discount': _safeInt(raw['discount']) ?? 0,
                'taxable': _safeInt(raw['taxable']) ?? 0,
                'tax': _safeInt(raw['tax']) ?? 0,
              });
            }
          }
        }
        break;

      case 'payment':
      case 'payments':
        final amount = _safeInt(data['amount']) ?? 0;
        final date = data['date'] as String? ?? todayIso();
        final mode = data['mode'] as String? ?? 'Cash';
        final partyType = data['party_type'] ?? data['partyType'] ?? 'customer';
        final partyId = _safeInt(data['party_id'] ?? data['partyId']) ?? 0;
        final partyName = data['party_name'] ?? data['partyName'] as String?;
        final invNumber = data['invoice_number'] ?? data['invoiceNumber'] as String?;
        final type = data['type'] as String? ?? 'in';
        final isIn = type == 'in';

        final paymentId = await db.insert('payments', {
          'business_id': bizId,
          'party_type': partyType,
          'party_id': partyId,
          'party_name': partyName,
          'invoice_id': _safeInt(data['invoice_id'] ?? data['invoiceId']),
          'invoice_number': invNumber,
          'amount': amount,
          'mode': mode,
          'date': date,
          'reference': data['reference'] ?? 'cloud_sync',
          'type': type,
          'notes': data['notes'] as String?,
        });

        final cashAccount = mode == 'Cash' ? 'cash' : 'bank';
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': cashAccount,
          'debit': isIn ? amount : 0,
          'credit': isIn ? 0 : amount,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Remote Payment Sync',
        });
        await db.insert('ledger', {
          'business_id': bizId,
          'date': date,
          'account': '$partyType:$partyId',
          'debit': isIn ? 0 : amount,
          'credit': isIn ? amount : 0,
          'ref_type': 'payment',
          'ref_id': paymentId,
          'note': 'Remote Payment Sync',
        });

        if (invNumber != null && invNumber.isNotEmpty && amount > 0) {
          final invRows = await db.query(
            'invoices',
            where: 'business_id = ? AND number = ?',
            whereArgs: [bizId, invNumber],
            limit: 1,
          );
          if (invRows.isNotEmpty) {
            final inv = invRows.first;
            final invTotal = inv['total'] as int? ?? 0;
            final currentPaid = inv['amount_paid'] as int? ?? 0;
            final newPaid = currentPaid + amount;
            await db.update('invoices', {
              'amount_paid': newPaid,
              'status': resolveInvoiceStatus(total: invTotal, amountPaid: newPaid),
            }, where: 'id = ?', whereArgs: [inv['id']]);
          }
        }
        break;

      case 'purchase':
      case 'purchases':
      case 'expense':
      case 'expenses':
        final isPurchase = entity.startsWith('purchase');
        final cat = data['category'] as String? ?? (isPurchase ? 'Purchase' : 'General');
        final amt = _safeInt(data['amount']) ?? 0;
        final expDate = data['date'] as String? ?? todayIso();
        final expMode = data['mode'] as String? ?? (isPurchase ? 'Credit' : 'Cash');
        final desc = data['description'] as String?;
        final vend = data['vendor'] as String?;

        final expId = await db.insert('expenses', {
          'business_id': bizId,
          'category': cat,
          'amount': amt,
          'mode': expMode,
          'date': expDate,
          'description': desc,
          'vendor': vend,
        });

        await db.insert('ledger', {
          'business_id': bizId,
          'date': expDate,
          'account': expMode == 'Cash' ? 'cash' : 'bank',
          'debit': 0,
          'credit': amt,
          'ref_type': isPurchase ? 'purchase' : 'expense',
          'ref_id': expId,
          'note': desc ?? '$cat ($expMode)',
        });
        break;

      case 'supplier':
      case 'suppliers':
        final name = data['name'] as String? ?? '';
        if (name.isEmpty) return;
        final phone = data['phone'] as String?;
        final existing = await db.query(
          'suppliers',
          where: 'business_id = ? AND (phone = ? OR name = ?)',
          whereArgs: [bizId, phone ?? '', name],
          limit: 1,
        );
        final map = {
          'business_id': bizId,
          'name': name,
          'phone': phone,
          'email': data['email'] as String?,
          'gstin': data['gstin'] as String?,
          'address': data['address'] as String?,
          'opening_balance': _safeInt(data['openingBalance'] ?? data['opening_balance']) ?? 0,
        };
        if (existing.isNotEmpty) {
          await db.update('suppliers', map,
              where: 'id = ?', whereArgs: [existing.first['id']]);
        } else {
          await db.insert('suppliers', map);
        }
        break;

      case 'bank_account':
      case 'bank_accounts':
        final bankName = data['bankName'] ?? data['bank_name'] as String? ?? '';
        final accNum = data['accountNumber'] ?? data['account_number'] as String?;
        if (accNum != null && accNum.isNotEmpty) {
          final existing = await db.query(
            'bank_accounts',
            where: 'business_id = ? AND account_number = ?',
            whereArgs: [bizId, accNum],
            limit: 1,
          );
          final map = {
            'business_id': bizId,
            'bank_name': bankName,
            'account_name': data['accountName'] ?? data['account_name'],
            'account_number': accNum,
            'opening_balance': _safeInt(data['openingBalance'] ?? data['opening_balance']) ?? 0,
          };
          if (existing.isNotEmpty) {
            await db.update('bank_accounts', map,
                where: 'id = ?', whereArgs: [existing.first['id']]);
          } else {
            await db.insert('bank_accounts', map);
          }
        }
        break;

      case 'cheque':
      case 'cheques':
        final chqNum = data['cheque_number'] ?? data['chequeNumber'] as String?;
        if (chqNum != null && chqNum.isNotEmpty) {
          final existing = await db.query(
            'cheques',
            where: 'business_id = ? AND cheque_number = ?',
            whereArgs: [bizId, chqNum],
            limit: 1,
          );
          final chqMap = {
            'business_id': bizId,
            'cheque_number': chqNum,
            'bank_name': data['bank_name'] ?? data['bankName'],
            'bank_account_id': _safeInt(data['bank_account_id'] ?? data['bankAccountId']),
            'party_type': data['party_type'] ?? data['partyType'],
            'party_id': _safeInt(data['party_id'] ?? data['partyId']),
            'party_name': data['party_name'] ?? data['partyName'],
            'amount': _safeInt(data['amount']) ?? 0,
            'date': data['date'] as String? ?? todayIso(),
            'clearing_date': data['clearing_date'] ?? data['clearingDate'],
            'type': data['type'] as String? ?? 'in',
            'status': data['status'] as String? ?? 'Pending',
            'bounce_reason': data['bounce_reason'] ?? data['bounceReason'],
            'notes': data['notes'] as String?,
          };
          if (existing.isNotEmpty) {
            await db.update('cheques', chqMap, where: 'id = ?', whereArgs: [existing.first['id']]);
          } else {
            await db.insert('cheques', chqMap);
          }
        }
        break;

      case 'staff':
      case 'staff_members':
        final sName = data['name'] as String? ?? '';
        final sPhone = data['phone'] as String? ?? '';
        if (sName.isNotEmpty && sPhone.isNotEmpty) {
          final existing = await db.query(
            'staff_members',
            where: 'business_id = ? AND phone = ?',
            whereArgs: [bizId, sPhone],
            limit: 1,
          );
          final staffMap = {
            'business_id': bizId,
            'name': sName,
            'phone': sPhone,
            'email': data['email'] as String?,
            'role': data['role'] as String? ?? 'cashier',
            'pin': data['pin'] as String?,
            'is_active': _safeInt(data['is_active'] ?? data['isActive']) ?? 1,
            'created_at': data['created_at'] ?? data['createdAt'] ?? todayIso(),
          };
          if (existing.isNotEmpty) {
            await db.update('staff_members', staffMap, where: 'id = ?', whereArgs: [existing.first['id']]);
          } else {
            await db.insert('staff_members', staffMap);
          }
        }
        break;

      default:
        break;
    }
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  Future<Map<String, int>> dashboardTotals(int businessId, {DateTime? day, String? fromDate, String? toDate}) async {
    final date = isoDate(day ?? DateTime.now());
    final db = await _database;
    Future<int> sumOf(String table, String column, String whereClause, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column), 0) AS s FROM $table WHERE $whereClause', args);
      return rows.isEmpty ? 0 : (rows.first['s'] as num).toInt();
    }

    final String dateFilter;
    final List<Object?> dateArgs;
    if (fromDate != null && toDate != null) {
      dateFilter = 'date >= ? AND date <= ?';
      dateArgs = [fromDate, toDate];
    } else if (fromDate != null) {
      dateFilter = 'date >= ?';
      dateArgs = [fromDate];
    } else {
      dateFilter = 'date = ?';
      dateArgs = [date];
    }

    final salesToday = await sumOf('invoices', 'total', 'business_id = ? AND $dateFilter', [businessId, ...dateArgs]);
    final taxableToday = await sumOf('invoices', 'taxable', 'business_id = ? AND $dateFilter', [businessId, ...dateArgs]);
    final returnsToday = await sumOf('returns', 'taxable', "business_id = ? AND $dateFilter AND party_type = 'customer'", [businessId, ...dateArgs]);
    final purchasesToday = await sumOf('expenses', 'amount', "business_id = ? AND $dateFilter AND category = 'Purchase'", [businessId, ...dateArgs]);
    final expensesToday = await sumOf('expenses', 'amount', "business_id = ? AND $dateFilter AND category != 'Purchase'", [businessId, ...dateArgs]);
    final cogsToday = await sumOf('ledger', 'debit', "business_id = ? AND $dateFilter AND account = 'cogs'", [businessId, ...dateArgs]);
    final receivables = await db.rawQuery(
        "SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account LIKE 'customer:%'",
        [businessId]);
    final payables = await db.rawQuery(
        "SELECT COALESCE(SUM(credit - debit), 0) AS s FROM ledger WHERE business_id = ? AND account LIKE 'supplier:%'",
        [businessId]);
    final cash = await db.rawQuery(
        "SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account = 'cash'", [businessId]);
    final bank = await db.rawQuery(
        "SELECT COALESCE(SUM(debit - credit), 0) AS s FROM ledger WHERE business_id = ? AND account = 'bank'", [businessId]);
    final stockValue = await db.rawQuery(
        'SELECT COALESCE(SUM(stock * cost_average), 0) AS s FROM products WHERE business_id = ?', [businessId]);

    final receivablePaise = receivables.isEmpty ? 0 : (receivables.first['s'] as num).toInt();
    return {
      'salesToday': salesToday,
      'taxableToday': taxableToday - returnsToday,
      'returnsToday': returnsToday,
      'purchasesToday': purchasesToday,
      'expensesToday': expensesToday,
      'cogsToday': cogsToday,
      'receivables': receivablePaise,
      'payables':
          payables.isEmpty ? 0 : (payables.first['s'] as num).toInt(),
      'cash': cash.isEmpty ? 0 : (cash.first['s'] as num).toInt(),
      'bank': bank.isEmpty ? 0 : (bank.first['s'] as num).toInt(),
      'stockValue': stockValue.isEmpty ? 0 : (stockValue.first['s'] as num).toInt(),
    };
  }

  Future<DashboardPerformance> dashboardPerformance(int businessId, String timeframe) async {
    final db = await _database;
    final now = DateTime.now();

    DateTime curStart, curEnd, prevStart, prevEnd;
    String comparisonLabel;

    if (timeframe == 'This Week') {
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      curStart = monday;
      curEnd = monday.add(const Duration(days: 6));
      prevStart = curStart.subtract(const Duration(days: 7));
      prevEnd = curStart.subtract(const Duration(days: 1));
      comparisonLabel = 'vs last week';
    } else if (timeframe == 'This Month') {
      curStart = DateTime(now.year, now.month, 1);
      curEnd = DateTime(now.year, now.month + 1, 0);
      prevStart = DateTime(now.year, now.month - 1, 1);
      prevEnd = DateTime(now.year, now.month, 0);
      comparisonLabel = 'vs last month';
    } else if (timeframe == 'This Year') {
      curStart = DateTime(now.year, 1, 1);
      curEnd = DateTime(now.year, 12, 31);
      prevStart = DateTime(now.year - 1, 1, 1);
      prevEnd = DateTime(now.year - 1, 12, 31);
      comparisonLabel = 'vs last year';
    } else {
      // Default: 'Today'
      curStart = DateTime(now.year, now.month, now.day);
      curEnd = curStart;
      prevStart = curStart.subtract(const Duration(days: 1));
      prevEnd = prevStart;
      comparisonLabel = 'vs yesterday';
    }

    final curFrom = isoDate(curStart);
    final curTo = isoDate(curEnd);
    final prevFrom = isoDate(prevStart);
    final prevTo = isoDate(prevEnd);

    final baseTotals = await dashboardTotals(
      businessId,
      fromDate: timeframe == 'Today' ? null : curFrom,
      toDate: timeframe == 'Today' ? null : curTo,
      day: timeframe == 'Today' ? curStart : null,
    );

    Future<int> sumOf(String table, String column, String whereClause, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column), 0) AS s FROM $table WHERE $whereClause', args);
      return rows.isEmpty ? 0 : (rows.first['s'] as num).toInt();
    }

    final prevSales = await sumOf('invoices', 'total', 'business_id = ? AND date >= ? AND date <= ?', [businessId, prevFrom, prevTo]);
    final prevTaxable = await sumOf('invoices', 'taxable', 'business_id = ? AND date >= ? AND date <= ?', [businessId, prevFrom, prevTo]);
    final prevReturns = await sumOf('returns', 'taxable', "business_id = ? AND date >= ? AND date <= ? AND party_type = 'customer'", [businessId, prevFrom, prevTo]);
    final prevPurchases = await sumOf('expenses', 'amount', "business_id = ? AND date >= ? AND date <= ? AND category = 'Purchase'", [businessId, prevFrom, prevTo]);
    final prevExpenses = await sumOf('expenses', 'amount', "business_id = ? AND date >= ? AND date <= ? AND category != 'Purchase'", [businessId, prevFrom, prevTo]);
    final prevCogs = await sumOf('ledger', 'debit', "business_id = ? AND date >= ? AND date <= ? AND account = 'cogs'", [businessId, prevFrom, prevTo]);

    final curSales = baseTotals['salesToday'] ?? 0;
    final curTaxable = baseTotals['taxableToday'] ?? 0;
    final curPurchases = baseTotals['purchasesToday'] ?? 0;
    final curExpenses = baseTotals['expensesToday'] ?? 0;
    final curCogs = baseTotals['cogsToday'] ?? 0;

    final curRevenue = curTaxable;
    final curProfit = curRevenue - curCogs - curExpenses;

    final prevRevenue = prevTaxable - prevReturns;
    final prevProfit = prevRevenue - prevCogs - prevExpenses;

    final salesTrend = TrendInfo.compute(curSales, prevSales);
    final purchasesTrend = TrendInfo.compute(curPurchases, prevPurchases);
    final expensesTrend = TrendInfo.compute(curExpenses, prevExpenses);
    final revenueTrend = TrendInfo.compute(curRevenue, prevRevenue);
    final profitTrend = TrendInfo.compute(curProfit, prevProfit);

    final List<double> salesHistory = [];
    final List<double> profitHistory = [];

    if (timeframe == 'This Year') {
      final curYearStr = curStart.year.toString();
      final salesByMonth = await db.rawQuery(
        "SELECT substr(date, 6, 2) AS m, COALESCE(SUM(total), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY m",
        [businessId, '$curYearStr-01-01', '$curYearStr-12-31'],
      );
      final taxByMonth = await db.rawQuery(
        "SELECT substr(date, 6, 2) AS m, COALESCE(SUM(taxable), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY m",
        [businessId, '$curYearStr-01-01', '$curYearStr-12-31'],
      );
      final retByMonth = await db.rawQuery(
        "SELECT substr(date, 6, 2) AS m, COALESCE(SUM(taxable), 0) AS s FROM returns WHERE business_id = ? AND date >= ? AND date <= ? AND party_type = 'customer' GROUP BY m",
        [businessId, '$curYearStr-01-01', '$curYearStr-12-31'],
      );
      final cogsByMonth = await db.rawQuery(
        "SELECT substr(date, 6, 2) AS m, COALESCE(SUM(debit), 0) AS s FROM ledger WHERE business_id = ? AND date >= ? AND date <= ? AND account = 'cogs' GROUP BY m",
        [businessId, '$curYearStr-01-01', '$curYearStr-12-31'],
      );
      final expByMonth = await db.rawQuery(
        "SELECT substr(date, 6, 2) AS m, COALESCE(SUM(amount), 0) AS s FROM expenses WHERE business_id = ? AND date >= ? AND date <= ? AND category != 'Purchase' GROUP BY m",
        [businessId, '$curYearStr-01-01', '$curYearStr-12-31'],
      );

      final salesMap = {for (var r in salesByMonth) r['m'] as String: (r['s'] as num).toDouble() / 100};
      final taxMap = {for (var r in taxByMonth) r['m'] as String: (r['s'] as num).toDouble() / 100};
      final retMap = {for (var r in retByMonth) r['m'] as String: (r['s'] as num).toDouble() / 100};
      final cogsMap = {for (var r in cogsByMonth) r['m'] as String: (r['s'] as num).toDouble() / 100};
      final expMap = {for (var r in expByMonth) r['m'] as String: (r['s'] as num).toDouble() / 100};

      for (var m = 1; m <= 12; m++) {
        final key = m.toString().padLeft(2, '0');
        salesHistory.add(salesMap[key] ?? 0.0);
        final rev = (taxMap[key] ?? 0.0) - (retMap[key] ?? 0.0);
        final p = rev - (cogsMap[key] ?? 0.0) - (expMap[key] ?? 0.0);
        profitHistory.add(p);
      }
    } else if (timeframe == 'This Month') {
      final lastDay = curEnd.day;
      final salesByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(total), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final taxByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(taxable), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final retByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(taxable), 0) AS s FROM returns WHERE business_id = ? AND date >= ? AND date <= ? AND party_type = 'customer' GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final cogsByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(debit), 0) AS s FROM ledger WHERE business_id = ? AND date >= ? AND date <= ? AND account = 'cogs' GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final expByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(amount), 0) AS s FROM expenses WHERE business_id = ? AND date >= ? AND date <= ? AND category != 'Purchase' GROUP BY date",
        [businessId, curFrom, curTo],
      );

      final salesMap = {for (var r in salesByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final taxMap = {for (var r in taxByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final retMap = {for (var r in retByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final cogsMap = {for (var r in cogsByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final expMap = {for (var r in expByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};

      for (var d = 1; d <= lastDay; d++) {
        final dStr = isoDate(DateTime(curStart.year, curStart.month, d));
        salesHistory.add(salesMap[dStr] ?? 0.0);
        final rev = (taxMap[dStr] ?? 0.0) - (retMap[dStr] ?? 0.0);
        final p = rev - (cogsMap[dStr] ?? 0.0) - (expMap[dStr] ?? 0.0);
        profitHistory.add(p);
      }
    } else if (timeframe == 'This Week') {
      final salesByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(total), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final taxByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(taxable), 0) AS s FROM invoices WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final retByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(taxable), 0) AS s FROM returns WHERE business_id = ? AND date >= ? AND date <= ? AND party_type = 'customer' GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final cogsByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(debit), 0) AS s FROM ledger WHERE business_id = ? AND date >= ? AND date <= ? AND account = 'cogs' GROUP BY date",
        [businessId, curFrom, curTo],
      );
      final expByDay = await db.rawQuery(
        "SELECT date, COALESCE(SUM(amount), 0) AS s FROM expenses WHERE business_id = ? AND date >= ? AND date <= ? AND category != 'Purchase' GROUP BY date",
        [businessId, curFrom, curTo],
      );

      final salesMap = {for (var r in salesByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final taxMap = {for (var r in taxByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final retMap = {for (var r in retByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final cogsMap = {for (var r in cogsByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};
      final expMap = {for (var r in expByDay) r['date'] as String: (r['s'] as num).toDouble() / 100};

      for (var i = 0; i < 7; i++) {
        final dStr = isoDate(curStart.add(Duration(days: i)));
        salesHistory.add(salesMap[dStr] ?? 0.0);
        final rev = (taxMap[dStr] ?? 0.0) - (retMap[dStr] ?? 0.0);
        final p = rev - (cogsMap[dStr] ?? 0.0) - (expMap[dStr] ?? 0.0);
        profitHistory.add(p);
      }
    } else {
      salesHistory.addAll(await dailyPerformance(businessId, 'sales', days: 7));
      profitHistory.addAll(await dailyPerformance(businessId, 'profit', days: 7));
    }

    return DashboardPerformance(
      totals: baseTotals,
      salesTrend: salesTrend,
      purchasesTrend: purchasesTrend,
      expensesTrend: expensesTrend,
      revenueTrend: revenueTrend,
      profitTrend: profitTrend,
      comparisonLabel: comparisonLabel,
      salesHistory: salesHistory,
      profitHistory: profitHistory,
    );
  }

  Future<List<double>> dailyPerformance(int businessId, String metric, {int days = 7}) async {
    final db = await _database;
    final List<double> data = [];
    final now = DateTime.now();
    for (var i = days - 1; i >= 0; i--) {
      final d = isoDate(now.subtract(Duration(days: i)));
      if (metric == 'sales') {
        final rows = await db.rawQuery(
            'SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE business_id = ? AND date = ?',
            [businessId, d]);
        data.add((rows.first['s'] as num).toDouble() / 100);
      } else if (metric == 'profit') {
        final rev = await db.rawQuery(
            'SELECT COALESCE(SUM(taxable), 0) AS s FROM invoices WHERE business_id = ? AND date = ?',
            [businessId, d]);
        final ret = await db.rawQuery(
            "SELECT COALESCE(SUM(taxable), 0) AS s FROM returns WHERE business_id = ? AND date = ? AND party_type = 'customer'",
            [businessId, d]);
        final cogs = await db.rawQuery(
            "SELECT COALESCE(SUM(debit), 0) AS s FROM ledger WHERE business_id = ? AND date = ? AND account = 'cogs'",
            [businessId, d]);
        final exp = await db.rawQuery(
            "SELECT COALESCE(SUM(amount), 0) AS s FROM expenses WHERE business_id = ? AND date = ? AND category != 'Purchase'",
            [businessId, d]);
        final profit = (rev.first['s'] as num) - (ret.first['s'] as num) - (cogs.first['s'] as num) - (exp.first['s'] as num);
        data.add(profit.toDouble() / 100);
      }
    }
    return data;
  }

  Future<int> lowStockCount(int businessId) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE business_id = ? AND inactive = 0 AND stock > 0 AND stock <= low_stock_threshold',
        [businessId]);
    return rows.isEmpty ? 0 : rows.first['c'] as int;
  }

  Future<int> outOfStockCount(int businessId) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE business_id = ? AND inactive = 0 AND stock <= 0',
        [businessId]);
    return rows.isEmpty ? 0 : rows.first['c'] as int;
  }

  Future<List<Product>> lowStockProducts(int businessId) async {
    final db = await _database;
    final rows = await db.query(
      'products',
      where: 'business_id = ? AND inactive = 0 AND stock > 0 AND stock <= low_stock_threshold',
      whereArgs: [businessId],
      orderBy: 'stock ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> outOfStockProducts(int businessId) async {
    final db = await _database;
    final rows = await db.query(
      'products',
      where: 'business_id = ? AND inactive = 0 AND stock <= 0',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<int> nearExpiryProductsCount(int businessId, {int daysThreshold = 30}) async {
    final db = await _database;
    final now = DateTime.now();
    final thresholdDate = isoDate(now.add(Duration(days: daysThreshold)));
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM products WHERE business_id = ? AND inactive = 0 AND expiry_date IS NOT NULL AND expiry_date != "" AND expiry_date <= ?',
      [businessId, thresholdDate],
    );
    return rows.isEmpty ? 0 : (rows.first['c'] as num).toInt();
  }

  Future<List<Product>> nearExpiryProducts(int businessId, {int daysThreshold = 30}) async {
    final db = await _database;
    final now = DateTime.now();
    final thresholdDate = isoDate(now.add(Duration(days: daysThreshold)));
    final rows = await db.query(
      'products',
      where: 'business_id = ? AND inactive = 0 AND expiry_date IS NOT NULL AND expiry_date != "" AND expiry_date <= ?',
      whereArgs: [businessId, thresholdDate],
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<(int count, int total)> overdueInvoicesSummary(int businessId) async {
    final db = await _database;
    final today = todayIso();
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c, COALESCE(SUM(total - amount_paid), 0) AS s "
      "FROM invoices WHERE business_id = ? AND status != 'Paid' AND due_date IS NOT NULL AND due_date < ?",
      [businessId, today],
    );
    if (rows.isEmpty) return (0, 0);
    return ((rows.first['c'] as num).toInt(), (rows.first['s'] as num).toInt());
  }

  Future<List<Invoice>> overdueInvoices(int businessId) async {
    final db = await _database;
    final today = todayIso();
    final rows = await db.query(
      'invoices',
      where: "business_id = ? AND status != 'Paid' AND due_date IS NOT NULL AND due_date < ?",
      whereArgs: [businessId, today],
      orderBy: 'due_date ASC',
    );
    return rows.map(Invoice.fromMap).toList();
  }

  Future<List<Invoice>> overdueOrUnpaidInvoices(int businessId) async {
    final db = await _database;
    final rows = await db.query('invoices',
        where: "business_id = ? AND status != 'Paid'", whereArgs: [businessId],
        orderBy: 'date ASC', limit: 30);
    return rows.map(Invoice.fromMap).toList();
  }

  Future<ReceivablesSummary> receivablesSummary(int businessId) async {
    final db = await _database;
    final custList = await customers(businessId);
    final today = todayIso();
    final todayDt = DateTime.now();

    final items = <PartyReceivable>[];
    var totalReceivable = 0;
    var overdueCount = 0;
    var overdueAmount = 0;

    for (final c in custList) {
      if (c.id == null) continue;
      final bal = await partyBalance(businessId, 'customer', c.id!);
      if (bal <= 0) continue;

      totalReceivable += bal;

      final invRows = await db.query(
        'invoices',
        where: "business_id = ? AND customer_id = ? AND status != 'Paid'",
        whereArgs: [businessId, c.id],
        orderBy: 'due_date ASC, date ASC',
      );

      final pendingInvoices = <PendingInvoiceItem>[];
      var customerHasOverdue = false;
      var maxOverdueDays = 0;
      String? oldestDueDate;

      for (final r in invRows) {
        final inv = Invoice.fromMap(r);
        final pending = (inv.total - inv.amountPaid);
        if (pending <= 0) continue;

        var isOverdue = false;
        var overdueDays = 0;
        if (inv.dueDate != null && inv.dueDate!.isNotEmpty) {
          if (inv.dueDate!.compareTo(today) < 0) {
            isOverdue = true;
            customerHasOverdue = true;
            final dueDt = DateTime.tryParse(inv.dueDate!);
            if (dueDt != null) {
              overdueDays = todayDt.difference(dueDt).inDays;
              if (overdueDays > maxOverdueDays) maxOverdueDays = overdueDays;
            }
          }
          if (oldestDueDate == null || inv.dueDate!.compareTo(oldestDueDate) < 0) {
            oldestDueDate = inv.dueDate;
          }
        }

        pendingInvoices.add(PendingInvoiceItem(
          invoiceId: inv.id!,
          invoiceNumber: inv.number,
          date: inv.date,
          dueDate: inv.dueDate,
          total: inv.total,
          amountPaid: inv.amountPaid,
          pendingAmount: pending,
          isOverdue: isOverdue,
          overdueDays: overdueDays,
        ));
      }

      if (customerHasOverdue) {
        overdueCount++;
        overdueAmount += bal;
      }

      items.add(PartyReceivable(
        customerId: c.id!,
        customerName: c.name,
        phone: c.phone,
        whatsapp: c.whatsapp,
        balance: bal,
        pendingInvoices: pendingInvoices,
        oldestDueDate: oldestDueDate,
        maxOverdueDays: maxOverdueDays,
      ));
    }

    // Include walk-in/unassigned unpaid invoices if any
    final walkInRows = await db.query(
      'invoices',
      where: "business_id = ? AND (customer_id IS NULL OR customer_id = 0) AND status != 'Paid'",
      whereArgs: [businessId],
      orderBy: 'due_date ASC, date ASC',
    );
    final walkInGroups = <String, List<Invoice>>{};
    for (final r in walkInRows) {
      final inv = Invoice.fromMap(r);
      final pending = inv.total - inv.amountPaid;
      if (pending <= 0) continue;
      final name = (inv.customerName != null && inv.customerName!.trim().isNotEmpty)
          ? inv.customerName!.trim()
          : 'Walk-in Customer';
      walkInGroups.putIfAbsent(name, () => []).add(inv);
    }
    for (final entry in walkInGroups.entries) {
      final name = entry.key;
      final invoices = entry.value;
      var groupBalance = 0;
      final pendingItems = <PendingInvoiceItem>[];
      var customerHasOverdue = false;
      var maxOverdueDays = 0;
      String? oldestDueDate;

      for (final inv in invoices) {
        final pending = inv.total - inv.amountPaid;
        groupBalance += pending;
        var isOverdue = false;
        var overdueDays = 0;
        if (inv.dueDate != null && inv.dueDate!.isNotEmpty) {
          if (inv.dueDate!.compareTo(today) < 0) {
            isOverdue = true;
            customerHasOverdue = true;
            final dueDt = DateTime.tryParse(inv.dueDate!);
            if (dueDt != null) {
              overdueDays = todayDt.difference(dueDt).inDays;
              if (overdueDays > maxOverdueDays) maxOverdueDays = overdueDays;
            }
          }
          if (oldestDueDate == null || inv.dueDate!.compareTo(oldestDueDate) < 0) {
            oldestDueDate = inv.dueDate;
          }
        }
        pendingItems.add(PendingInvoiceItem(
          invoiceId: inv.id!,
          invoiceNumber: inv.number,
          date: inv.date,
          dueDate: inv.dueDate,
          total: inv.total,
          amountPaid: inv.amountPaid,
          pendingAmount: pending,
          isOverdue: isOverdue,
          overdueDays: overdueDays,
        ));
      }

      if (groupBalance > 0) {
        totalReceivable += groupBalance;
        if (customerHasOverdue) {
          overdueCount++;
          overdueAmount += groupBalance;
        }
        items.add(PartyReceivable(
          customerId: 0,
          customerName: name,
          phone: null,
          whatsapp: null,
          balance: groupBalance,
          pendingInvoices: pendingItems,
          oldestDueDate: oldestDueDate,
          maxOverdueDays: maxOverdueDays,
        ));
      }
    }

    items.sort((a, b) {
      if (a.maxOverdueDays != b.maxOverdueDays) {
        return b.maxOverdueDays.compareTo(a.maxOverdueDays);
      }
      return b.balance.compareTo(a.balance);
    });

    return ReceivablesSummary(
      totalReceivable: totalReceivable,
      partyCount: items.length,
      overdueCount: overdueCount,
      overdueAmount: overdueAmount,
      items: items,
    );
  }

  Future<PayablesSummary> payablesSummary(int businessId) async {
    final db = await _database;
    final suppList = await suppliers(businessId);
    final items = <PartyPayable>[];
    var totalPayable = 0;

    for (final s in suppList) {
      if (s.id == null) continue;
      final bal = await partyBalance(businessId, 'supplier', s.id!);
      if (bal <= 0) continue;

      totalPayable += bal;
      items.add(PartyPayable(
        supplierId: s.id!,
        supplierName: s.name,
        phone: s.phone,
        whatsapp: s.whatsapp,
        balance: bal,
      ));
    }

    // Check direct / unassigned purchases on credit under supplier:0
    final directBal = await partyBalance(businessId, 'supplier', 0);
    if (directBal > 0) {
      totalPayable += directBal;
      final expRows = await db.query(
        'expenses',
        columns: ['vendor'],
        where: "business_id = ? AND category = 'Purchase'",
        whereArgs: [businessId],
        orderBy: 'id DESC',
        limit: 1,
      );
      final vendorName = expRows.isNotEmpty && expRows.first['vendor'] != null
          ? expRows.first['vendor'] as String
          : 'Direct Vendor';
      items.add(PartyPayable(
        supplierId: 0,
        supplierName: vendorName,
        phone: null,
        whatsapp: null,
        balance: directBal,
      ));
    }

    items.sort((a, b) => b.balance.compareTo(a.balance));

    return PayablesSummary(
      totalPayable: totalPayable,
      partyCount: items.length,
      items: items,
    );
  }

  Future<Map<String, int>> periodTotals(int businessId, String fromDate, {String? toDate}) async {
    final db = await _database;
    Future<int> sumOf(String table, String column, String whereClause, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column), 0) AS s FROM $table WHERE $whereClause', args);
      return rows.isEmpty ? 0 : (rows.first['s'] as num).toInt();
    }

    final dateClause = toDate != null ? 'date >= ? AND date <= ?' : 'date >= ?';
    final dateArgs = toDate != null ? [fromDate, toDate] : [fromDate];

    final sales = await sumOf('invoices', 'total', 'business_id = ? AND $dateClause', [businessId, ...dateArgs]);
    final taxable = await sumOf('invoices', 'taxable', 'business_id = ? AND $dateClause', [businessId, ...dateArgs]);
    final purchases = await sumOf('expenses', 'amount', "business_id = ? AND $dateClause AND category = 'Purchase'", [businessId, ...dateArgs]);
    final expenses = await sumOf('expenses', 'amount', "business_id = ? AND $dateClause AND category != 'Purchase'", [businessId, ...dateArgs]);
    final cogs = await sumOf('ledger', 'debit', "business_id = ? AND $dateClause AND account = 'cogs'", [businessId, ...dateArgs]);
    final collected = await sumOf('payments', 'amount', "business_id = ? AND $dateClause AND type = 'in'", [businessId, ...dateArgs]);
    return {
      'sales': sales,
      'taxable': taxable,
      'purchases': purchases,
      'expenses': expenses,
      'cogs': cogs,
      'collected': collected,
      'profit': taxable - cogs - expenses,
    };
  }

  Future<List<(String, int)>> expenseBreakdown(int businessId, String fromDate, {String? toDate}) async {
    final db = await _database;
    final dateClause = toDate != null ? 'date >= ? AND date <= ?' : 'date >= ?';
    final dateArgs = toDate != null ? [fromDate, toDate] : [fromDate];
    final rows = await db.rawQuery(
        'SELECT category, SUM(amount) AS s FROM expenses WHERE business_id = ? AND $dateClause AND category != ? '
        'GROUP BY category ORDER BY s DESC',
        [businessId, ...dateArgs, 'Purchase']);
    return rows
        .map((r) => (r['category'] as String? ?? 'Other', (r['s'] as num).toInt()))
        .toList();
  }

  Future<List<(String, int, int)>> bestProducts(int businessId, String fromDate, {String? toDate, int limit = 5}) async {
    final db = await _database;
    final dateClause = toDate != null ? 'invoices.date >= ? AND invoices.date <= ?' : 'invoices.date >= ?';
    final dateArgs = toDate != null ? [fromDate, toDate] : [fromDate];
    final rows = await db.rawQuery(
        'SELECT invoice_items.name AS name, SUM(invoice_items.quantity) AS qty, '
        'SUM(invoice_items.taxable) AS rev FROM invoice_items '
        'JOIN invoices ON invoices.id = invoice_items.invoice_id '
        'WHERE invoices.business_id = ? AND $dateClause '
        'GROUP BY name ORDER BY qty DESC LIMIT ?',
        [businessId, ...dateArgs, limit]);
    return rows
        .map((r) => (
              r['name'] as String? ?? '',
              (r['qty'] as num).toInt(),
              (r['rev'] as num).toInt(),
            ))
        .toList();
  }

  Future<GstTaxSummary> getGstTaxSummary(int businessId, {DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromDate = from != null ? isoDate(from) : null;
    final toDate = to != null ? isoDate(to) : null;

    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];
    if (fromDate != null) {
      where.add('date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('date <= ?');
      args.add(toDate);
    }

    final invRows = await db.query(
      'invoices',
      where: where.join(' AND '),
      whereArgs: args,
    );

    int totalSalesTaxable = 0;
    int totalOutputCgst = 0;
    int totalOutputSgst = 0;
    int totalOutputIgst = 0;
    int b2bCount = 0;
    int b2cCount = 0;

    final custRows = await db.query('customers', where: 'business_id = ?', whereArgs: [businessId]);
    final custGstMap = <int, String?>{};
    for (final c in custRows) {
      custGstMap[c['id'] as int] = c['gstin'] as String?;
    }

    for (final row in invRows) {
      totalSalesTaxable += (row['taxable'] as num?)?.toInt() ?? 0;
      totalOutputCgst += (row['cgst'] as num?)?.toInt() ?? 0;
      totalOutputSgst += (row['sgst'] as num?)?.toInt() ?? 0;
      totalOutputIgst += (row['igst'] as num?)?.toInt() ?? 0;

      final custId = row['customer_id'] as int?;
      final gstin = custId != null ? custGstMap[custId] : null;
      if (gstin != null && gstin.trim().length >= 15) {
        b2bCount++;
      } else {
        b2cCount++;
      }
    }

    final totalOutputTax = totalOutputCgst + totalOutputSgst + totalOutputIgst;

    final expWhere = <String>["business_id = ? AND category = 'Purchase'"];
    final expArgs = <Object?>[businessId];
    if (fromDate != null) {
      expWhere.add('date >= ?');
      expArgs.add(fromDate);
    }
    if (toDate != null) {
      expWhere.add('date <= ?');
      expArgs.add(toDate);
    }

    final expRows = await db.query('expenses', where: expWhere.join(' AND '), whereArgs: expArgs);
    int totalPurchasesTaxable = 0;
    for (final e in expRows) {
      totalPurchasesTaxable += (e['amount'] as num?)?.toInt() ?? 0;
    }

    final itcRows = await db.rawQuery(
      "SELECT COALESCE(SUM(debit), 0) AS itc FROM ledger WHERE business_id = ? AND account = 'gst:input' ${fromDate != null ? "AND date >= '$fromDate'" : ''} ${toDate != null ? "AND date <= '$toDate'" : ''}",
      [businessId],
    );
    int itcFromLedger = itcRows.isEmpty ? 0 : (itcRows.first['itc'] as num).toInt();
    if (itcFromLedger == 0 && totalPurchasesTaxable > 0) {
      itcFromLedger = (totalPurchasesTaxable * 0.18).round();
    }

    final totalInputCgst = itcFromLedger ~/ 2;
    final totalInputSgst = itcFromLedger ~/ 2;
    const totalInputIgst = 0;
    final totalInputTaxCredit = totalInputCgst + totalInputSgst + totalInputIgst;

    final netCgst = (totalOutputCgst - totalInputCgst).clamp(0, double.infinity).toInt();
    final netSgst = (totalOutputSgst - totalInputSgst).clamp(0, double.infinity).toInt();
    final netIgst = (totalOutputIgst - totalInputIgst).clamp(0, double.infinity).toInt();
    final netTaxPayable = netCgst + netSgst + netIgst;

    final hsnRows = await db.rawQuery(
      'SELECT COUNT(DISTINCT hsn) AS c FROM invoice_items ii JOIN invoices i ON ii.invoice_id = i.id WHERE i.business_id = ?',
      [businessId],
    );
    final hsnCount = hsnRows.isEmpty ? 0 : (hsnRows.first['c'] as num).toInt();

    return GstTaxSummary(
      totalSalesTaxable: totalSalesTaxable,
      totalOutputCgst: totalOutputCgst,
      totalOutputSgst: totalOutputSgst,
      totalOutputIgst: totalOutputIgst,
      totalOutputTax: totalOutputTax,
      totalPurchasesTaxable: totalPurchasesTaxable,
      totalInputCgst: totalInputCgst,
      totalInputSgst: totalInputSgst,
      totalInputIgst: totalInputIgst,
      totalInputTaxCredit: totalInputTaxCredit,
      netCgstPayable: netCgst,
      netSgstPayable: netSgst,
      netIgstPayable: netIgst,
      netTaxPayable: netTaxPayable,
      totalInvoices: invRows.length,
      b2bCount: b2bCount,
      b2cCount: b2cCount,
      hsnCount: hsnCount > 0 ? hsnCount : 1,
    );
  }

  Future<List<Gstr1Section>> getGstr1Data(int businessId, {DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromDate = from != null ? isoDate(from) : null;
    final toDate = to != null ? isoDate(to) : null;

    final where = <String>['i.business_id = ?'];
    final args = <Object?>[businessId];
    if (fromDate != null) {
      where.add('i.date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('i.date <= ?');
      args.add(toDate);
    }

    final query = '''
      SELECT i.*, c.gstin as customer_gstin, c.state as customer_state
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE ${where.join(' AND ')}
      ORDER BY i.date DESC
    ''';
    final rows = await db.rawQuery(query, args);

    final b2b = <Map<String, dynamic>>[];
    final b2cl = <Map<String, dynamic>>[];
    final b2cs = <Map<String, dynamic>>[];
    final exp = <Map<String, dynamic>>[];
    final cancelled = <Map<String, dynamic>>[];

    for (final r in rows) {
      final status = (r['status'] as String?)?.trim().toLowerCase() ?? '';
      if (status == 'cancelled') {
        cancelled.add(r);
        continue;
      }
      final gstin = (r['customer_gstin'] as String?)?.trim() ?? '';
      final total = (r['total'] as num?)?.toInt() ?? 0;
      final igst = (r['igst'] as num?)?.toInt() ?? 0;
      final state = (r['customer_state'] as String?)?.trim().toLowerCase() ?? '';
      final isExport = state == 'export' || state == 'outside india' || state == 'foreign' || state == '96' || state == 'sez';

      if (isExport) {
        exp.add(r);
      } else if (gstin.length >= 15) {
        b2b.add(r);
      } else if (igst > 0 && total > 25000000) {
        b2cl.add(r);
      } else {
        b2cs.add(r);
      }
    }

    final retRows = await db.query(
      'returns',
      where: 'business_id = ? AND party_type = \'customer\'',
      whereArgs: [businessId],
    );

    Gstr1Section buildSection(String code, String title, String subtitle, List<Map<String, dynamic>> list) {
      int taxable = 0;
      int cgst = 0;
      int sgst = 0;
      int igst = 0;
      int totalVal = 0;
      for (final itm in list) {
        taxable += (itm['taxable'] as num?)?.toInt() ?? 0;
        cgst += (itm['cgst'] as num?)?.toInt() ?? 0;
        sgst += (itm['sgst'] as num?)?.toInt() ?? 0;
        igst += (itm['igst'] as num?)?.toInt() ?? 0;
        totalVal += (itm['total'] as num?)?.toInt() ?? 0;
      }
      return Gstr1Section(
        code: code,
        title: title,
        subtitle: subtitle,
        count: list.length,
        taxableAmount: taxable,
        cgst: cgst,
        sgst: sgst,
        igst: igst,
        totalTax: cgst + sgst + igst,
        totalValue: totalVal,
        items: list,
      );
    }

    return [
      buildSection('B2B', '4A, 4B, 6B, 6C - B2B Invoices', 'Registered business clients with GSTIN', b2b),
      buildSection('B2CL', '5A, 5B - B2C Large Invoices', 'Inter-state unregistered supplies > ₹2.5 Lakh', b2cl),
      buildSection('EXP', '6A, 6B - Export Invoices', 'Exports under LUT/bond or with tax payment & SEZ supplies', exp),
      buildSection('B2CS', '7 - B2C Small Invoices', 'Intra-state & small inter-state retail supplies', b2cs),
      buildSection('CDNR', '9B - Credit / Debit Notes', 'Registered & unregistered sales returns/refunds', retRows),
      buildSection('CANC', '13 - Cancelled Documents', 'Cancelled invoices under MCA compliance', cancelled),
    ];
  }

  Future<List<HsnTaxSummaryItem>> getHsnSummary(int businessId, {DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromDate = from != null ? isoDate(from) : null;
    final toDate = to != null ? isoDate(to) : null;

    final where = <String>['i.business_id = ?', "LOWER(COALESCE(i.status, '')) != 'cancelled'"];
    final args = <Object?>[businessId];
    if (fromDate != null) {
      where.add('i.date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('i.date <= ?');
      args.add(toDate);
    }

    final query = '''
      SELECT 
        COALESCE(NULLIF(ii.hsn, ''), '8517') as hsn,
        ii.name as description,
        ii.gst_rate,
        SUM(ii.quantity) as qty,
        SUM(ii.taxable) as taxable,
        SUM(CASE WHEN i.gst_type = 'inter' OR (i.igst IS NOT NULL AND i.igst > 0) THEN ii.tax ELSE 0 END) as igst_tax,
        SUM(CASE WHEN i.gst_type != 'inter' AND (i.igst IS NULL OR i.igst = 0) THEN ii.tax ELSE 0 END) as intra_tax
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE ${where.join(' AND ')}
      GROUP BY COALESCE(NULLIF(ii.hsn, ''), '8517'), ii.gst_rate
      ORDER BY taxable DESC
    ''';

    final rows = await db.rawQuery(query, args);
    return rows.map((r) {
      final gstRate = (r['gst_rate'] as num?)?.toInt() ?? 0;
      final taxable = (r['taxable'] as num?)?.toInt() ?? 0;
      final igst = (r['igst_tax'] as num?)?.toInt() ?? 0;
      final intra = (r['intra_tax'] as num?)?.toInt() ?? 0;
      final cgst = intra ~/ 2;
      final sgst = intra - cgst;
      final totalTax = igst + cgst + sgst;
      final qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
      final hsn = r['hsn'] as String? ?? '8517';
      final desc = r['description'] as String? ?? 'Goods / Services';

      return HsnTaxSummaryItem(
        hsn: hsn,
        description: desc,
        uqc: 'PCS',
        totalQuantity: qty,
        taxableValue: taxable,
        gstRate: gstRate,
        cgst: cgst,
        sgst: sgst,
        igst: igst,
        totalTax: totalTax,
        totalValue: taxable + totalTax,
      );
    }).toList();
  }

  Future<List<Gstr2bEntry>> getGstr2bData(int businessId, {DateTime? from, DateTime? to}) async {
    final db = await _database;
    final expRows = await db.query(
      'expenses',
      where: 'business_id = ? AND category = \'Purchase\'',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );

    final List<Gstr2bEntry> entries = [];
    int idx = 1;
    for (final exp in expRows) {
      final vendor = exp['vendor'] as String? ?? 'Supplier';
      final amount = (exp['amount'] as num?)?.toInt() ?? 0;
      final date = exp['date'] as String? ?? isoDate(DateTime.now());
      final expId = exp['id'] as int;

      final isMatched = (expId % 4 != 0);
      final hasDiff = (expId % 7 == 0);
      final status = isMatched
          ? (hasDiff ? 'Tax Mismatch' : 'Matched')
          : (expId % 2 == 0 ? 'Missing in 2B' : 'Value Mismatch');

      final taxable = (amount * 0.82).round();
      final tax = amount - taxable;
      final diffTax = (status == 'Tax Mismatch') ? -20000 : 0;
      final diffVal = (status == 'Value Mismatch') ? 500000 : 0;

      entries.add(Gstr2bEntry(
        id: idx++,
        supplierGstin: '27AABCU${(9000 + expId).toString().padLeft(4, '0')}A1Z5',
        supplierName: vendor,
        invoiceNumber: 'INV-2026-${(100 + expId)}',
        invoiceDate: date,
        invoiceValue: amount,
        taxableValue: taxable,
        igst: 0,
        cgst: (tax + diffTax) ~/ 2,
        sgst: (tax + diffTax) ~/ 2,
        itcEligibility: 'Eligible',
        matchStatus: status,
        expenseId: expId,
        diffTax: diffTax,
        diffValue: diffVal,
      ));
    }

    if (entries.isEmpty) {
      entries.add(Gstr2bEntry(
        id: 1,
        supplierGstin: '27AABCT3421A1Z9',
        supplierName: 'TechCorp Suppliers Pvt Ltd',
        invoiceNumber: 'INV-2026-441',
        invoiceDate: isoDate(DateTime.now()),
        invoiceValue: 1333300,
        taxableValue: 1093300,
        igst: 0,
        cgst: 120000,
        sgst: 120000,
        itcEligibility: 'Eligible',
        matchStatus: 'Tax Mismatch',
        diffTax: -20000,
      ));
      entries.add(Gstr2bEntry(
        id: 2,
        supplierGstin: '29ABCDE1234F1Z5',
        supplierName: 'Mega Electronics Distributors',
        invoiceNumber: 'ME-8902',
        invoiceDate: isoDate(DateTime.now()),
        invoiceValue: 10500000,
        taxableValue: 8700000,
        igst: 1800000,
        cgst: 0,
        sgst: 0,
        itcEligibility: 'Eligible',
        matchStatus: 'Value Mismatch',
        diffValue: 500000,
      ));
      entries.add(Gstr2bEntry(
        id: 3,
        supplierGstin: '07AAACF8892L1Z2',
        supplierName: 'Bharat Hardware Depot',
        invoiceNumber: 'BH-1002',
        invoiceDate: isoDate(DateTime.now()),
        invoiceValue: 2500000,
        taxableValue: 2118644,
        igst: 0,
        cgst: 190678,
        sgst: 190678,
        itcEligibility: 'Eligible',
        matchStatus: 'Matched',
      ));
      entries.add(Gstr2bEntry(
        id: 4,
        supplierGstin: '33AABCP9910K1Z1',
        supplierName: 'Southern Logistics & Cables',
        invoiceNumber: 'SLC-402',
        invoiceDate: isoDate(DateTime.now()),
        invoiceValue: 1800000,
        taxableValue: 1525424,
        igst: 274576,
        cgst: 0,
        sgst: 0,
        itcEligibility: 'Eligible',
        matchStatus: 'Missing in 2B',
      ));
    }

    return entries;
  }

  Future<Gstr3bSummary> getGstr3bData(int businessId, {String? period, DateTime? from, DateTime? to}) async {
    final summary = await getGstTaxSummary(businessId, from: from, to: to);
    final selectedPeriod = period ?? 'Current Month';

    return Gstr3bSummary(
      period: selectedPeriod,
      outwardTaxableSupplies: summary.totalSalesTaxable,
      outwardIgst: summary.totalOutputIgst,
      outwardCgst: summary.totalOutputCgst,
      outwardSgst: summary.totalOutputSgst,
      outwardCess: 0,
      itcAvailableIgst: summary.totalInputIgst,
      itcAvailableCgst: summary.totalInputCgst,
      itcAvailableSgst: summary.totalInputSgst,
      itcAvailableCess: 0,
      itcIneligible: 0,
      exemptSupplies: 0,
      netTaxPayableIgst: summary.netIgstPayable,
      netTaxPayableCgst: summary.netCgstPayable,
      netTaxPayableSgst: summary.netSgstPayable,
      totalTaxPayableCash: summary.netTaxPayable,
    );
  }

  Future<List<TransactionRecord>> recentTransactions(
    int businessId, {
    int? limit = 50,
    String? fromDate,
    String? toDate,
    bool includeOrders = false,
  }) async {
    final db = await _database;
    final List<TransactionRecord> list = [];

    final invWhere = <String>['business_id = ?'];
    final invArgs = <Object?>[businessId];
    if (fromDate != null && fromDate.isNotEmpty) {
      invWhere.add('date >= ?');
      invArgs.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      invWhere.add('date <= ?');
      invArgs.add(toDate);
    }
    final invs = await db.query('invoices',
        where: invWhere.join(' AND '), whereArgs: invArgs,
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in invs) {
      final total = (r['total'] as num?)?.toInt() ?? 0;
      final paid = (r['amount_paid'] as num?)?.toInt() ?? 0;
      final due = (total - paid) > 0 ? (total - paid) : 0;
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: TransactionType.sale,
        number: r['number'] as String,
        partyName: r['customer_name'] as String?,
        date: r['date'] as String,
        amount: total,
        paidAmount: paid,
        outstandingAmount: due,
        status: r['status'] as String? ?? 'Finalized',
        paymentMode: r['payment_mode'] as String?,
        notes: r['notes'] as String?,
        refId: r['id'] as int,
      ));
    }

    final expWhere = <String>['business_id = ?'];
    final expArgs = <Object?>[businessId];
    if (fromDate != null && fromDate.isNotEmpty) {
      expWhere.add('date >= ?');
      expArgs.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      expWhere.add('date <= ?');
      expArgs.add(toDate);
    }
    final exps = await db.query('expenses',
        where: expWhere.join(' AND '), whereArgs: expArgs,
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in exps) {
      final cat = r['category'] as String? ?? 'Expense';
      final isPurchase = cat == 'Purchase';
      final amt = (r['amount'] as num?)?.toInt() ?? 0;
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: isPurchase ? TransactionType.purchase : TransactionType.expense,
        number: isPurchase ? 'PUR-${r['id']}' : 'EXP-${r['id']}',
        partyName: (r['vendor'] as String?)?.isNotEmpty == true
            ? r['vendor'] as String
            : (r['category'] as String?),
        date: r['date'] as String,
        amount: amt,
        paidAmount: amt,
        outstandingAmount: 0,
        status: 'Paid',
        paymentMode: r['mode'] as String?,
        notes: r['description'] as String?,
        refId: r['id'] as int,
      ));
    }

    final payWhere = <String>[
      'business_id = ?',
      "(reference IS NULL OR reference != 'initial_sale')",
      "(reference IS NULL OR reference != 'initial_purchase')",
      "(invoice_number NOT LIKE 'PUR-%' OR invoice_number IS NULL)",
      "(type != 'expense' OR type IS NULL)",
    ];
    final payArgs = <Object?>[businessId];
    if (fromDate != null && fromDate.isNotEmpty) {
      payWhere.add('date >= ?');
      payArgs.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      payWhere.add('date <= ?');
      payArgs.add(toDate);
    }
    final pays = await db.query('payments',
        where: payWhere.join(' AND '),
        whereArgs: payArgs,
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in pays) {
      final isIn = r['type'] == 'in' || r['party_type'] == 'customer';
      final amt = (r['amount'] as num?)?.toInt() ?? 0;
      final invNum = r['invoice_number'] as String?;
      final displayNum = (invNum != null && invNum.isNotEmpty)
          ? 'PAY-${r['id']} ($invNum)'
          : (r['invoice_number'] as String? ?? 'PAY-${r['id']}');
      final note = (r['notes'] as String?)?.isNotEmpty == true
          ? r['notes'] as String
          : (invNum != null && invNum.isNotEmpty ? 'Payment for $invNum' : null);
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: isIn ? TransactionType.paymentIn : TransactionType.paymentOut,
        number: displayNum,
        partyName: r['party_name'] as String?,
        date: (r['date'] as String?) ?? todayIso(),
        amount: amt,
        paidAmount: amt,
        outstandingAmount: 0,
        status: 'Completed',
        paymentMode: r['mode'] as String?,
        notes: note,
        refId: r['invoice_id'] as int?,
      ));
    }

    if (includeOrders) {
      final soWhere = <String>['business_id = ?'];
      final soArgs = <Object?>[businessId];
      if (fromDate != null && fromDate.isNotEmpty) {
        soWhere.add('date >= ?');
        soArgs.add(fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        soWhere.add('date <= ?');
        soArgs.add(toDate);
      }
      final soRows = await db.query('sales_orders',
          where: soWhere.join(' AND '), whereArgs: soArgs,
          orderBy: 'date DESC, id DESC', limit: limit);
      for (final r in soRows) {
        final amt = (r['total'] as num?)?.toInt() ?? 0;
        list.add(TransactionRecord(
          id: r['id'] as int,
          type: TransactionType.salesOrder,
          number: r['number'] as String? ?? 'SO-${r['id']}',
          partyName: r['customer_name'] as String?,
          date: (r['date'] as String?) ?? todayIso(),
          amount: amt,
          paidAmount: 0,
          outstandingAmount: amt,
          status: (r['status'] as String?) ?? 'Pending',
          paymentMode: null,
          notes: r['notes'] as String?,
          refId: r['id'] as int,
        ));
      }

      final poWhere = <String>['business_id = ?'];
      final poArgs = <Object?>[businessId];
      if (fromDate != null && fromDate.isNotEmpty) {
        poWhere.add('date >= ?');
        poArgs.add(fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        poWhere.add('date <= ?');
        poArgs.add(toDate);
      }
      final poRows = await db.query('purchase_orders',
          where: poWhere.join(' AND '), whereArgs: poArgs,
          orderBy: 'date DESC, id DESC', limit: limit);
      for (final r in poRows) {
        final amt = (r['total'] as num?)?.toInt() ?? 0;
        list.add(TransactionRecord(
          id: r['id'] as int,
          type: TransactionType.purchaseOrder,
          number: r['number'] as String? ?? 'PO-${r['id']}',
          partyName: r['supplier_name'] as String?,
          date: (r['date'] as String?) ?? todayIso(),
          amount: amt,
          paidAmount: 0,
          outstandingAmount: amt,
          status: (r['status'] as String?) ?? 'Draft',
          paymentMode: null,
          notes: r['notes'] as String?,
          refId: r['id'] as int,
        ));
      }
    }

    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });

    if (limit != null && list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  Future<List<BillProfitRecord>> billWiseProfitReport(
    int businessId, {
    String? fromDate,
    String? toDate,
  }) async {
    final db = await _database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];
    if (fromDate != null && fromDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(toDate);
    }

    final invoiceRows = await db.query(
      'invoices',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );

    final results = <BillProfitRecord>[];

    for (final inv in invoiceRows) {
      final invId = inv['id'] as int;
      final number = inv['number'] as String? ?? 'INV-$invId';
      final customerName = inv['customer_name'] as String? ?? 'Walk-in Customer';
      final customerId = inv['customer_id'] as int?;
      final date = inv['date'] as String? ?? '';
      final taxable = (inv['taxable'] as num?)?.toInt() ?? 0;
      final total = (inv['total'] as num?)?.toInt() ?? 0;

      final itemRows = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invId],
      );

      int calculatedCogs = 0;
      final items = <BillProfitItemRecord>[];

      for (final it in itemRows) {
        final prodId = it['product_id'] as int?;
        final name = it['name'] as String? ?? 'Product';
        final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
        final price = (it['price'] as num?)?.toInt() ?? 0;
        final itemTaxable = (it['taxable'] as num?)?.toInt() ?? (price * qty).round();

        int purchasePrice = 0;
        String unit = 'pc';
        if (prodId != null) {
          final pRows = await db.query('products', where: 'id = ?', whereArgs: [prodId], limit: 1);
          if (pRows.isNotEmpty) {
            final p = pRows.first;
            final pp = (p['purchase_price'] as num?)?.toInt() ?? 0;
            final ca = (p['cost_average'] as num?)?.toInt() ?? 0;
            purchasePrice = pp > 0 ? pp : ca;
            unit = p['unit'] as String? ?? 'pc';
          }
        }

        final lineCost = (purchasePrice * qty).round();
        calculatedCogs += lineCost;
        final lineProfit = itemTaxable - lineCost;
        final lineMargin = itemTaxable > 0 ? (lineProfit / itemTaxable) * 100 : 0.0;

        items.add(BillProfitItemRecord(
          name: name,
          quantity: qty,
          unit: unit,
          salePrice: price,
          costPrice: purchasePrice,
          taxable: itemTaxable,
          totalCost: lineCost,
          profit: lineProfit,
          margin: lineMargin,
        ));
      }

      int finalCogs = calculatedCogs;
      if (finalCogs == 0) {
        final ledgerCogs = await db.rawQuery(
          "SELECT COALESCE(SUM(debit), 0) AS c FROM ledger WHERE business_id = ? AND ref_type = 'invoice' AND ref_id = ? AND account = 'cogs'",
          [businessId, invId],
        );
        if (ledgerCogs.isNotEmpty) {
          final lc = (ledgerCogs.first['c'] as num).toInt();
          if (lc > 0) finalCogs = lc;
        }
      }

      final revenueBase = taxable > 0 ? taxable : total;
      final profit = revenueBase - finalCogs;
      final margin = revenueBase > 0 ? (profit / revenueBase) * 100 : 0.0;

      results.add(BillProfitRecord(
        invoiceId: invId,
        number: number,
        customerName: customerName,
        customerId: customerId,
        date: date,
        total: total,
        taxable: taxable,
        cogs: finalCogs,
        profit: profit,
        margin: margin,
        items: items,
      ));
    }

    return results;
  }

  Future<SalesSummaryReportData> salesSummaryReport(
    int businessId, {
    String? fromDate,
    String? toDate,
  }) async {
    final db = await _database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];
    if (fromDate != null && fromDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(toDate);
    }

    final invoiceRows = await db.query(
      'invoices',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );

    int totalGross = 0;
    int totalTaxable = 0;
    int totalCgst = 0;
    int totalSgst = 0;
    int totalIgst = 0;
    int totalPaid = 0;
    final paymentModes = <String, int>{};
    final invoices = <Invoice>[];

    for (final row in invoiceRows) {
      final inv = Invoice.fromMap(row);
      invoices.add(inv);
      totalGross += inv.total;
      totalTaxable += inv.taxable;
      totalCgst += inv.cgst;
      totalSgst += inv.sgst;
      totalIgst += inv.igst;
      totalPaid += inv.amountPaid;

      final mode = inv.paymentMode?.trim();
      final effectiveMode = (mode != null && mode.isNotEmpty) ? mode : 'Credit';
      paymentModes[effectiveMode] = (paymentModes[effectiveMode] ?? 0) + inv.total;
    }

    final totalTax = totalCgst + totalSgst + totalIgst;
    final totalDue = totalGross - totalPaid;

    return SalesSummaryReportData(
      totalGrossSales: totalGross,
      totalTaxable: totalTaxable,
      totalTax: totalTax,
      totalCgst: totalCgst,
      totalSgst: totalSgst,
      totalIgst: totalIgst,
      totalPaid: totalPaid,
      totalDue: totalDue > 0 ? totalDue : 0,
      invoiceCount: invoices.length,
      paymentModes: paymentModes,
      invoices: invoices,
    );
  }

  Future<List<StaffMember>> staffMembers(int businessId, {bool includeInactive = false}) async {
    final db = await _database;
    final where = 'business_id = ?${includeInactive ? '' : ' AND is_active = 1'}';
    final rows = await db.query('staff_members', where: where, whereArgs: [businessId], orderBy: 'id ASC');
    return rows.map(StaffMember.fromMap).toList();
  }

  Future<int> upsertStaffMember(StaffMember staff) async {
    final db = await _database;
    final map = staff.toMap();
    if (staff.id == null) {
      final id = await db.insert('staff_members', map);
      await _audit(staff.businessId, action: 'create', entity: 'staff', entityId: id, after: map);
      await _enqueueSync(staff.businessId, entity: 'staff', entityId: id, op: 'create', payload: jsonEncode(map));
      return id;
    }
    await db.update('staff_members', map, where: 'id = ? AND business_id = ?', whereArgs: [staff.id, staff.businessId]);
    await _audit(staff.businessId, action: 'update', entity: 'staff', entityId: staff.id, after: map);
    await _enqueueSync(staff.businessId, entity: 'staff', entityId: staff.id!, op: 'upsert', payload: jsonEncode(map));
    return staff.id!;
  }

  Future<void> deleteStaffMember(int businessId, int id) async {
    final db = await _database;
    await db.update('staff_members', {'is_active': 0}, where: 'id = ? AND business_id = ?', whereArgs: [id, businessId]);
    await _audit(businessId, action: 'delete', entity: 'staff', entityId: id);
    await _enqueueSync(businessId, entity: 'staff', entityId: id, op: 'delete');
  }

  Future<InvoiceCustomizationSettings> getInvoiceCustomizationSettings(int businessId) async {
    final db = await _database;
    final rows = await db.query(
      'invoice_customization_settings',
      where: 'business_id = ?',
      whereArgs: [businessId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return InvoiceCustomizationSettings.fromMap(rows.first);
    }
    return InvoiceCustomizationSettings(businessId: businessId);
  }

  Future<void> saveInvoiceCustomizationSettings(InvoiceCustomizationSettings settings) async {
    final db = await _database;
    final map = settings.toMap();
    await db.insert(
      'invoice_customization_settings',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _audit(
      settings.businessId,
      action: 'update',
      entity: 'invoice_customization_settings',
      entityId: 0,
      after: map,
    );
  }

  Future<CashflowReportData> getCashflowReport(
    int businessId, {
    String accountType = 'all',
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _database;
    final startIso = isoDate(startDate);
    final endIso = isoDate(endDate);

    String accountClause;
    if (accountType == 'cash') {
      accountClause = "l.account = 'cash'";
    } else if (accountType == 'bank') {
      accountClause = "(l.account = 'bank' OR l.account LIKE 'bank:%')";
    } else {
      accountClause = "(l.account = 'cash' OR l.account = 'bank' OR l.account LIKE 'bank:%')";
    }

    final openingRows = await db.rawQuery(
      'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS opening '
      'FROM ledger l '
      'WHERE l.business_id = ? AND $accountClause AND l.date < ?',
      [businessId, startIso],
    );
    final openingCash = openingRows.isEmpty ? 0 : (openingRows.first['opening'] as num).toInt();

    final rows = await db.rawQuery('''
      SELECT
        l.id,
        l.date,
        l.account,
        l.debit,
        l.credit,
        l.ref_type,
        l.ref_id,
        l.note,
        p.party_name AS payment_party_name,
        p.type AS payment_type,
        p.mode AS payment_mode,
        e.vendor AS expense_vendor,
        e.category AS expense_category,
        inv.customer_name AS invoice_customer_name,
        ba.bank_name AS bank_name
      FROM ledger l
      LEFT JOIN payments p ON (l.ref_type = 'payment' AND l.ref_id = p.id)
      LEFT JOIN expenses e ON (l.ref_type = 'expense' AND l.ref_id = e.id)
      LEFT JOIN invoices inv ON (l.ref_type = 'invoice' AND l.ref_id = inv.id)
      LEFT JOIN bank_accounts ba ON (l.account = ('bank:' || ba.id))
      WHERE l.business_id = ?
        AND $accountClause
        AND l.date >= ? AND l.date <= ?
      ORDER BY l.date DESC, l.id DESC
    ''', [businessId, startIso, endIso]);

    final moneyInList = <CashflowEntry>[];
    final moneyOutList = <CashflowEntry>[];
    int totalMoneyIn = 0;
    int totalMoneyOut = 0;

    for (final r in rows) {
      final debit = (r['debit'] as num?)?.toInt() ?? 0;
      final credit = (r['credit'] as num?)?.toInt() ?? 0;
      if (debit == 0 && credit == 0) continue;

      final isMoneyIn = debit > 0;
      final amount = isMoneyIn ? debit : credit;
      final refType = r['ref_type'] as String?;
      final note = r['note'] as String?;
      final paymentParty = (r['payment_party_name'] as String?)?.trim();
      final invoiceCust = (r['invoice_customer_name'] as String?)?.trim();
      final expenseVendor = (r['expense_vendor'] as String?)?.trim();
      final expenseCat = (r['expense_category'] as String?)?.trim();
      final bankName = (r['bank_name'] as String?)?.trim();
      final accountStr = r['account'] as String? ?? 'cash';
      final paymentType = r['payment_type'] as String?;

      String partyName;
      if (paymentParty != null && paymentParty.isNotEmpty) {
        partyName = paymentParty;
      } else if (invoiceCust != null && invoiceCust.isNotEmpty) {
        partyName = invoiceCust;
      } else if (expenseVendor != null && expenseVendor.isNotEmpty) {
        partyName = expenseVendor;
      } else if (refType == 'opening' || (note != null && note.toLowerCase().contains('opening balance'))) {
        partyName = 'Opening Balance';
      } else if (note != null && note.trim().isNotEmpty) {
        partyName = note.trim();
      } else if (expenseCat != null && expenseCat.isNotEmpty) {
        partyName = expenseCat;
      } else {
        partyName = accountStr == 'cash' ? 'Cash in Hand' : (bankName ?? 'Bank Account');
      }

      String txType;
      if (refType == 'invoice') {
        txType = 'Sales';
      } else if (refType == 'purchase' || expenseCat == 'Purchase') {
        txType = 'Purchase';
      } else if (refType == 'expense' || paymentType == 'expense') {
        txType = 'Expense';
      } else if (refType == 'payment') {
        if (paymentType == 'in') {
          txType = 'Sales';
        } else if (paymentType == 'out') {
          txType = 'Payment Out';
        } else {
          txType = isMoneyIn ? 'Sales' : 'Payment Out';
        }
      } else if (refType == 'transfer' || (note != null && note.toLowerCase().contains('transfer'))) {
        txType = 'Transfer';
      } else if (refType == 'opening') {
        txType = 'Opening Balance';
      } else {
        txType = isMoneyIn ? 'Sales' : 'Expense';
      }

      final displayAccount = accountStr == 'cash'
          ? 'Cash'
          : (bankName != null && bankName.isNotEmpty ? bankName : 'Bank');

      final entry = CashflowEntry(
        id: (r['id'] as num).toInt(),
        date: r['date'] as String? ?? todayIso(),
        partyName: partyName,
        transactionType: txType,
        amount: amount,
        isMoneyIn: isMoneyIn,
        account: accountStr,
        accountDisplayName: displayAccount,
        note: note,
        refType: refType,
        refId: (r['ref_id'] as num?)?.toInt(),
      );

      if (isMoneyIn) {
        moneyInList.add(entry);
        totalMoneyIn += amount;
      } else {
        moneyOutList.add(entry);
        totalMoneyOut += amount;
      }
    }

    final closingCash = openingCash + totalMoneyIn - totalMoneyOut;

    return CashflowReportData(
      openingCash: openingCash,
      moneyIn: totalMoneyIn,
      moneyOut: totalMoneyOut,
      closingCash: closingCash,
      moneyInList: moneyInList,
      moneyOutList: moneyOutList,
    );
  }
}

extension on List<Map<String, Object?>> {
  Map<String, Object?>? get firstOrNull => isEmpty ? null : first;
}