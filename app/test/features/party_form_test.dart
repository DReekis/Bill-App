import 'package:flutter_test/flutter_test.dart';
import 'package:billket/core/gst_service.dart';
import 'package:billket/core/models.dart';

void main() {
  group('Customer & Supplier PAN and Address Serialization', () {
    test('Customer serializes and deserializes pan, city, pin, and addresses', () {
      final customer = Customer(
        id: 101,
        name: 'Apex Traders',
        phone: '9876543210',
        whatsapp: '9876543210',
        email: 'info@apextraders.com',
        billingAddress: '402 Sunrise Complex, MG Road, Mumbai 400001',
        shippingAddress: 'Warehouse #3, Bhiwandi, Thane 421302',
        gstin: '27AABCS1429B1Z5',
        pan: 'AABCS1429B',
        state: 'Maharashtra',
        city: 'Mumbai',
        pin: '400001',
        openingBalance: 500000,
        creditLimit: 1000000,
        paymentTermsDays: 30,
        notes: 'VIP Wholesaler',
      );

      final map = customer.toMap();
      expect(map['name'], 'Apex Traders');
      expect(map['phone'], '9876543210');
      expect(map['whatsapp'], '9876543210');
      expect(map['email'], 'info@apextraders.com');
      expect(map['billing_address'], '402 Sunrise Complex, MG Road, Mumbai 400001');
      expect(map['shipping_address'], 'Warehouse #3, Bhiwandi, Thane 421302');
      expect(map['gstin'], '27AABCS1429B1Z5');
      expect(map['pan'], 'AABCS1429B');
      expect(map['state'], 'Maharashtra');
      expect(map['city'], 'Mumbai');
      expect(map['pin'], '400001');
      expect(map['opening_balance'], 500000);
      expect(map['credit_limit'], 1000000);
      expect(map['payment_terms'], 30);

      final restored = Customer.fromMap({
        'id': 101,
        ...map,
      });

      expect(restored.id, 101);
      expect(restored.name, 'Apex Traders');
      expect(restored.billingAddress, '402 Sunrise Complex, MG Road, Mumbai 400001');
      expect(restored.shippingAddress, 'Warehouse #3, Bhiwandi, Thane 421302');
      expect(restored.gstin, '27AABCS1429B1Z5');
      expect(restored.pan, 'AABCS1429B');
      expect(restored.state, 'Maharashtra');
      expect(restored.city, 'Mumbai');
      expect(restored.pin, '400001');
      expect(restored.creditLimit, 1000000);
      expect(restored.paymentTermsDays, 30);
    });

    test('Supplier serializes and deserializes pan and address', () {
      final supplier = Supplier(
        id: 202,
        name: 'Bharat Chemicals Ltd',
        phone: '9123456780',
        whatsapp: '9123456780',
        email: 'sales@bharatchem.in',
        address: 'Plot 55, GIDC Industrial Estate, Vadodara, Gujarat 390010',
        gstin: '24AAACB1234P1Z8',
        pan: 'AAACB1234P',
        state: 'Gujarat',
        openingBalance: 250000,
        creditPeriodDays: 45,
        notes: 'Primary raw material supplier',
      );

      final map = supplier.toMap();
      expect(map['name'], 'Bharat Chemicals Ltd');
      expect(map['phone'], '9123456780');
      expect(map['whatsapp'], '9123456780');
      expect(map['email'], 'sales@bharatchem.in');
      expect(map['address'], 'Plot 55, GIDC Industrial Estate, Vadodara, Gujarat 390010');
      expect(map['gstin'], '24AAACB1234P1Z8');
      expect(map['pan'], 'AAACB1234P');
      expect(map['state'], 'Gujarat');
      expect(map['opening_balance'], 250000);
      expect(map['credit_period'], 45);

      final restored = Supplier.fromMap({
        'id': 202,
        ...map,
      });

      expect(restored.id, 202);
      expect(restored.name, 'Bharat Chemicals Ltd');
      expect(restored.address, 'Plot 55, GIDC Industrial Estate, Vadodara, Gujarat 390010');
      expect(restored.gstin, '24AAACB1234P1Z8');
      expect(restored.pan, 'AAACB1234P');
      expect(restored.state, 'Gujarat');
      expect(restored.creditPeriodDays, 45);
    });
  });

  group('Party GSTIN Extraction for Auto-Fill', () {
    test('15-char GSTIN extracts 10-char PAN and state code accurately', () {
      const gstin = '27AABCS1429B1Z5';
      expect(GstService.isValidGstinFormat(gstin), isTrue);

      final pan = gstin.substring(2, 12);
      expect(pan, 'AABCS1429B');
      expect(pan.length, 10);

      final deterministic = GstService.parseDeterministic(gstin);
      expect(deterministic.state, 'Maharashtra');
      expect(deterministic.stateCode, '27');
      expect(deterministic.pan, 'AABCS1429B');
      expect(deterministic.constitution, 'Company');
    });

    test('different GSTIN formats correctly identify constitution', () {
      // Proprietorship (4th char of PAN is P)
      const propGstin = '07AABPB1234A1Z5';
      final prop = GstService.parseDeterministic(propGstin);
      expect(prop.pan, 'AABPB1234A');
      expect(prop.constitution, 'Sole Proprietorship');
      expect(prop.state, 'Delhi');

      // Partnership (4th char of PAN is F)
      const partGstin = '29AAPFU1234F1Z8';
      final part = GstService.parseDeterministic(partGstin);
      expect(part.pan, 'AAPFU1234F');
      expect(part.constitution, 'Partnership / LLP');
      expect(part.state, 'Karnataka');
    });
  });
}
