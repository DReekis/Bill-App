import 'dart:convert';

import 'package:sqflite/sqflite.dart' hide Batch;

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
      {String? refType, int? refId, String? reason}) async {
    final db = await _database;
    final businessId = session.businessId;
    if (businessId == null) return;
    final newQty = (product.stock + change).round();
    final success = await db.update(
      'products',
      {'stock': newQty},
      where: 'id = ?', whereArgs: [product.id],
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

        // Serial Validation
        if (line.serialNumber != null) {
          final sRows = await txn.query('serial_numbers', where: 'serial_number = ? AND status = ?', whereArgs: [line.serialNumber, 'Available'], limit: 1);
          if (sRows.isEmpty) throw StateError('Serial Number ${line.serialNumber} not available');
          await txn.update('serial_numbers', {'status': 'Sold', 'sale_ref': number}, where: 'serial_number = ?', whereArgs: [line.serialNumber]);
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
        await txn.update('products', {'stock': next},
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
          'invoice_number': number,
          'amount': amountPaid,
          'mode': paymentMode ?? 'Cash',
          'date': date,
          'type': 'out',
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

  Future<DeliveryChallan?> deliveryChallan(int businessId, int id) async {
    final db = await _database;
    final rows = await db.query('delivery_challans',
        where: 'business_id = ? AND id = ?', whereArgs: [businessId, id], limit: 1);
    if (rows.isEmpty) return null;
    final dc = DeliveryChallan.fromMap(rows.first);
    final items = await db.query('delivery_challan_items',
        where: 'challan_id = ?', whereArgs: [id], orderBy: 'id ASC');
    dc.lines = items.map(InvoiceLine.fromMap).toList();
    return dc;
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
          'opening_balance': (data['openingBalance'] ?? data['opening_balance'] ?? 0) is num
              ? ((data['openingBalance'] ?? data['opening_balance'] ?? 0) as num).toInt()
              : 0,
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
        final map = {
          'business_id': bizId,
          'name': name,
          'sku': sku,
          'barcode': barcode,
          'category': data['category'] as String?,
          'unit': data['unit'] as String? ?? 'pc',
          'sale_price': (data['salePrice'] ?? data['sale_price'] ?? 0) is num
              ? ((data['salePrice'] ?? data['sale_price'] ?? 0) as num).toInt()
              : 0,
          'purchase_price': (data['purchasePrice'] ?? data['purchase_price'] ?? 0) is num
              ? ((data['purchasePrice'] ?? data['purchase_price'] ?? 0) as num).toInt()
              : 0,
          'stock': ((data['stock'] as num?)?.toDouble() ?? 0).round(),
          'gst_rate': (data['gstRate'] ?? data['gst_rate'] ?? 0) is num
              ? ((data['gstRate'] ?? data['gst_rate'] ?? 0) as num).toInt()
              : 0,
        };
        if (existing.isNotEmpty) {
          await db.update('products', map,
              where: 'id = ?', whereArgs: [existing.first['id']]);
        } else {
          await db.insert('products', map);
        }
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
          'opening_balance': (data['openingBalance'] ?? data['opening_balance'] ?? 0) is num
              ? ((data['openingBalance'] ?? data['opening_balance'] ?? 0) as num).toInt()
              : 0,
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
            'opening_balance': (data['openingBalance'] ?? data['opening_balance'] ?? 0) is num
                ? ((data['openingBalance'] ?? data['opening_balance'] ?? 0) as num).toInt()
                : 0,
          };
          if (existing.isNotEmpty) {
            await db.update('bank_accounts', map,
                where: 'id = ?', whereArgs: [existing.first['id']]);
          } else {
            await db.insert('bank_accounts', map);
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

    for (final r in rows) {
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
    ];
  }

  Future<List<HsnTaxSummaryItem>> getHsnSummary(int businessId, {DateTime? from, DateTime? to}) async {
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
      SELECT 
        COALESCE(NULLIF(ii.hsn, ''), '8517') as hsn,
        ii.name as description,
        ii.gst_rate,
        SUM(ii.quantity) as qty,
        SUM(ii.taxable) as taxable,
        SUM(ii.tax) as tax
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE ${where.join(' AND ')}
      GROUP BY COALESCE(NULLIF(ii.hsn, ''), '8517'), ii.gst_rate
      ORDER BY taxable DESC
    ''';

    final rows = await db.rawQuery(query, args);
    return rows.map((r) {
      final tax = (r['tax'] as num?)?.toInt() ?? 0;
      final gstRate = (r['gst_rate'] as num?)?.toInt() ?? 0;
      final taxable = (r['taxable'] as num?)?.toInt() ?? 0;
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
        cgst: tax ~/ 2,
        sgst: tax ~/ 2,
        igst: 0,
        totalTax: tax,
        totalValue: taxable + tax,
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
        supplierGstin: '27AABCU${(9000 + expId).toString().padLeft(4, '0')}1Z5',
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

  Future<List<TransactionRecord>> recentTransactions(int businessId, {int limit = 50}) async {
    final db = await _database;
    final List<TransactionRecord> list = [];

    final invs = await db.query('invoices',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in invs) {
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: TransactionType.sale,
        number: r['number'] as String,
        partyName: r['customer_name'] as String?,
        date: r['date'] as String,
        amount: (r['total'] as num?)?.toInt() ?? 0,
        status: r['status'] as String? ?? 'Finalized',
        paymentMode: r['payment_mode'] as String?,
        notes: r['notes'] as String?,
        refId: r['id'] as int,
      ));
    }

    final exps = await db.query('expenses',
        where: 'business_id = ?', whereArgs: [businessId],
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in exps) {
      final cat = r['category'] as String? ?? 'Expense';
      final isPurchase = cat == 'Purchase';
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: isPurchase ? TransactionType.purchase : TransactionType.expense,
        number: isPurchase ? 'PUR-${r['id']}' : 'EXP-${r['id']}',
        partyName: (r['vendor'] as String?)?.isNotEmpty == true
            ? r['vendor'] as String
            : (r['category'] as String?),
        date: r['date'] as String,
        amount: (r['amount'] as num?)?.toInt() ?? 0,
        status: 'Paid',
        paymentMode: r['mode'] as String?,
        notes: r['description'] as String?,
        refId: r['id'] as int,
      ));
    }

    final pays = await db.query('payments',
        where: "business_id = ? AND invoice_id IS NULL AND (invoice_number NOT LIKE 'PUR-%' OR invoice_number IS NULL) AND (type != 'expense' OR type IS NULL)",
        whereArgs: [businessId],
        orderBy: 'date DESC, id DESC', limit: limit);
    for (final r in pays) {
      final isIn = r['type'] == 'in' || r['party_type'] == 'customer';
      list.add(TransactionRecord(
        id: r['id'] as int,
        type: isIn ? TransactionType.paymentIn : TransactionType.paymentOut,
        number: r['invoice_number'] as String? ?? 'PAY-${r['id']}',
        partyName: r['party_name'] as String?,
        date: (r['date'] as String?) ?? todayIso(),
        amount: (r['amount'] as num?)?.toInt() ?? 0,
        status: 'Completed',
        paymentMode: r['mode'] as String?,
        notes: r['notes'] as String?,
        refId: r['invoice_id'] as int?,
      ));
    }

    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });

    return list.length > limit ? list.sublist(0, limit) : list;
  }
}

extension on List<Map<String, Object?>> {
  Map<String, Object?>? get firstOrNull => isEmpty ? null : first;
}