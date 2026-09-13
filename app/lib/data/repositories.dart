import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/billing_engine.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/session.dart';
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
      'idempotency_key': '${session.mobile ?? 'device'}#$entity#$entityId#$op',
      'status': 'pending',
      'attempts': 0,
      'created_at': timestampNow(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<String> nextInvoiceNumber(int businessId, String prefix) async {
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.query('businesses',
          columns: ['invoice_sequence'], where: 'id = ?', whereArgs: [businessId]);
      final current = (rows.isNotEmpty ? rows.first['invoice_sequence'] as int : 0);
      final next = current + 1;
      await txn.update('businesses', {'invoice_sequence': next},
          where: 'id = ?', whereArgs: [businessId]);
      return InvoiceNumbering.format(prefix, next);
    });
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

  Future<List<Invoice>> invoicesForParty(int businessId, String partyType, int partyId) async {
    final db = await _database;
    final column = partyType == 'customer' ? 'customer_id' : 'party_id';
    final table = partyType == 'customer' ? 'invoices' : 'payments';
    final rows = await db.query(table,
        where: 'business_id = ? AND $column = ?', whereArgs: [businessId, partyId],
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
    final beforeStock = before.isNotEmpty ? (before.first['stock'] as int? ?? 0) : 0;
    await db.update('products', map, where: 'id = ?', whereArgs: [product.id]);
    if (product.stock != beforeStock) {
      await db.insert('stock_moves', {
        'business_id': businessId,
        'product_id': product.id,
        'change_qty': product.stock - beforeStock,
        'qty_after': product.stock,
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
      {String? refType, int? refId}) async {
    final db = await _database;
    final businessId = session.businessId;
    if (businessId == null) return;
    final newQty = product.stock + change;
    final success = await db.update(
      'products',
      {'stock': newQty},
      where: 'id = ?', whereArgs: [product.id],
    );
    if (success == 0) return;
    await db.insert('stock_moves', {
      'business_id': businessId,
      'product_id': product.id,
      'change_qty': change,
      'qty_after': newQty,
      'move_type': moveType,
      'ref_type': refType,
      'ref_id': refId,
      'date': todayIso(),
    });
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
  }) async {
    final db = await _database;
    final invoiceId = await db.transaction<int>((txn) async {
      final total = quote.total.paise;
      final status = resolveInvoiceStatus(total: total, amountPaid: amountPaid);
      final invoiceId = await txn.insert('invoices', {
        'business_id': businessId,
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
      });

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
        });
      }

      final bizRows = await txn.query('businesses',
          columns: ['allow_negative_stock'], where: 'id = ?', whereArgs: [businessId], limit: 1);
      final allowNegative = (bizRows.isEmpty ? 0 : (bizRows.first['allow_negative_stock'] as int? ?? 0)) == 1;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.productId == null) continue;
        final product = await txn.query('products',
            where: 'id = ?', whereArgs: [line.productId], limit: 1);
        if (product.isEmpty) continue;
        final current = (product.first['stock'] as num?)?.toDouble() ?? 0;
        final next = current - line.quantity;
        if (!allowNegative && next < 0) {
          throw StateError('Not enough stock for ${line.name} — only ${_qty(current)} in stock');
        }
        await txn.update('products', {'stock': next},
            where: 'id = ?', whereArgs: [line.productId]);
        await txn.insert('stock_moves', {
          'business_id': businessId,
          'product_id': line.productId,
          'change_qty': -line.quantity,
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
      return invoiceId;
    });
    await _audit(businessId,
        action: 'create', entity: 'invoice', entityId: invoiceId, after: {'number': number, 'total': quote.total.paise});
    await _enqueueSync(businessId, entity: 'invoice', entityId: invoiceId, op: 'create', payload: number);
    return invoiceId;
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
  }) async {
    final db = await _database;
    final purchaseId = await db.transaction<int>((txn) async {
      final seq = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM expenses WHERE business_id = ?', [businessId]);
      final number = 'PUR-${(seq.first['c'] as int) + 1}';
      final purchaseId = await txn.insert('expenses', {
        'business_id': businessId,
        'category': 'Purchase',
        'amount': 0,
        'mode': paymentMode ?? 'Credit',
        'date': date,
        'description': notes == null || notes.isEmpty
            ? 'Purchase from $supplierName'
            : 'Purchase from $supplierName — $notes',
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
          'amount': amountPaid,
          'mode': paymentMode ?? 'Cash',
          'date': date,
          'type': 'out',
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
    await _enqueueSync(businessId, entity: 'expense', entityId: id, op: 'create');
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
    await _enqueueSync(businessId, entity: 'payment', entityId: id, op: 'create');
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
    final id = await db.transaction<int>((txn) async {
      final qId = await txn.insert('quotations', quote.toMap()..['business_id'] = quote.businessId ?? session.businessId);
      for (final line in quote.lines) {
        await txn.insert('quotation_items', line.toMap()..['quotation_id'] = qId);
      }
      return qId;
    });
    await _audit(quote.businessId ?? session.businessId!,
        action: 'create', entity: 'quotation', entityId: id);
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

  Future<int> finalizeReturn(TransactionReturn ret) async {
    final db = await _database;
    final id = await db.transaction<int>((txn) async {
      final bizId = ret.businessId ?? session.businessId!;
      final retId = await txn.insert('returns', ret.toMap()..['business_id'] = bizId);

      for (final line in ret.lines) {
        await txn.insert('return_items', line.toMap()..['return_id'] = retId);

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

  Future<List<LedgerEntry>> partyLedger(int businessId, String partyType, int partyId) async {
    final db = await _database;
    final suffix = partyType == 'customer' ? 'customer:$partyId' : 'supplier:$partyId';
    final rows = await db.query('ledger',
        where: 'business_id = ? AND account = ?', whereArgs: [businessId, suffix],
        orderBy: 'date ASC, id ASC');
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<List<StockMove>> stockMoves(int businessId, int productId) async {
    final db = await _database;
    final rows = await db.query('stock_moves',
        where: 'business_id = ? AND product_id = ?', whereArgs: [businessId, productId],
        orderBy: 'date ASC, id ASC');
    return rows.map(StockMove.fromMap).toList();
  }

  Future<List<AuditEntry>> auditLog(int businessId) async {
    final db = await _database;
    final rows = await db.query('audit_log',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'id DESC', limit: 200);
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

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);

  Future<Map<String, int>> dashboardTotals(int businessId, {DateTime? day}) async {
    final date = isoDate(day ?? DateTime.now());
    final db = await _database;
    Future<int> sumOf(String table, String column, String whereClause, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column), 0) AS s FROM $table WHERE $whereClause', args);
      return rows.isEmpty ? 0 : (rows.first['s'] as num).toInt();
    }

    final salesToday = await sumOf('invoices', 'total', 'business_id = ? AND date = ?', [businessId, date]);
    final taxableToday = await sumOf('invoices', 'taxable', 'business_id = ? AND date = ?', [businessId, date]);
    final returnsToday = await sumOf('returns', 'taxable', "business_id = ? AND date = ? AND party_type = 'customer'", [businessId, date]);
    final purchasesToday = await sumOf('expenses', 'amount', "business_id = ? AND date = ? AND category = 'Purchase'", [businessId, date]);
    final expensesToday = await sumOf('expenses', 'amount', "business_id = ? AND date = ? AND category != 'Purchase'", [businessId, date]);
    final cogsToday = await sumOf('ledger', 'debit', "business_id = ? AND date = ? AND account = 'cogs'", [businessId, date]);
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

  Future<List<Invoice>> overdueOrUnpaidInvoices(int businessId) async {
    final db = await _database;
    final rows = await db.query('invoices',
        where: "business_id = ? AND status != 'Paid'", whereArgs: [businessId],
        orderBy: 'date ASC', limit: 30);
    return rows.map(Invoice.fromMap).toList();
  }

  Future<Map<String, int>> periodTotals(int businessId, String fromDate) async {
    final db = await _database;
    Future<int> sumOf(String table, String column, String whereClause, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column), 0) AS s FROM $table WHERE $whereClause', args);
      return rows.isEmpty ? 0 : (rows.first['s'] as num).toInt();
    }

    final sales = await sumOf('invoices', 'total', 'business_id = ? AND date >= ?', [businessId, fromDate]);
    final taxable = await sumOf('invoices', 'taxable', 'business_id = ? AND date >= ?', [businessId, fromDate]);
    final purchases = await sumOf('expenses', 'amount', "business_id = ? AND date >= ? AND category = 'Purchase'", [businessId, fromDate]);
    final expenses = await sumOf('expenses', 'amount', "business_id = ? AND date >= ? AND category != 'Purchase'", [businessId, fromDate]);
    final cogs = await sumOf('ledger', 'debit', "business_id = ? AND date >= ? AND account = 'cogs'", [businessId, fromDate]);
    final collected = await sumOf('payments', 'amount', "business_id = ? AND date >= ? AND type = 'in'", [businessId, fromDate]);
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

  Future<List<(String, int)>> expenseBreakdown(int businessId, String fromDate) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT category, SUM(amount) AS s FROM expenses WHERE business_id = ? AND date >= ? AND category != ? '
        'GROUP BY category ORDER BY s DESC',
        [businessId, fromDate, 'Purchase']);
    return rows
        .map((r) => (r['category'] as String? ?? 'Other', (r['s'] as num).toInt()))
        .toList();
  }

  Future<List<(String, int, int)>> bestProducts(int businessId, String fromDate, {int limit = 5}) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT invoice_items.name AS name, SUM(invoice_items.quantity) AS qty, '
        'SUM(invoice_items.taxable) AS rev FROM invoice_items '
        'JOIN invoices ON invoices.id = invoice_items.invoice_id '
        'WHERE invoices.business_id = ? AND invoices.date >= ? '
        'GROUP BY name ORDER BY qty DESC LIMIT ?',
        [businessId, fromDate, limit]);
    return rows
        .map((r) => (
              r['name'] as String? ?? '',
              (r['qty'] as num).toInt(),
              (r['rev'] as num).toInt(),
            ))
        .toList();
  }
}

extension on List<Map<String, Object?>> {
  Map<String, Object?>? get firstOrNull => isEmpty ? null : first;
}