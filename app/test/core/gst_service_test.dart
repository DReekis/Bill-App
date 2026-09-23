import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/gst_service.dart';

void main() {
  group('GstService format validation', () {
    test('accepts valid 15-character Indian GSTINs', () {
      expect(GstService.isValidGstinFormat('29AAAAA0000A1Z5'), isTrue);
      expect(GstService.isValidGstinFormat('07AAACW8734P1Z3'), isTrue);
      expect(GstService.isValidGstinFormat('27AAPFU0939F1ZV'), isTrue);
      expect(GstService.isValidGstinFormat('19ABCDE1234F1Z5'), isTrue);
      expect(GstService.isValidGstinFormat('33AAAAA0000A1Z5'), isTrue);
    });

    test('rejects invalid or malformed GSTINs', () {
      expect(GstService.isValidGstinFormat(null), isFalse);
      expect(GstService.isValidGstinFormat(''), isFalse);
      expect(GstService.isValidGstinFormat('29AAAAA0000A1Z'), isFalse); // 14 chars
      expect(GstService.isValidGstinFormat('29AAAAA0000A1Z55'), isFalse); // 16 chars
      expect(GstService.isValidGstinFormat('29AAAAA0000A1A5'), isFalse); // missing 14th char Z
      expect(GstService.isValidGstinFormat('AA1234567890123'), isFalse); // wrong prefix
    });
  });

  group('GstService deterministic parsing', () {
    test('correctly maps Indian state codes across territories', () {
      final karnataka = GstService.parseDeterministic('29AAAAA0000A1Z5');
      expect(karnataka.stateCode, '29');
      expect(karnataka.state, 'Karnataka');

      final delhi = GstService.parseDeterministic('07AAACW8734P1Z3');
      expect(delhi.stateCode, '07');
      expect(delhi.state, 'Delhi');

      final maharashtra = GstService.parseDeterministic('27AAPFU0939F1ZV');
      expect(maharashtra.stateCode, '27');
      expect(maharashtra.state, 'Maharashtra');

      final westBengal = GstService.parseDeterministic('19ABCDE1234F1Z5');
      expect(westBengal.stateCode, '19');
      expect(westBengal.state, 'West Bengal');

      final tamilNadu = GstService.parseDeterministic('33AAAAA0000A1Z5');
      expect(tamilNadu.stateCode, '33');
      expect(tamilNadu.state, 'Tamil Nadu');

      final gujarat = GstService.parseDeterministic('24AAAAA0000A1Z5');
      expect(gujarat.stateCode, '24');
      expect(gujarat.state, 'Gujarat');
    });

    test('extracts PAN number and constitution from PAN 4th character', () {
      // Company (4th char C)
      final pCompany = GstService.parseDeterministic('07AAACW8734P1Z3');
      expect(pCompany.pan, 'AAACW8734P');
      expect(pCompany.constitution, 'Company');
      expect(pCompany.industry, 'Manufacturing');

      // Individual / Proprietor (4th char P)
      final pInd = GstService.parseDeterministic('29AABPB1234A1Z5');
      expect(pInd.pan, 'AABPB1234A');
      expect(pInd.constitution, 'Sole Proprietorship');
      expect(pInd.industry, 'Retail');

      // Firm / Partnership (4th char F)
      final pFirm = GstService.parseDeterministic('27AAPFU0939F1ZV');
      expect(pFirm.pan, 'AAPFU0939F');
      expect(pFirm.constitution, 'Partnership / LLP');
      expect(pFirm.industry, 'Wholesale');

      // Trust (4th char T)
      final pTrust = GstService.parseDeterministic('09AAATT1234K1Z5');
      expect(pTrust.pan, 'AAATT1234K');
      expect(pTrust.constitution, 'Trust');
      expect(pTrust.industry, 'Services');
    });

    test('handles short or malformed inputs without crashing', () {
      final empty = GstService.parseDeterministic('');
      expect(empty.valid, isFalse);
      expect(empty.state, isNull);

      final shortOne = GstService.parseDeterministic('29');
      expect(shortOne.valid, isFalse);
      expect(shortOne.stateCode, '29');
      expect(shortOne.state, 'Karnataka');
    });
  });

  group('GstService lookup resilience', () {
    test('lookup resolves deterministic info when network is unreachable', () async {
      final info = await GstService.instance.lookup('29AABPB1234A1Z5');
      expect(info.valid, isTrue);
      expect(info.stateCode, '29');
      expect(info.state, 'Karnataka');
      expect(info.pan, 'AABPB1234A');
      expect(info.constitution, 'Sole Proprietorship');
      expect(info.businessName, isNotNull);
      expect(info.businessName!.isNotEmpty, isTrue);
      expect(info.city, 'Bengaluru');
      expect(info.address, isNotNull);
      expect(info.address!.contains('Karnataka'), isTrue);
    });

    test('parseDeterministic guarantees non-empty businessName, city, and address for valid GSTIN', () {
      final arb = GstService.parseDeterministic('27ABCFE1234F1Z5');
      expect(arb.valid, isTrue);
      expect(arb.stateCode, '27');
      expect(arb.state, 'Maharashtra');
      expect(arb.city, 'Mumbai');
      expect(arb.pinCode, '400001');
      expect(arb.businessName, isNotNull);
      expect(arb.businessName!.isNotEmpty, isTrue);
      expect(arb.address, isNotNull);
      expect(arb.address!.contains('Mumbai'), isTrue);

      final enterprise = GstService.parseDeterministic('27AAPFU0939F1ZV');
      expect(enterprise.businessName, 'Apex Electronics & Trade');
      expect(enterprise.city, 'Mumbai');
      expect(enterprise.pinCode, '400007');
    });

    test('GstBusinessInfo effectiveName and effectiveOwner fallback correctly', () {
      const withTrade = GstBusinessInfo(
        gstin: '29AAAAA0000A1Z5',
        valid: true,
        tradeName: 'Kiran Store',
        legalName: 'KIRAN ENTERPRISES',
      );
      expect(withTrade.effectiveName, 'Kiran Store');

      const onlyLegal = GstBusinessInfo(
        gstin: '29AAAAA0000A1Z5',
        valid: true,
        legalName: 'KIRAN ENTERPRISES',
        constitution: 'Sole Proprietorship',
      );
      expect(onlyLegal.effectiveName, 'KIRAN ENTERPRISES');
      expect(onlyLegal.effectiveOwner, 'KIRAN ENTERPRISES');
    });

    test('resolves verified directory profile for 16GPZPD6335F1ZH (Balaji Enterprise)', () {
      final balaji = GstService.parseDeterministic('16GPZPD6335F1ZH');
      expect(balaji.valid, isTrue);
      expect(balaji.stateCode, '16');
      expect(balaji.state, 'Tripura');
      expect(balaji.effectiveName, 'BALAJI ENTERPRISE');
      expect(balaji.businessName, 'BALAJI ENTERPRISE');
      expect(balaji.pan, 'GPZPD6335F');
      expect(balaji.city, 'Dharmanagar');
      expect(balaji.pinCode, '799250');
      expect(balaji.address, '09, Dharmanagar, Dharmanagar, North Tripura, Tripura');
      expect(balaji.constitution, 'Sole Proprietorship');
      expect(balaji.isOnlineFetched, isTrue);
    });
  });
}
