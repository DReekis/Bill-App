import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/core/restock_notification_service.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late int supplierId;
  late int productId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.instance.createSchema,
      ),
    );
    AppDatabase.instance.useDatabaseForTesting(db);

    businessId = await repo.createBusiness(Business(
      name: 'Restock Test Store',
      ownerName: 'Restock Owner',
      taxRegistered: false,
    ));
    repo.session.businessId = businessId;

    supplierId = await repo.upsertSupplier(
      Supplier(
        name: 'Prime Suppliers',
        phone: '9876501234',
        address: 'Wholesale Market',
      ),
      businessIdOverride: businessId,
    );

    productId = await repo.upsertProduct(
      Product(
        name: 'Organic Honey 500g',
        salePrice: 30000, // ₹300
        purchasePrice: 20000, // ₹200
        stock: 10,
        unit: 'jar',
        expiryDate: '2026-06-30',
      ),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Purchase Order Restock & Price Update', () {
    test('Finalizing Purchase Order increases item stock and updates purchase price', () async {
      final po = PurchaseOrder(
        businessId: businessId,
        number: 'PO-1001',
        supplierId: supplierId,
        supplierName: 'Prime Suppliers',
        date: todayIso(),
        expectedDate: todayIso(),
        status: 'Confirmed',
        total: 37500, // 15 jars * ₹250
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Organic Honey 500g',
            quantity: 15,
            price: 25000, // New purchase price ₹250
            unit: 'jar',
          ),
        ],
      );

      final poId = await repo.finalizePurchaseOrder(po);
      expect(poId, greaterThan(0));

      final product = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      // Stock should have increased: 10 (initial) + 15 = 25
      expect(product.stock, 25);
      // Purchase price should have updated to 25000 (₹250)
      expect(product.purchasePrice, 25000);

      // Verify stock movement was recorded
      final moves = await db.query(
        'stock_moves',
        where: 'product_id = ? AND ref_type = ?',
        whereArgs: [productId, 'purchase_order'],
      );
      expect(moves.length, 1);
      expect((moves.first['change_qty'] as num).toDouble(), 15.0);
    });

    test('Updating Purchase Order recalculates stock and purchase price', () async {
      final poId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-1002',
        supplierId: supplierId,
        supplierName: 'Prime Suppliers',
        date: todayIso(),
        expectedDate: todayIso(),
        status: 'Draft',
        total: 25000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Organic Honey 500g',
            quantity: 10,
            price: 22000,
            unit: 'jar',
          ),
        ],
      ));

      var prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 20); // 10 + 10
      expect(prod.purchasePrice, 22000);

      // Update PO to 25 quantity and new price ₹260
      await repo.updatePurchaseOrder(PurchaseOrder(
        id: poId,
        businessId: businessId,
        number: 'PO-1002',
        supplierId: supplierId,
        supplierName: 'Prime Suppliers',
        date: todayIso(),
        expectedDate: todayIso(),
        status: 'Confirmed',
        total: 65000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Organic Honey 500g',
            quantity: 25,
            price: 26000,
            unit: 'jar',
          ),
        ],
      ));

      prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 35); // 10 initial + 25 = 35
      expect(prod.purchasePrice, 26000);
    });

    test('Deleting Purchase Order reverts the restocked quantities', () async {
      final poId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-1003',
        supplierId: supplierId,
        supplierName: 'Prime Suppliers',
        date: todayIso(),
        status: 'Draft',
        total: 24000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Organic Honey 500g',
            quantity: 12,
            price: 20000,
            unit: 'jar',
          ),
        ],
      ));

      var prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 22); // 10 + 12

      await repo.deletePurchaseOrder(businessId, poId);

      prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 10); // Reverted back to initial 10
    });

    test('Converting Purchase Order to Purchase does not double count restocked inventory', () async {
      final poId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-1004',
        supplierId: supplierId,
        supplierName: 'Prime Suppliers',
        date: todayIso(),
        status: 'Draft',
        total: 23000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Organic Honey 500g',
            quantity: 8,
            price: 23000,
            unit: 'jar',
          ),
        ],
      ));

      var prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 18); // 10 + 8

      final purchaseId = await repo.convertPurchaseOrderToPurchase(poId);
      expect(purchaseId, greaterThan(0));

      // After converting, stock must still be 18 (NOT 18 + 8 = 26)
      prod = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(prod.stock, 18);
      expect(prod.purchasePrice, 23000);
    });
  });

  group('Restock Notification & Price/Expiry Update', () {
    test('Records restock review item and clears notification upon setting new price and expiry', () async {
      final restockService = RestockNotificationService.instance;

      // Ensure initially 0 pending notifications
      final initialCount = await restockService.getPendingCount(businessId);
      expect(initialCount, 0);

      // Record a restock event (like Purchase Order Builder does)
      await restockService.recordRestock(
        businessId: businessId,
        sourceRef: 'PO-1001',
        items: [
          RestockReviewItem(
            productId: productId,
            productName: 'Organic Honey 500g',
            restockedQty: 20,
            unit: 'jar',
            oldPurchasePrice: 20000,
            newPurchasePrice: 25000,
            currentSalePrice: 30000,
            hasBatch: true,
            currentExpiryDate: '2026-06-30',
            sourceRef: 'PO-1001',
            date: todayIso(),
          ),
        ],
      );

      // Verify pending notification count is 1
      final pendingCount = await restockService.getPendingCount(businessId);
      expect(pendingCount, 1);

      final pendingReviews = await restockService.getPendingReviews(businessId);
      expect(pendingReviews.length, 1);
      final item = pendingReviews.first;
      expect(item.productId, productId);
      expect(item.restockedQty, 20);
      expect(item.newPurchasePrice, 25000);

      // User sets new selling price ₹360 (36000 paise) and new expiry date '2027-12-31'
      await restockService.applyUpdates(
        businessId: businessId,
        updates: {
          productId: (
            salePrice: 36000,
            expiryDate: '2027-12-31',
            batchNumber: 'BATCH-2026-A',
          ),
        },
      );

      // Verify the product in database was updated with new selling price and expiry date
      final updatedProduct = (await repo.products(businessId)).firstWhere((p) => p.id == productId);
      expect(updatedProduct.salePrice, 36000);
      expect(updatedProduct.expiryDate, '2027-12-31');

      // Verify batch record was created
      final batches = await db.query('batches', where: 'product_id = ?', whereArgs: [productId]);
      expect(batches.any((b) => b['batch_number'] == 'BATCH-2026-A' && b['expiry_date'] == '2027-12-31'), isTrue);

      // Verify notification is GONE (pending count = 0)
      final finalCount = await restockService.getPendingCount(businessId);
      expect(finalCount, 0);
    });

    test('Dismissing item removes it from pending review notifications', () async {
      final restockService = RestockNotificationService.instance;

      await restockService.recordRestock(
        businessId: businessId,
        sourceRef: 'PUR-0001',
        items: [
          RestockReviewItem(
            productId: productId,
            productName: 'Organic Honey 500g',
            restockedQty: 5,
            unit: 'jar',
            oldPurchasePrice: 20000,
            newPurchasePrice: 21000,
            currentSalePrice: 30000,
            sourceRef: 'PUR-0001',
            date: todayIso(),
          ),
        ],
      );

      expect(await restockService.getPendingCount(businessId), 1);

      await restockService.dismissItem(businessId, productId);

      expect(await restockService.getPendingCount(businessId), 0);
    });
  });
}
