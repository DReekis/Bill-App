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
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (kIsWeb) return _connectWeb();
    if (_supportsSqlite) return _connect();
    return _connectFfi();
  }

  Future<Database> _connectWeb() async {
    if (_db != null) return _db!;
    ffi.sqfliteFfiInit();
    _db = await ffi.databaseFactoryFfi.openDatabase(
      ffi.inMemoryDatabasePath,
      options: ffi.OpenDatabaseOptions(version: 1, onCreate: createSchema),
    );
    return _db!;
  }

  Future<Database> _connect() async {
    return _db ??= await openDatabase(
      '${await getDatabasesPath()}/ledger_pilot.db',
      version: 1,
      onCreate: createSchema,
      onOpen: _migrate,
    );
  }

  Future<Database> _connectFfi() async {
    if (_db != null) return _db!;
    ffi.sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    _db = await ffi.databaseFactoryFfi.openDatabase(
      '${dir.path}/ledger_pilot.db',
      options: ffi.OpenDatabaseOptions(version: 1, onCreate: createSchema, onOpen: _migrate),
    );
    return _db!;
  }

  static Future<void> _migrate(Database db) async {
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN upi_id TEXT;');
    } catch (_) {}
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cheques (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_id INTEGER NOT NULL,
          cheque_number TEXT NOT NULL,
          bank_name TEXT,
          bank_account_id INTEGER,
          party_type TEXT,
          party_id INTEGER,
          party_name TEXT,
          amount INTEGER DEFAULT 0,
          date TEXT NOT NULL,
          clearing_date TEXT,
          type TEXT NOT NULL,
          status TEXT DEFAULT 'Pending',
          bounce_reason TEXT,
          notes TEXT
        );
      ''');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE bank_accounts ADD COLUMN ifsc TEXT;');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE bank_accounts ADD COLUMN account_type TEXT DEFAULT 'Current';");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE quotations ADD COLUMN is_proforma INTEGER DEFAULT 0;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE quotation_items ADD COLUMN discount_percent REAL DEFAULT 0;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE quotation_items ADD COLUMN unit TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN invoice_phone TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN invoice_email TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN terms_sales TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN terms_quotation TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN terms_purchase TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN terms_challan TEXT;');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE businesses ADD COLUMN signature_text TEXT DEFAULT 'Authorised Signatory';");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN show_empty_signature_box INTEGER DEFAULT 1;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN show_payment_qr INTEGER DEFAULT 1;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN bank_account_id INTEGER;');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE businesses ADD COLUMN quotation_prefix TEXT DEFAULT 'EST';");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN quotation_sequence INTEGER DEFAULT 0;');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE businesses ADD COLUMN purchase_prefix TEXT DEFAULT 'PUR';");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE businesses ADD COLUMN purchase_sequence INTEGER DEFAULT 0;');
    } catch (_) {}
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
        business_phone TEXT,
        email TEXT,
        address TEXT,
        state TEXT,
        city TEXT,
        pin_code TEXT,
        country TEXT DEFAULT 'India',
        logo TEXT,
        signature TEXT,
        website TEXT,
        gstin TEXT,
        pan TEXT,
        industry TEXT,
        upi_id TEXT,
        tax_registered INTEGER DEFAULT 0,
        composition_scheme INTEGER DEFAULT 0,
        invoice_prefix TEXT DEFAULT 'INV',
        invoice_sequence INTEGER DEFAULT 0,
        allow_negative_stock INTEGER DEFAULT 0,
        fy_start TEXT DEFAULT '2026-04-01',
        currency TEXT DEFAULT 'INR',
        invoice_phone TEXT,
        invoice_email TEXT,
        terms_sales TEXT,
        terms_quotation TEXT,
        terms_purchase TEXT,
        terms_challan TEXT,
        signature_text TEXT DEFAULT 'Authorised Signatory',
        show_empty_signature_box INTEGER DEFAULT 1,
        show_payment_qr INTEGER DEFAULT 1,
        bank_account_id INTEGER,
        quotation_prefix TEXT DEFAULT 'EST',
        quotation_sequence INTEGER DEFAULT 0,
        purchase_prefix TEXT DEFAULT 'PUR',
        purchase_sequence INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        name TEXT NOT NULL,
        phone TEXT,
        whatsapp TEXT,
        email TEXT,
        billing_address TEXT,
        shipping_address TEXT,
        gstin TEXT,
        pan TEXT,
        state TEXT,
        city TEXT,
        pin TEXT,
        opening_balance INTEGER DEFAULT 0,
        credit_limit INTEGER DEFAULT 0,
        payment_terms INTEGER DEFAULT 0,
        customer_type TEXT DEFAULT 'Retail',
        customer_group TEXT,
        notes TEXT,
        loyalty_points INTEGER DEFAULT 0,
        inactive INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        name TEXT NOT NULL,
        phone TEXT,
        whatsapp TEXT,
        email TEXT,
        address TEXT,
        gstin TEXT,
        pan TEXT,
        state TEXT,
        opening_balance INTEGER DEFAULT 0,
        credit_period INTEGER DEFAULT 0,
        supplier_group TEXT,
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
        item_code TEXT,
        category TEXT,
        brand TEXT,
        hsn TEXT,
        barcode TEXT,
        unit TEXT DEFAULT 'pc',
        gst_rate INTEGER DEFAULT 0,
        purchase_price INTEGER DEFAULT 0,
        sale_price INTEGER DEFAULT 0,
        wholesale_price INTEGER DEFAULT 0,
        retail_price INTEGER DEFAULT 0,
        mrp INTEGER DEFAULT 0,
        min_selling_price INTEGER DEFAULT 0,
        stock INTEGER DEFAULT 0,
        cost_average INTEGER DEFAULT 0,
        low_stock_threshold INTEGER DEFAULT 5,
        tax_included INTEGER DEFAULT 0,
        has_batch INTEGER DEFAULT 0,
        has_serial INTEGER DEFAULT 0,
        image_path TEXT,
        description TEXT,
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
        notes TEXT,
        is_proforma INTEGER DEFAULT 0
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
        discount_percent REAL DEFAULT 0,
        taxable INTEGER DEFAULT 0,
        tax INTEGER DEFAULT 0,
        unit TEXT
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
      CREATE TABLE sales_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        customer_id INTEGER,
        customer_name TEXT,
        date TEXT NOT NULL,
        due_date TEXT,
        status TEXT DEFAULT 'Pending',
        total INTEGER DEFAULT 0,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        quantity REAL DEFAULT 0,
        price INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        supplier_id INTEGER,
        supplier_name TEXT,
        date TEXT NOT NULL,
        expected_date TEXT,
        status TEXT DEFAULT 'Draft',
        total INTEGER DEFAULT 0,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        quantity REAL DEFAULT 0,
        price INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE delivery_challans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        number TEXT NOT NULL,
        customer_id INTEGER,
        customer_name TEXT,
        date TEXT NOT NULL,
        address TEXT,
        transport_details TEXT,
        status TEXT DEFAULT 'Pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE delivery_challan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        challan_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT,
        quantity REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE bank_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        bank_name TEXT NOT NULL,
        account_name TEXT,
        account_number TEXT,
        ifsc TEXT,
        account_type TEXT DEFAULT 'Current',
        opening_balance INTEGER DEFAULT 0,
        inactive INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cheques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER NOT NULL,
        cheque_number TEXT NOT NULL,
        bank_name TEXT,
        bank_account_id INTEGER,
        party_type TEXT,
        party_id INTEGER,
        party_name TEXT,
        amount INTEGER DEFAULT 0,
        date TEXT NOT NULL,
        clearing_date TEXT,
        type TEXT NOT NULL,
        status TEXT DEFAULT 'Pending',
        bounce_reason TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE unit_conversions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        product_id INTEGER NOT NULL,
        from_unit TEXT NOT NULL,
        to_unit TEXT NOT NULL,
        multiplier REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        product_id INTEGER NOT NULL,
        batch_number TEXT NOT NULL,
        mfg_date TEXT,
        expiry_date TEXT,
        quantity REAL DEFAULT 0,
        purchase_price INTEGER DEFAULT 0,
        sale_price INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE serial_numbers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER,
        product_id INTEGER NOT NULL,
        serial_number TEXT NOT NULL,
        status TEXT DEFAULT 'Available',
        purchase_ref TEXT,
        sale_ref TEXT
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
    await db.delete('sales_orders');
    await db.delete('sales_order_items');
    await db.delete('purchase_orders');
    await db.delete('purchase_order_items');
    await db.delete('delivery_challans');
    await db.delete('delivery_challan_items');
    await db.delete('bank_accounts');
    await db.delete('cheques');
    await db.delete('unit_conversions');
    await db.delete('batches');
    await db.delete('serial_numbers');
    await db.delete('businesses');
  }
}

Future<void> copyDatabaseFile(Database db, String destPath) async {
  final source = db.path;
  AppDatabase.instance.resetConnection();
  await File(source).copy(destPath);
}