import 'package:billket/core/dates.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/utils/pdf_invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late Business business;
  late int customerId;
  late int supplierId;
  late int productId;

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
      name: 'Order Workflow Test Store',
      ownerName: 'Order Manager',
      taxRegistered: false,
    ));
    business = (await repo.getBusiness(businessId))!;
    repo.session.businessId = businessId;

    customerId = await repo.upsertCustomer(
      Customer(
        name: 'Alice Cooper',
        phone: '9876543210',
        billingAddress: '123 Market St',
      ),
      businessIdOverride: businessId,
    );

    supplierId = await repo.upsertSupplier(
      Supplier(
        name: 'Acme Wholesalers',
        phone: '9123456780',
        address: '456 Industrial Area',
      ),
      businessIdOverride: businessId,
    );

    productId = await repo.upsertProduct(
      Product(
        name: 'Premium Basmati Rice 5kg',
        salePrice: 50000, // ₹500
        purchasePrice: 40000, // ₹400
        stock: 50,
        unit: 'bag',
      ),
      businessIdOverride: businessId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Sell Order & Purchase Order Workflows', () {
    test('Sequential numbering auto-increments for Sales Orders', () async {
      final initialPeek = await repo.peekNextSalesOrderNumber(businessId);
      expect(initialPeek, 'SO-0001');

      final orderId = await repo.finalizeSalesOrder(SalesOrder(
        businessId: businessId,
        number: initialPeek,
        customerId: customerId,
        customerName: 'Alice Cooper',
        date: todayIso(),
        dueDate: todayIso(),
        status: 'Pending',
        total: 100000, // ₹1,000
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 2,
            price: 50000,
            unit: 'bag',
          ),
        ],
      ));
      expect(orderId, greaterThan(0));

      final nextPeek = await repo.peekNextSalesOrderNumber(businessId);
      expect(nextPeek, 'SO-0002');
    });

    test('Sequential numbering auto-increments for Purchase Orders', () async {
      final initialPeek = await repo.peekNextPurchaseOrderNumber(businessId);
      expect(initialPeek, 'PO-0001');

      final poId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: initialPeek,
        supplierId: supplierId,
        supplierName: 'Acme Wholesalers',
        date: todayIso(),
        expectedDate: todayIso(),
        status: 'Draft',
        total: 200000, // ₹2,000
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 5,
            price: 40000,
            unit: 'bag',
          ),
        ],
      ));
      expect(poId, greaterThan(0));

      final nextPeek = await repo.peekNextPurchaseOrderNumber(businessId);
      expect(nextPeek, 'PO-0002');
    });

    test('Sales Orders can be listed and retrieved with line items', () async {
      await repo.finalizeSalesOrder(SalesOrder(
        businessId: businessId,
        number: 'SO-0001',
        customerId: customerId,
        customerName: 'Alice Cooper',
        date: todayIso(),
        status: 'Pending',
        total: 100000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 2,
            price: 50000,
            unit: 'bag',
          ),
        ],
      ));

      final orders = await repo.salesOrders(businessId);
      expect(orders.isNotEmpty, isTrue);
      final order = orders.firstWhere((o) => o.number == 'SO-0001');
      expect(order.customerName, 'Alice Cooper');
      expect(order.lines.length, 1);
      expect(order.lines.first.name, 'Premium Basmati Rice 5kg');
      expect(order.lines.first.quantity, 2);
    });

    test('Purchase Orders can be listed and retrieved with line items', () async {
      await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-0001',
        supplierId: supplierId,
        supplierName: 'Acme Wholesalers',
        date: todayIso(),
        status: 'Draft',
        total: 200000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 5,
            price: 40000,
            unit: 'bag',
          ),
        ],
      ));

      final pos = await repo.purchaseOrders(businessId);
      expect(pos.isNotEmpty, isTrue);
      final po = pos.firstWhere((p) => p.number == 'PO-0001');
      expect(po.supplierName, 'Acme Wholesalers');
      expect(po.lines.length, 1);
      expect(po.lines.first.name, 'Premium Basmati Rice 5kg');
      expect(po.lines.first.quantity, 5);
    });

    test('One-click conversion of Sell Order to Invoice updates order status and creates invoice', () async {
      final orderId = await repo.finalizeSalesOrder(SalesOrder(
        businessId: businessId,
        number: 'SO-0001',
        customerId: customerId,
        customerName: 'Alice Cooper',
        date: todayIso(),
        status: 'Pending',
        total: 100000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 2,
            price: 50000,
            unit: 'bag',
          ),
        ],
      ));

      final invoiceId = await repo.convertSalesOrderToInvoice(orderId);
      expect(invoiceId, greaterThan(0));

      // Check updated order status
      final updatedOrder = await repo.salesOrder(businessId, orderId);
      expect(updatedOrder?.status, 'Converted');
      expect(updatedOrder?.notes, contains('Converted to Invoice ID: $invoiceId'));

      // Check newly created invoice
      final invoice = await repo.invoice(businessId, invoiceId);
      expect(invoice, isNotNull);
      expect(invoice?.customerName, 'Alice Cooper');
      expect(invoice?.total, 100000);
      expect(invoice?.notes, contains('Converted from Sales Order SO-0001'));
    });

    test('One-click conversion of Purchase Order to Purchase updates stock and marks converted', () async {
      final prodsBefore = await repo.products(businessId);
      final initialStock = prodsBefore.firstWhere((p) => p.id == productId).stock;

      final poId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-0001',
        supplierId: supplierId,
        supplierName: 'Acme Wholesalers',
        date: todayIso(),
        status: 'Draft',
        total: 200000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 5,
            price: 40000,
            unit: 'bag',
          ),
        ],
      ));

      final purchaseId = await repo.convertPurchaseOrderToPurchase(poId);
      expect(purchaseId, greaterThan(0));

      // Check updated PO status
      final updatedPo = await repo.purchaseOrder(businessId, poId);
      expect(updatedPo?.status, 'Converted');
      expect(updatedPo?.notes, contains('Converted to Purchase ID: $purchaseId'));

      // Stock was updated by purchase (+5 bags)
      final prodsAfter = await repo.products(businessId);
      expect(prodsAfter.firstWhere((p) => p.id == productId).stock, initialStock + 5);
    });

    test('recentTransactions includes orders when includeOrders is true', () async {
      await repo.finalizeSalesOrder(SalesOrder(
        businessId: businessId,
        number: 'SO-0001',
        customerId: customerId,
        customerName: 'Alice Cooper',
        date: todayIso(),
        status: 'Pending',
        total: 100000,
        lines: [],
      ));

      await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-0001',
        supplierId: supplierId,
        supplierName: 'Acme Wholesalers',
        date: todayIso(),
        status: 'Draft',
        total: 200000,
        lines: [],
      ));

      final txsWithOrders = await repo.recentTransactions(
        businessId,
        includeOrders: true,
      );

      final hasSalesOrder = txsWithOrders.any((t) => t.type == TransactionType.salesOrder);
      final hasPurchaseOrder = txsWithOrders.any((t) => t.type == TransactionType.purchaseOrder);
      expect(hasSalesOrder, isTrue);
      expect(hasPurchaseOrder, isTrue);

      final soRecord = txsWithOrders.firstWhere((t) => t.type == TransactionType.salesOrder);
      expect(soRecord.isInflow, isTrue);
      expect(soRecord.typeLabel, 'Sales Order');

      final poRecord = txsWithOrders.firstWhere((t) => t.type == TransactionType.purchaseOrder);
      expect(poRecord.typeLabel, 'Purchase Order');
    });

    test('PDF invoice generator builds official Sell Order and Purchase Order PDFs', () async {
      final order = SalesOrder(
        businessId: businessId,
        number: 'SO-0001',
        customerId: customerId,
        customerName: 'Alice Cooper',
        date: todayIso(),
        status: 'Pending',
        total: 100000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 2,
            price: 50000,
            unit: 'bag',
          ),
        ],
      );
      final salesOrderPdf = await buildSalesOrderPdf(
        business: business,
        order: order,
      );
      expect(salesOrderPdf.isNotEmpty, isTrue);

      final po = PurchaseOrder(
        businessId: businessId,
        number: 'PO-0001',
        supplierId: supplierId,
        supplierName: 'Acme Wholesalers',
        date: todayIso(),
        status: 'Draft',
        total: 200000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Premium Basmati Rice 5kg',
            quantity: 5,
            price: 40000,
            unit: 'bag',
          ),
        ],
      );
      final purchaseOrderPdf = await buildPurchaseOrderPdf(
        business: business,
        order: po,
      );
      expect(purchaseOrderPdf.isNotEmpty, isTrue);
    });

    test('Deletes Sales Order and Purchase Order cleanly', () async {
      final tempSoId = await repo.finalizeSalesOrder(SalesOrder(
        businessId: businessId,
        number: 'SO-TEMP',
        date: todayIso(),
        status: 'Pending',
        total: 50000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Temp Rice',
            quantity: 1,
            price: 50000,
          ),
        ],
      ));
      expect(tempSoId, greaterThan(0));
      await repo.deleteSalesOrder(businessId, tempSoId);
      final deletedSo = await repo.salesOrder(businessId, tempSoId);
      expect(deletedSo, isNull);

      final tempPoId = await repo.finalizePurchaseOrder(PurchaseOrder(
        businessId: businessId,
        number: 'PO-TEMP',
        date: todayIso(),
        status: 'Draft',
        total: 40000,
        lines: [
          InvoiceLine(
            productId: productId,
            name: 'Temp Rice',
            quantity: 1,
            price: 40000,
          ),
        ],
      ));
      expect(tempPoId, greaterThan(0));
      await repo.deletePurchaseOrder(businessId, tempPoId);
      final deletedPo = await repo.purchaseOrder(businessId, tempPoId);
      expect(deletedPo, isNull);
    });
  });
}
