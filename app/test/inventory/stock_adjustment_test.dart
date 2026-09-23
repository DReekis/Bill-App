import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);
    businessId = await repo.createBusiness(Business(
      name: 'Stock Test Store',
      state: 'Maharashtra',
      taxRegistered: true,
    ));
    repo.session.businessId = businessId;
  });

  tearDown(() async {
    await db.close();
  });

  test('Additive Stock Adjustment: 30 in stock + 20 added = 50 total', () async {
    // 1. Initial product with 30 units
    final productId = await repo.upsertProduct(
      Product(
        name: 'Basmati Rice 1kg',
        sku: 'RICE-1KG',
        salePrice: 12000,
        purchasePrice: 9000,
        stock: 30,
      ),
      businessIdOverride: businessId,
    );

    final initialProducts = await repo.products(businessId);
    final product = initialProducts.firstWhere((p) => p.id == productId);
    expect(product.stock, 30);

    // 2. Perform additive stock adjustment: add 20 units
    // User had 30 units and adds 20 more -> must be 50, NOT 20.
    const addQuantity = 20.0;
    await repo.adjustStock(
      product,
      addQuantity,
      'adjustment_in',
      reason: 'Stock Received',
    );

    // 3. Verify in-memory product is updated
    expect(product.stock, 50);

    // 4. Verify database persistence
    final refreshedProducts = await repo.products(businessId);
    final updatedProduct = refreshedProducts.firstWhere((p) => p.id == productId);
    expect(updatedProduct.stock, 50);

    // 5. Verify stock move audit record
    final moves = await repo.stockMoves(businessId, productId);
    expect(moves.isNotEmpty, true);

    final latestMove = moves.last;
    expect(latestMove.changeQty, 20.0);
    expect(latestMove.qtyAfter, 50.0);
    expect(latestMove.moveType, contains('Stock Received'));
  });

  test('Subtractive Stock Adjustment: 30 in stock - 5 reduced = 25 total', () async {
    final productId = await repo.upsertProduct(
      Product(
        name: 'Sunflower Oil 1L',
        sku: 'OIL-1L',
        salePrice: 15000,
        purchasePrice: 12000,
        stock: 30,
      ),
      businessIdOverride: businessId,
    );

    final products = await repo.products(businessId);
    final product = products.firstWhere((p) => p.id == productId);
    expect(product.stock, 30);

    // Deduct 5 units (e.g. damaged stock)
    const reduceQuantity = -5.0;
    await repo.adjustStock(
      product,
      reduceQuantity,
      'adjustment_out',
      reason: 'Damaged / Broken',
    );

    expect(product.stock, 25);

    final refreshed = await repo.products(businessId);
    expect(refreshed.firstWhere((p) => p.id == productId).stock, 25);

    final moves = await repo.stockMoves(businessId, productId);
    final latestMove = moves.last;
    expect(latestMove.changeQty, -5.0);
    expect(latestMove.qtyAfter, 25.0);
    expect(latestMove.moveType, contains('Damaged'));
  });

  test('Set Total Stock Count: 30 in stock overridden to 50 via audit count', () async {
    final productId = await repo.upsertProduct(
      Product(
        name: 'Wheat Flour 5kg',
        sku: 'ATTA-5KG',
        salePrice: 24000,
        purchasePrice: 19000,
        stock: 30,
      ),
      businessIdOverride: businessId,
    );

    final products = await repo.products(businessId);
    final product = products.firstWhere((p) => p.id == productId);

    // During physical audit, physical count is 50 units (change = 50 - 30 = +20)
    const targetCount = 50.0;
    final change = targetCount - product.stock;
    await repo.adjustStock(
      product,
      change,
      'stock_audit',
      reason: 'Physical Audit',
    );

    expect(product.stock, 50);

    final refreshed = await repo.products(businessId);
    expect(refreshed.firstWhere((p) => p.id == productId).stock, 50);

    final moves = await repo.stockMoves(businessId, productId);
    final latestMove = moves.last;
    expect(latestMove.changeQty, 20.0);
    expect(latestMove.qtyAfter, 50.0);
    expect(latestMove.moveType, contains('Physical Audit'));
  });

  test('upsertProduct safely handles additive stock updates without type cast failure', () async {
    final productId = await repo.upsertProduct(
      Product(
        name: 'Sugar 1kg',
        sku: 'SUGAR-1KG',
        salePrice: 4500,
        purchasePrice: 3800,
        stock: 30,
      ),
      businessIdOverride: businessId,
    );

    // Simulate product edit where user added 20 units (30 + 20 = 50)
    await repo.upsertProduct(
      Product(
        id: productId,
        name: 'Sugar 1kg Premium',
        sku: 'SUGAR-1KG',
        salePrice: 4800,
        purchasePrice: 3800,
        stock: 50,
      ),
      businessIdOverride: businessId,
    );

    final refreshed = await repo.products(businessId);
    final updated = refreshed.firstWhere((p) => p.id == productId);
    expect(updated.stock, 50);
    expect(updated.name, 'Sugar 1kg Premium');

    final moves = await repo.stockMoves(businessId, productId);
    final latestMove = moves.last;
    expect(latestMove.changeQty, 20.0);
    expect(latestMove.qtyAfter, 50.0);
    expect(latestMove.moveType, 'adjustment');
  });
}
