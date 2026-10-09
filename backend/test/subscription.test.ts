import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { app } from '../src/server.js';
import { prisma } from '../src/services/db.js';
import { config } from '../src/config.js';

test('Subscription & Razorpay Engine Suite', async (t) => {
  const testEmail = `sub-test-${Date.now()}@example.com`;
  let authToken = '';
  let businessId = '';

  await t.test('Setup: Register test business owner', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        name: 'FinTech Owner',
        email: testEmail,
        password: 'password123',
        businessName: 'Apex Sub Enterprises',
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.body);
    authToken = body.token;
    businessId = body.business.id;
    assert.ok(authToken);
    assert.ok(businessId);
  });

  await t.test('GET /api/v1/subscription/plans returns canonical 5 tiers', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/subscription/plans',
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.ok(Array.isArray(body.plans));

    const tiers = body.plans.map((p: any) => p.tier);
    assert.ok(tiers.includes('free'));
    assert.ok(tiers.includes('starter'));
    assert.ok(tiers.includes('silver'));
    assert.ok(tiers.includes('gold'));
    assert.ok(tiers.includes('business_pro'));

    // Check pricing exact match with PDF
    const starter = body.plans.find((p: any) => p.tier === 'starter');
    const silver = body.plans.find((p: any) => p.tier === 'silver');
    const gold = body.plans.find((p: any) => p.tier === 'gold');
    const businessPro = body.plans.find((p: any) => p.tier === 'business_pro');

    assert.equal(starter.priceInInr, 579);
    assert.equal(silver.priceInInr, 1499);
    assert.equal(gold.priceInInr, 2999);
    assert.equal(businessPro.priceInInr, 4999);
  });

  await t.test('GET /api/v1/subscription/status/:businessId returns usage and plan details', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/subscription/status/${businessId}`,
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.equal(body.businessId, businessId);
    assert.ok(body.plan);
    assert.ok(body.usage);
    assert.equal(typeof body.usage.invoices.used, 'number');
  });

  await t.test('POST /api/v1/subscription/create-order creates verified Razorpay order', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/subscription/create-order',
      headers: {
        authorization: `Bearer ${authToken}`,
      },
      payload: {
        businessId,
        tier: 'silver',
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.body);
    assert.ok(body.orderId);
    assert.equal(body.amount, 149900); // 1,499 INR in paise
    assert.equal(body.currency, 'INR');
    assert.equal(body.plan.tier, 'silver');
  });

  await t.test('POST /api/v1/subscription/verify-payment rejects tampered signature', async () => {
    // Generate valid test order in DB
    const fakeOrderId = `order_test_${Date.now()}`;
    await prisma.subscriptionOrder.create({
      data: {
        orderId: fakeOrderId,
        businessId,
        tier: 'silver',
        amount: 149900,
        currency: 'INR',
        status: 'created',
      },
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/subscription/verify-payment',
      headers: {
        authorization: `Bearer ${authToken}`,
      },
      payload: {
        businessId,
        orderId: fakeOrderId,
        paymentId: 'pay_test_tampered',
        signature: 'invalid_sha256_hash_here_123',
      },
    });

    assert.equal(res.statusCode, 400);
    const body = JSON.parse(res.body);
    assert.ok(body.error.includes('SIGNATURE_VERIFICATION_FAILED'));
  });

  await t.test('POST /api/v1/subscription/verify-payment accepts valid HMAC and upgrades business', async () => {
    const validOrderId = `order_valid_${Date.now()}`;
    const validPaymentId = `pay_valid_${Date.now()}`;

    await prisma.subscriptionOrder.create({
      data: {
        orderId: validOrderId,
        businessId,
        tier: 'gold',
        amount: 299900,
        currency: 'INR',
        status: 'created',
      },
    });

    // Compute legitimate HMAC SHA-256 signature
    const validSignature = crypto
      .createHmac('sha256', config.razorpay.keySecret)
      .update(`${validOrderId}|${validPaymentId}`)
      .digest('hex');

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/subscription/verify-payment',
      headers: {
        authorization: `Bearer ${authToken}`,
      },
      payload: {
        businessId,
        orderId: validOrderId,
        paymentId: validPaymentId,
        signature: validSignature,
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.equal(body.success, true);
    assert.equal(body.tier, 'gold');
    assert.ok(body.expiresAt);

    // Verify database record upgraded
    const dbBusiness = await prisma.business.findUnique({
      where: { id: businessId },
    });
    assert.equal(dbBusiness?.subscriptionTier, 'gold');
    assert.equal(dbBusiness?.subscriptionStatus, 'active');
  });

  await t.test('POST /api/v1/subscription/verify-payment prevents duplicate replay attack', async () => {
    const secondOrderId = `order_replay_${Date.now()}`;
    const reusedPaymentId = `pay_reused_${Date.now()}`;

    // First order and payment succeeds
    await prisma.subscriptionOrder.create({
      data: {
        orderId: secondOrderId,
        businessId,
        tier: 'starter',
        amount: 57900,
        currency: 'INR',
        status: 'created',
      },
    });

    const signature1 = crypto
      .createHmac('sha256', config.razorpay.keySecret)
      .update(`${secondOrderId}|${reusedPaymentId}`)
      .digest('hex');

    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/subscription/verify-payment',
      headers: { authorization: `Bearer ${authToken}` },
      payload: {
        businessId,
        orderId: secondOrderId,
        paymentId: reusedPaymentId,
        signature: signature1,
      },
    });
    assert.equal(res1.statusCode, 200);

    // Attacker tries to reuse the same paymentId for a different third order
    const thirdOrderId = `order_attacker_${Date.now()}`;
    await prisma.subscriptionOrder.create({
      data: {
        orderId: thirdOrderId,
        businessId,
        tier: 'business_pro',
        amount: 499900,
        currency: 'INR',
        status: 'created',
      },
    });

    const attackerSignature = crypto
      .createHmac('sha256', config.razorpay.keySecret)
      .update(`${thirdOrderId}|${reusedPaymentId}`)
      .digest('hex');

    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/subscription/verify-payment',
      headers: { authorization: `Bearer ${authToken}` },
      payload: {
        businessId,
        orderId: thirdOrderId,
        paymentId: reusedPaymentId,
        signature: attackerSignature,
      },
    });

    assert.equal(res2.statusCode, 400);
    const body2 = JSON.parse(res2.body);
    assert.ok(body2.error.includes('PAYMENT_ALREADY_USED'));
  });
});
