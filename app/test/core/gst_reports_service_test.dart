import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billket/core/billing_engine.dart';
import 'package:billket/core/gst_reports_service.dart';
import 'package:billket/core/models.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';

void main() {
  final repo = Repository.instance;
  late Database db;
  late int businessId;
  late Business testBusiness;

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
      name: 'Alpha Traders Pvt Ltd',
      gstin: '29ABCDE1234F1Z5',
      state: 'Karnataka',
      taxRegistered: true,
      currency: 'INR',
      signatureText: 'Managing Director',
    ));
    repo.session.businessId = businessId;
    testBusiness = (await repo.getBusiness(businessId))!;
  });

  tearDown(() async {
    await db.close();
  });

  group('GstReportsService Unit Helpers', () {
    test('toRupees converts paise to standard rupees correctly', () {
      expect(GstReportsService.toRupees(100000), 1000.0);
      expect(GstReportsService.toRupees(4950), 49.5);
      expect(GstReportsService.toRupees(0), 0.0);
      expect(GstReportsService.toRupees(1), 0.01);
    });

    test('formatGstDate converts ISO date to DD-MM-YYYY', () {
      expect(GstReportsService.formatGstDate('2026-09-24'), '24-09-2026');
      expect(GstReportsService.formatGstDate('2026-01-05'), '05-01-2026');
    });

    test('formatFp generates 6-digit MMYYYY financial period string', () {
      expect(GstReportsService.formatFp(DateTime(2026, 9, 24)), '092026');
      expect(GstReportsService.formatFp(DateTime(2026, 1, 15)), '012026');
    });

    test('resolveStateCode derives state code from GSTIN or state name', () {
      expect(GstReportsService.resolveStateCode(gstin: '29ABCDE1234F1Z5'), '29');
      expect(GstReportsService.resolveStateCode(gstin: '27AAPFU0939F1ZV'), '27');
      expect(GstReportsService.resolveStateCode(stateName: 'Delhi'), '07');
      expect(GstReportsService.resolveStateCode(stateName: 'Maharashtra'), '27');
      expect(GstReportsService.resolveStateCode(stateName: 'Karnataka'), '29');
    });
  });

  group('GSTR-1 Reporting Protocol (Sales)', () {
    setUp(() async {
      // Seed a B2B product
      final prodId = await repo.upsertProduct(
        Product(
          name: 'Industrial Widget A',
          sku: 'WID-01',
          hsn: '84713010',
          salePrice: 100000, // ₹1,000.00
          purchasePrice: 60000,
          costAverage: 60000,
          stock: 50,
          gstRate: 18,
        ),
        businessIdOverride: businessId,
      );

      // Seed a registered customer
      final custId = await repo.upsertCustomer(
        Customer(
          name: 'Nexus Enterprises',
          gstin: '29BBBBB0000B1Z2',
          phone: '9876543210',
          state: 'Karnataka',
        ),
        businessIdOverride: businessId,
      );

      // Create a B2B Sale
      final quote = BillingEngine.calculateQuote(
        lines: [LineCalcInput(quantity: 2, price: 100000, gstRate: 18)],
        invoiceDiscount: const InvoiceDiscountInput.none(),
        businessState: 'Karnataka',
        customerState: 'Karnataka',
      );
      final line = quote.lines.first;
      final number = await repo.nextInvoiceNumber(businessId, 'INV');

      await repo.finalizeSale(
        businessId: businessId,
        number: number,
        customerId: custId,
        customerName: 'Nexus Enterprises',
        date: '2026-09-24',
        gstType: 'intra',
        quote: quote,
        lines: [
          InvoiceLine(
            productId: prodId,
            name: 'Industrial Widget A',
            hsn: '84713010',
            gstRate: 18,
            quantity: 2,
            price: 100000,
            taxable: line.taxable.paise,
            tax: line.tax.paise,
          )
        ],
        paymentMode: 'Bank Transfer',
        amountPaid: quote.total.paise,
      );
    });

    test('generateGstr1Json complies strictly with Government GST Portal Schema v1.3', () async {
      final jsonStr = await GstReportsService.instance.generateGstr1Json(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(jsonStr, isNotEmpty);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Root level portal fields
      expect(data['gstin'], '29ABCDE1234F1Z5');
      expect(data['fp'], '092026');
      expect(data['version'], 'GSTR1_V1.3');
      expect(data['gt'], greaterThan(0));
      expect(data['cur_gt'], greaterThan(0));

      // B2B Section
      expect(data['b2b'], isA<List>());
      final b2bList = data['b2b'] as List;
      expect(b2bList.length, 1);
      final b2bEntry = b2bList.first as Map<String, dynamic>;
      expect(b2bEntry['ctin'], '29BBBBB0000B1Z2');
      expect(b2bEntry['cfs'], 'Y');
      final invList = b2bEntry['inv'] as List;
      expect(invList.length, 1);

      final inv = invList.first as Map<String, dynamic>;
      expect(inv['pos'], '29');
      expect(inv['inv_typ'], 'R');
      expect(inv['rchrg'], 'N');
      expect(inv['itms'], isA<List>());

      // HSN Section
      expect(data['hsn'], isA<Map<String, dynamic>>());
      final hsnData = data['hsn']['data'] as List;
      expect(hsnData, isNotEmpty);
      final firstHsn = hsnData.first as Map<String, dynamic>;
      expect(firstHsn['hsn_sc'], '84713010');
      expect(firstHsn['qty'], 2);

      // Document Issue Section
      expect(data['doc_issue'], isA<Map<String, dynamic>>());
      final docDet = data['doc_issue']['doc_det'] as List;
      expect(docDet, isNotEmpty);
      final docs = docDet.first['docs'] as List;
      expect(docs.first['totnum'], greaterThan(0));
    });

    test('generateGstr1Excel outputs valid GST Offline Tool format workbook', () async {
      final bytes = await GstReportsService.instance.generateGstr1Excel(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      // Standard ZIP/OpenXML magic bytes
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);

      // Verify workbook structure via ZipDecoder
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);
    });

    test('generateGstr1Pdf renders official Form GSTR-1 document', () async {
      final pdfBytes = await GstReportsService.instance.generateGstr1Pdf(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        periodLabel: 'September 2026',
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('GSTR-2 Reporting Protocol (Purchases / Inward Supplies)', () {
    setUp(() async {
      await db.insert('expenses', {
        'business_id': businessId,
        'category': 'Purchase',
        'vendor': 'Supreme Materials Ltd',
        'amount': 590000,
        'date': '2026-09-20',
        'mode': 'Bank Transfer',
      });
    });

    test('generateGstr2Json generates GST Portal compliant JSON', () async {
      final jsonStr = await GstReportsService.instance.generateGstr2Json(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(jsonStr, isNotEmpty);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['gstin'], '29ABCDE1234F1Z5');
      expect(data['fp'], '092026');
      expect(data['version'], 'GSTR2_V1.1');
      expect(data['b2b'], isA<List>());

      final b2b = data['b2b'] as List;
      expect(b2b.length, 1);
      final entry = b2b.first as Map<String, dynamic>;
      expect(entry['ctin'], contains('27AABCU'));
      final invList = entry['inv'] as List;
      expect(invList.length, 1);
      final inv = invList.first as Map<String, dynamic>;
      expect(inv['val'], 5900.0);
    });

    test('generateGstr2Excel outputs valid Purchase Register spreadsheet', () async {
      final bytes = await GstReportsService.instance.generateGstr2Excel(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);
    });

    test('generateGstr2Pdf renders official Form GSTR-2 document', () async {
      final pdfBytes = await GstReportsService.instance.generateGstr2Pdf(
        business: testBusiness,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        periodLabel: 'September 2026',
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('GSTR-3B Reporting Protocol (Monthly Return & Tax Computation)', () {
    test('generateGstr3bJson complies with GST Portal GSTR3B schema', () async {
      final jsonStr = await GstReportsService.instance.generateGstr3bJson(
        business: testBusiness,
        period: 'September 2026',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(jsonStr, isNotEmpty);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['gstin'], '29ABCDE1234F1Z5');
      expect(data['ret_period'], '092026');
      expect(data['sec_sum'], isA<Map<String, dynamic>>());

      final secSum = data['sec_sum'] as Map<String, dynamic>;
      expect(secSum['3.1'], isA<Map<String, dynamic>>());
      expect(secSum['3.1']['osup_det'], isNotNull);
      expect(secSum['4'], isA<Map<String, dynamic>>());
      expect(secSum['4']['itc_avl'], isA<List>());
      expect(secSum['4']['itc_net'], isNotNull);
      expect(secSum['5.1'], isA<Map<String, dynamic>>());
    });

    test('generateGstr3bExcel creates 3.1, 4 and 6.1 workbook sheets', () async {
      final bytes = await GstReportsService.instance.generateGstr3bExcel(
        business: testBusiness,
        period: 'September 2026',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);
    });

    test('generateGstr3bPdf renders official Form GSTR-3B document', () async {
      final pdfBytes = await GstReportsService.instance.generateGstr3bPdf(
        business: testBusiness,
        period: 'September 2026',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });
}
