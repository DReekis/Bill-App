import 'dart:convert';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/gst_reports_service.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Phase 5: MCA Audit Trail & GST Compliance Tests', () {
    late Database db;
    late Repository repo;
    late int bizId;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: AppDatabase.instance.createSchema,
        ),
      );
      AppDatabase.instance.useDatabaseForTesting(db);
      repo = Repository.instance;

      bizId = await repo.createBusiness(Business(
        name: 'Vanguard Retailers Pvt Ltd',
        state: 'Karnataka',
        gstin: '29ABCDE1234F1Z5',
        taxRegistered: true,
      ));
      repo.session.businessId = bizId;
      repo.session.mobile = '9876543210';
    });

    tearDown(() async {
      await db.close();
    });

    test('MCA Audit Trail: cancelInvoice reverts stock, voids ledger, and logs immutable audit trail', () async {
      // 1. Create a product with stock = 100
      final prodId = await repo.upsertProduct(
        Product(
          name: 'Wireless Bluetooth Headset',
          salePrice: 200000, // Rs. 2,000.00
          purchasePrice: 120000,
          stock: 100,
          gstRate: 18,
          hsn: '8518',
        ),
        businessIdOverride: bizId,
      );

      // 2. Create customer
      final custId = await repo.upsertCustomer(
        Customer(
          name: 'Tech Corp India',
          gstin: '29AABCT5555G1Z0',
          state: 'Karnataka',
        ),
        businessIdOverride: bizId,
      );

      // 3. Issue invoice for 10 units
      final quote = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 10, price: 200000, gstRate: 18),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      final invId = await repo.finalizeSale(
        businessId: bizId,
        number: 'INV-0001',
        customerId: custId,
        customerName: 'Tech Corp India',
        date: '2026-09-26',
        dueDate: '2026-10-10',
        gstType: 'intra',
        quote: quote,
        lines: [
          InvoiceLine(
            productId: prodId,
            name: 'Wireless Bluetooth Headset',
            hsn: '8518',
            gstRate: 18,
            quantity: 10,
            price: 200000,
            taxable: quote.lines[0].taxable.paise,
            tax: quote.lines[0].tax.paise,
          ),
        ],
        amountPaid: 100000, // partial payment
        paymentMode: 'Bank',
      );

      // Verify stock was deducted: 100 - 10 = 90
      var p = (await repo.products(bizId)).firstWhere((item) => item.id == prodId);
      expect(p.stock, 90.0);

      // Verify invoice exists and is Partial
      var inv = await repo.invoice(bizId, invId);
      expect(inv, isNotNull);
      expect(inv!.status, 'Partially paid');

      // 4. Cancel the invoice with reason
      await repo.cancelInvoice(bizId, invId, reason: 'Client requested order cancellation before shipment');

      // 5. Verify stock was restored back to 100.0
      p = (await repo.products(bizId)).firstWhere((item) => item.id == prodId);
      expect(p.stock, 100.0);

      // Verify invoice status is 'Cancelled'
      inv = await repo.invoice(bizId, invId);
      expect(inv!.status, 'Cancelled');
      expect(inv.notes, contains('Client requested order cancellation'));

      // Verify invoice ledger entries were voided/removed
      final ledgerRows = await db.query('ledger',
          where: 'business_id = ? AND ref_type = ? AND ref_id = ?',
          whereArgs: [bizId, 'invoice', invId]);
      expect(ledgerRows.isEmpty, isTrue);

      // Verify linked payment was voided
      final paymentRows = await db.query('payments',
          where: 'business_id = ? AND invoice_id = ?', whereArgs: [bizId, invId]);
      expect(paymentRows.isEmpty, isTrue);

      // 6. Verify MCA Audit Trail entry was written
      final auditEntries = await repo.auditLog(bizId, entity: 'invoice', action: 'cancel');
      expect(auditEntries.isNotEmpty, isTrue);

      final cancelLog = auditEntries.firstWhere((e) => e.entityId == invId);
      expect(cancelLog.action, 'cancel');
      expect(cancelLog.actor, '9876543210');
      expect(cancelLog.before, isNotNull);
      expect(cancelLog.after, isNotNull);

      final beforeMap = jsonDecode(cancelLog.before!) as Map<String, dynamic>;
      final afterMap = jsonDecode(cancelLog.after!) as Map<String, dynamic>;

      expect(beforeMap['status'], 'Partially paid');
      expect(afterMap['status'], 'Cancelled');
      expect(afterMap['reason'], 'Client requested order cancellation before shipment');
    });

    test('MCA Audit Trail: updateSale records before and after state diff', () async {
      final custId = await repo.upsertCustomer(
        Customer(
          name: 'Apex Solutions',
          state: 'Karnataka',
        ),
        businessIdOverride: bizId,
      );

      final quote1 = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 1, price: 1000000, gstRate: 18),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      final invId = await repo.finalizeSale(
        businessId: bizId,
        number: 'INV-0002',
        customerId: custId,
        customerName: 'Apex Solutions',
        date: '2026-09-26',
        dueDate: '2026-10-10',
        gstType: 'intra',
        quote: quote1,
        lines: [
          InvoiceLine(
            productId: null,
            name: 'Consulting Service',
            hsn: '9983',
            gstRate: 18,
            quantity: 1,
            price: 1000000,
            taxable: quote1.lines[0].taxable.paise,
            tax: quote1.lines[0].tax.paise,
          ),
        ],
        amountPaid: 0,
      );

      final inv = (await repo.invoice(bizId, invId))!;

      // Update invoice to 2 units (20,000.00)
      final quote2 = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 2, price: 1000000, gstRate: 18),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );

      await repo.updateSale(
        businessId: bizId,
        invoiceId: invId,
        number: inv.number,
        customerId: custId,
        customerName: 'Apex Solutions',
        date: '2026-09-26',
        dueDate: '2026-10-10',
        gstType: 'intra',
        quote: quote2,
        lines: [
          InvoiceLine(
            productId: null,
            name: 'Consulting Service',
            hsn: '9983',
            gstRate: 18,
            quantity: 2,
            price: 1000000,
            taxable: quote2.lines[0].taxable.paise,
            tax: quote2.lines[0].tax.paise,
          ),
        ],
        amountPaid: 0,
      );

      // Verify MCA audit trail has 'update' entry with before & after
      final updates = await repo.auditLog(bizId, entity: 'invoice', action: 'update');
      expect(updates.isNotEmpty, isTrue);

      final updateLog = updates.firstWhere((e) => e.entityId == invId);
      final before = jsonDecode(updateLog.before!) as Map<String, dynamic>;
      final after = jsonDecode(updateLog.after!) as Map<String, dynamic>;

      expect(before['total'], quote1.total.paise);
      expect(after['total'], quote2.total.paise);
    });

    test('GST Compliance: Cancelled invoices excluded from GSTR-1 & HSN, tracked in Table 13 Docs', () async {
      final biz = (await repo.getBusiness(bizId))!;

      // 1. Create B2B Customer
      final custId = await repo.upsertCustomer(
        Customer(
          name: 'Omkar Electronics',
          gstin: '29ABCDE9999F1Z9',
          state: 'Karnataka',
        ),
        businessIdOverride: bizId,
      );

      // 2. Active Invoice 1 (Intrastate intra)
      final q1 = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 1, price: 100000, gstRate: 18),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );
      await repo.finalizeSale(
        businessId: bizId,
        number: 'INV-1001',
        customerId: custId,
        customerName: 'Omkar Electronics',
        date: '2026-09-10',
        dueDate: '2026-09-25',
        gstType: 'intra',
        quote: q1,
        lines: [
          InvoiceLine(
            productId: null,
            name: 'Item A',
            hsn: '8517',
            gstRate: 18,
            quantity: 1,
            price: 100000,
            taxable: q1.lines[0].taxable.paise,
            tax: q1.lines[0].tax.paise,
          ),
        ],
        amountPaid: q1.total.paise,
      );

      // 3. Invoice 2 that gets cancelled
      final q2 = BillingEngine.calculateQuote(
        lines: [
          LineCalcInput(quantity: 2, price: 500000, gstRate: 18),
        ],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        gstEnabled: true,
        businessTaxRegistered: true,
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );
      final inv2Id = await repo.finalizeSale(
        businessId: bizId,
        number: 'INV-1002',
        customerId: custId,
        customerName: 'Omkar Electronics',
        date: '2026-09-15',
        dueDate: '2026-09-30',
        gstType: 'intra',
        quote: q2,
        lines: [
          InvoiceLine(
            productId: null,
            name: 'Item B',
            hsn: '8517',
            gstRate: 18,
            quantity: 2,
            price: 500000,
            taxable: q2.lines[0].taxable.paise,
            tax: q2.lines[0].tax.paise,
          ),
        ],
        amountPaid: 0,
      );

      // Cancel Invoice 2
      await repo.cancelInvoice(bizId, inv2Id, reason: 'Duplicate bill created in error');

      // 4. Query GSTR-1 Data
      final sections = await repo.getGstr1Data(bizId);
      final b2b = sections.firstWhere((s) => s.code == 'B2B');
      final canc = sections.firstWhere((s) => s.code == 'CANC');

      // Cancelled invoice must NOT be in B2B
      expect(b2b.count, 1);
      expect(b2b.taxableAmount, 100000); // only Invoice 1

      // Cancelled invoice must be in CANC
      expect(canc.count, 1);

      // 5. Query HSN Summary - must only reflect Invoice 1
      final hsn = await repo.getHsnSummary(bizId);
      expect(hsn.length, 1);
      expect(hsn.first.taxableValue, 100000);
      expect(hsn.first.cgst, 9000); // 9% of 1000
      expect(hsn.first.sgst, 9000); // 9% of 1000
      expect(hsn.first.igst, 0);

      // 6. Test GSTR-1 JSON output
      final jsonStr = await GstReportsService.instance.generateGstr1Json(business: biz);
      final jsonObj = jsonDecode(jsonStr) as Map<String, dynamic>;

      final docDet = jsonObj['doc_issue']['doc_det'][0]['docs'][0];
      expect(docDet['totnum'], 2); // 1 active + 1 cancelled = 2
      expect(docDet['canc'], 1); // 1 cancelled
      expect(docDet['net_issue'], 1); // 2 - 1 = 1

      // 7. Test GSTR-1 CSV output
      final csvStr = await GstReportsService.instance.generateGstr1Csv(business: biz);
      expect(csvStr, contains('TABLE 4: B2B INVOICES'));
      expect(csvStr, contains('TABLE 12: HSN SUMMARY'));
      expect(csvStr, contains('TABLE 13: DOCUMENTS ISSUED'));
      expect(csvStr, contains('Invoices for outward supply'));
    });
  });
}
