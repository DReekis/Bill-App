import test from 'node:test';
import assert from 'node:assert';
import { app } from '../src/server.js';

test('Sandbox Service & Compliance Engine Endpoints', async (t) => {
  await t.test('GET /api/v1/gst/lookup/:gstin returns complete Billbook fields', async () => {
    // 1. Pre-configured enterprise profile
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/gst/lookup/29AAAAA0000A1Z5',
    });
    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.strictEqual(body.valid, true);
    assert.strictEqual(body.tradeName, 'Modern Retail Store');
    assert.strictEqual(body.legalName, 'Modern Retail Enterprises Pvt Ltd');
    assert.strictEqual(body.pan, 'AAAAA0000A');
    assert.strictEqual(body.stateCode, '29');
    assert.strictEqual(body.state, 'Karnataka');
    assert.strictEqual(body.city, 'Bengaluru');
    assert.strictEqual(body.pinCode, '560001');
    assert.strictEqual(body.constitution, 'Private Limited Company');
    assert.strictEqual(body.taxpayerType, 'Regular');
    assert.strictEqual(body.isComposition, false);
    assert.strictEqual(body.status, 'Active');
    assert.strictEqual(body.shippingAddress, 'Modern Retail Store, 104, MG Road, Brigade Junction, Bengaluru, Karnataka - 560001');

    // 2. Deterministic fallback for any valid Indian GSTIN
    const res2 = await app.inject({
      method: 'GET',
      url: '/api/v1/gst/lookup/27ABCFE1234F1Z5',
    });
    assert.strictEqual(res2.statusCode, 200);
    const body2 = JSON.parse(res2.body);
    assert.strictEqual(body2.valid, true);
    assert.strictEqual(body2.pan, 'ABCFE1234F');
    assert.strictEqual(body2.stateCode, '27');
    assert.strictEqual(body2.state, 'Maharashtra');
    assert.strictEqual(body2.constitution, 'Partnership / LLP');
    assert.ok(body2.shippingAddress && body2.shippingAddress.includes('Enterprise ABCFE'));
  });

  await t.test('POST /api/v1/einvoice/generate generates compliant IRN, Ack and Signed QR Code', async () => {
    const payload = {
      invoiceNumber: 'INV-2026-9001',
      invoiceDate: '2026-10-10',
      supplyType: 'B2B',
      sellerGstin: '29AAAAA0000A1Z5',
      sellerLegalName: 'Modern Retail Enterprises Pvt Ltd',
      sellerTradeName: 'Modern Retail Store',
      sellerAddress: '104, MG Road, Brigade Junction',
      sellerCity: 'Bengaluru',
      sellerStateCode: '29',
      sellerPincode: '560001',
      buyerGstin: '27AAPFU0939F1ZV',
      buyerLegalName: 'Apex Electronics & Trade LLP',
      buyerTradeName: 'Apex Electronics',
      buyerAddress: 'Shop 12, Lamington Road',
      buyerCity: 'Mumbai',
      buyerStateCode: '27',
      buyerPincode: '400007',
      placeOfSupply: '27',
      items: [
        {
          itemNo: 1,
          productName: 'Commercial Thermal POS System',
          hsn: '84705000',
          quantity: 2,
          unit: 'NOS',
          unitPrice: 2500000,
          grossAmount: 5000000,
          discount: 0,
          taxableAmount: 5000000,
          gstRate: 18,
          igstAmount: 900000,
          totalItemValue: 5900000,
        },
      ],
      taxableAmount: 5000000,
      igstAmount: 900000,
      totalInvoiceValue: 5900000,
    };

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/einvoice/generate',
      payload,
    });

    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.status, 'ACT');
    assert.strictEqual(body.nicSchemaVersion, '1.03');
    // IRN must be 64 hexadecimal characters
    assert.strictEqual(typeof body.irn, 'string');
    assert.strictEqual(body.irn.length, 64);
    assert.match(body.irn, /^[0-9a-f]{64}$/);
    // AckNo must be 15 digits
    assert.strictEqual(typeof body.ackNo, 'string');
    assert.strictEqual(body.ackNo.length, 15);
    // Signed QR Code string must be present
    assert.ok(body.signedQrCode && body.signedQrCode.length > 50);

    // Test E-Invoice cancellation within 24h
    const cancelRes = await app.inject({
      method: 'POST',
      url: '/api/v1/einvoice/cancel',
      payload: {
        irn: body.irn,
        reason: '3', // Order Cancelled
        remarks: 'Client cancelled transaction',
      },
    });
    assert.strictEqual(cancelRes.statusCode, 200);
    const cancelBody = JSON.parse(cancelRes.body);
    assert.strictEqual(cancelBody.success, true);
    assert.strictEqual(cancelBody.irn, body.irn);
    assert.strictEqual(cancelBody.status, 'CNL');
  });

  await t.test('POST /api/v1/ewaybill/generate generates authentic 12-digit E-Way Bill and slip', async () => {
    const payload = {
      invoiceNumber: 'INV-2026-9001',
      invoiceDate: '2026-10-10',
      subSupplyType: '1',
      docType: 'INV',
      fromGstin: '29AAAAA0000A1Z5',
      fromTradeName: 'Modern Retail Store',
      fromAddress: '104, MG Road, Brigade Junction',
      fromCity: 'Bengaluru',
      fromPincode: '560001',
      fromStateCode: '29',
      toGstin: '27AAPFU0939F1ZV',
      toTradeName: 'Apex Electronics',
      toAddress: 'Shop 12, Lamington Road',
      toCity: 'Mumbai',
      toPincode: '400007',
      toStateCode: '27',
      totalValue: 5000000,
      igstValue: 900000,
      totInvValue: 5900000,
      distanceKm: 980,
      vehicleNo: 'KA01AB1234',
      vehicleType: 'R',
      transportMode: 'Road',
      transporterName: 'VRL Logistics',
    };

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/ewaybill/generate',
      payload,
    });

    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.status, 'ACT');
    // E-Way Bill Number must be exactly 12 digits
    assert.strictEqual(typeof body.ewbNo, 'string');
    assert.strictEqual(body.ewbNo.length, 12);
    assert.match(body.ewbNo, /^[0-9]{12}$/);
    assert.strictEqual(body.vehicleNo, 'KA01AB1234');
    assert.strictEqual(body.distanceKm, 980);
    assert.ok(body.validUntil);

    // Test E-Way Bill cancellation
    const cancelRes = await app.inject({
      method: 'POST',
      url: '/api/v1/ewaybill/cancel',
      payload: {
        ewbNo: body.ewbNo,
        reason: '2', // Order Cancelled
        remarks: 'Order cancelled by buyer',
      },
    });
    assert.strictEqual(cancelRes.statusCode, 200);
    const cancelBody = JSON.parse(cancelRes.body);
    assert.strictEqual(cancelBody.success, true);
    assert.strictEqual(cancelBody.ewbNo, body.ewbNo);
    assert.strictEqual(cancelBody.status, 'CNL');
  });
});
