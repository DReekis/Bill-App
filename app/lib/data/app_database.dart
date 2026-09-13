import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  bool get _supportsSqlite =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<Database> get database async {
    if (_supportsSqlite) return _connect();
    return _connectFfi();
  }

  Future<Database> _connect() async {
    return _db ??= await openDatabase(
      '${await getDatabasesPath()}/ledger_pilot.db',
      version: 1,
      onCreate: createSchema,
    );
  }

  Future<Database> _connectFfi() async {
    if (_db != null) return _db!;
    ffi.sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    _db = await ffi.databaseFactoryFfi.openDatabase(
      '${dir.path}/ledger_pilot.db',
      options: ffi.OpenDatabaseOptions(version: 1, onCreate: createSchema),
    );
    return _db!;
  }

  /// Lets tests drive the real repository against an in-memory database.
  @visibleForTesting
  void useDatabaseForTesting(Database db) => _db = db;

  Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE businesses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_name TEXT,
        gstin TEXT,
        state TEXT,
        city TEXT,
        industry TEXT,
        invoice_prefix TEXT DEFAULT 'INV',
        tax_registered INTEGER DEFAULT 0,
        allow_negative_stock INTEGER DEFAULT 0,
        invoice_sequence INTEGER DEFAULT 0,
        fy_start TEXT DEFAULT '2026-04-01',
        currency TEXT DEFAULT 'INR'
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        billing_address TEXT,
        shipping_address TEXT,
        gstin TEXT,
        state TEXT,
        opening_balance INTEGER DEFAULT 0,
        credit_limit INTEGER DEFAULT 0,
        payment_terms INTEGER DEFAULT 0,
        notes TEXT,
        inactive INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        gstin TEXT,
        state TEXT,
        opening_balance INTEGER DEFAULT 0,
        credit_period INTEGER DEFAULT 0,
        notes TEXT,
        inactive INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        name TEXT NOT NULL,
        sku TEXT,
        category TEXT,
        hsn TEXT,
        barcode TEXT,
        unit TEXT DEFAULT 'pc',
        gst_rate INTEGER DEFAULT 0,
        purchase_price INTEGER DEFAULT 0,
        sale_price INTEGER DEFAULT 0,
        wholesale_price INTEGER DEFAULT 0,
        mrp INTEGER DEFAULT 0,
        stock INTEGER DEFAULT 0,
        cost_average INTEGER DEFAULT 0,
        low_stock_threshold INTEGER DEFAULT 5,
        tax_included INTEGER DEFAULT 0,
        inactive INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        customer_id INTEGER,
        customer_name TEXT,
        date TEXT NOT NULL,
        due_date TEXT,
        gst_type TEXT DEFAULT 'gst',
        subtotal INTEGER DEFAULT 0,
        discount INTEGER DEFAULT 0,
        discount_type TEXT,
        discount_rate REAL DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        cgst INTEGER DEFAULT 0,
        sgst INTEGER DEFAULT 0,
        igst INTEGER DEFAULT 0,
        cess INTEGER DEFAULT 0,
        round_off INTEGER DEFAULT 0,
        total INTEGER DEFAULT 0,
        amount_paid INTEGER DEFAULT 0,
        payment_mode TEXT,
        status TEXT DEFAULT 'Finalized',
        notes TEXT
      )
    ''');

    await db.execute(
        'CREATE UNIQUE INDEX idx_invoices_number\n  ON invoices (business_id, number)');

    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        hsn TEXT,
        gst_rate INTEGER DEFAULT 0,
        quantity REAL DEFAULT 0,
        price INTEGER DEFAULT 0,
        discount INTEGER DEFAULT 0,
        discount_percent REAL DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        tax INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        product_id INTEGER NOT NULL,
        change_qty REAL DEFAULT 0,
        qty_after REAL DEFAULT 0,
        move_type TEXT,
        ref_type TEXT,
        ref_id INTEGER,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        party_type TEXT,
        party_id INTEGER,
        party_name TEXT,
        invoice_id INTEGER,
        invoice_number TEXT,
        amount INTEGER DEFAULT 0,
        mode TEXT,
        date TEXT,
        reference TEXT,
        type TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        category TEXT,
        amount INTEGER DEFAULT 0,
        mode TEXT,
        date TEXT,
        description TEXT,
        vendor TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        date TEXT,
        account TEXT,
        debit INTEGER DEFAULT 0,
        credit INTEGER DEFAULT 0,
        ref_type TEXT,
        ref_id INTEGER,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        actor TEXT DEFAULT 'owner',
        action TEXT,
        entity TEXT,
        entity_id INTEGER,
        before TEXT,
        after TEXT,
        timestamp TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE quotations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        customer_id INTEGER,
        customer_name TEXT,
        date TEXT NOT NULL,
        expiry_date TEXT,
        gst_type TEXT DEFAULT 'gst',
        subtotal INTEGER DEFAULT 0,
        discount INTEGER DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        cgst INTEGER DEFAULT 0,
        sgst INTEGER DEFAULT 0,
        igst INTEGER DEFAULT 0,
        total INTEGER DEFAULT 0,
        status TEXT DEFAULT 'Open',
        notes TEXT
      )
    ''');

    await db.execute(
        'CREATE UNIQUE INDEX idx_quotations_number ON quotations (business_id, number)');

    await db.execute('''
      CREATE TABLE quotation_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quotation_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        hsn TEXT,
        gst_rate INTEGER DEFAULT 0,
        quantity REAL DEFAULT 0,
        price INTEGER DEFAULT 0,
        discount INTEGER DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        tax INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        invoice_id INTEGER,
        party_id INTEGER,
        party_name TEXT,
        party_type TEXT,
        date TEXT NOT NULL,
        subtotal INTEGER DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        tax INTEGER DEFAULT 0,
        total INTEGER DEFAULT 0,
        reason TEXT,
        status TEXT DEFAULT 'Finalized'
      )
    ''');

    await db.execute('''
      CREATE TABLE return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        hsn TEXT,
        gst_rate INTEGER DEFAULT 0,
        quantity REAL DEFAULT 0,
        price INTEGER DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        tax INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        entity TEXT,
        entity_id INTEGER,
        op TEXT,
        payload TEXT,
        idempotency_key TEXT UNIQUE,
        status TEXT DEFAULT 'pending',
        attempts INTEGER DEFAULT 0,
        last_error TEXT,
        created_at TEXT,
        synced_at TEXT
      )
    ''');
  }

  void resetConnection() {
    _db?.close();
    _db = null;
  }

  Future<File> databaseFile() async {
    final db = await database;
    return File(db.path);
  }

  Future<File> tempExportFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/ledger_pilot_backup.db');
  }

  Future<void> reset() async {
    final db = await database;
    await db.delete('sync_queue');
    await db.delete('ledger');
    await db.delete('invoice_items');
    await db.delete('invoices');
    await db.delete('stock_moves');
    await db.delete('payments');
    await db.delete('expenses');
    await db.delete('products');
    await db.delete('customers');
    await db.delete('suppliers');
    await db.delete('audit_log');
    await db.delete('quotations');
    await db.delete('quotation_items');
    await db.delete('returns');
    await db.delete('return_items');
    await db.delete('businesses');
  }
}

Future<void> copyDatabaseFile(Database db, String destPath) async {
  final source = db.path;
  AppDatabase.instance.resetConnection();
  await File(source).copy(destPath);
}