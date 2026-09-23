import assert from 'node:assert/strict';
import test from 'node:test';

import { app } from '../src/server.js';

test('GET /health is public', async () => {
  const response = await app.inject({
    method: 'GET',
    url: '/health',
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    ok: true,
    service: 'pricepilot-bill-backend',
  });
});

test('POST /api/v1/auth/register creates a user and token', async () => {
  const email = `test.user.${Date.now()}@example.com`;
  const response = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      name: 'Test User',
      email,
      password: 'secret123',
    },
  });

  assert.equal(response.statusCode, 201);
  const body = response.json() as { token: string; user: { email: string } };
  assert.equal(body.user.email, email);
  assert.ok(body.token.length > 20);
});

test('GET /api/v1/businesses requires a bearer token', async () => {
  const response = await app.inject({
    method: 'GET',
    url: '/api/v1/businesses',
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error, 'Missing bearer token');
});

test('Full Business Flow: Entities, Sync Push & Pull', async () => {
  // 1. Register user
  const email = `flow.user.${Date.now()}@example.com`;
  const regRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      name: 'Flow User',
      email,
      password: 'secret123',
    },
  });
  const { token } = regRes.json() as { token: string };
  const authHeaders = { authorization: `Bearer ${token}` };

  // 2. Create Business
  const bizRes = await app.inject({
    method: 'POST',
    url: '/api/v1/businesses',
    headers: authHeaders,
    payload: {
      name: 'Retail Traders Hub',
      currency: 'INR',
    },
  });
  assert.equal(bizRes.statusCode, 201);
  const business = bizRes.json() as { id: string; name: string };
  const bizHeaders = { ...authHeaders, 'x-business-id': business.id };

  // 3. Create Supplier
  const supRes = await app.inject({
    method: 'POST',
    url: '/api/v1/suppliers',
    headers: bizHeaders,
    payload: {
      businessId: business.id,
      name: 'Evergreen Wholesalers',
      phone: '9876543210',
      state: 'Maharashtra',
    },
  });
  assert.equal(supRes.statusCode, 201);

  // 4. Create Bank Account & Cheque
  const bankRes = await app.inject({
    method: 'POST',
    url: '/api/v1/bank-accounts',
    headers: bizHeaders,
    payload: {
      businessId: business.id,
      bankName: 'State Bank of India',
      accountNumber: '1122334455',
      openingBalance: 50000,
    },
  });
  assert.equal(bankRes.statusCode, 201);

  const chqRes = await app.inject({
    method: 'POST',
    url: '/api/v1/cheques',
    headers: bizHeaders,
    payload: {
      businessId: business.id,
      chequeNumber: 'CHQ-9901',
      bankName: 'HDFC Bank',
      amount: 15000,
      date: new Date().toISOString(),
      type: 'in',
      status: 'Pending',
    },
  });
  assert.equal(chqRes.statusCode, 201);

  // 5. Test Sync Push (Materializes into DB)
  const pushRes = await app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: bizHeaders,
    payload: {
      businessId: business.id,
      entity: 'customer',
      entityId: `cust-sync-${Date.now()}`,
      op: 'upsert',
      payload: JSON.stringify({
        name: 'Aarav Sharma',
        phone: '9898989898',
        city: 'Pune',
      }),
      idempotencyKey: `key-cust-${Date.now()}`,
    },
  });
  assert.equal(pushRes.statusCode, 202);
  const pushBody = pushRes.json() as { accepted: boolean; record: { status: string } };
  assert.equal(pushBody.accepted, true);
  assert.equal(pushBody.record.status, 'synced');

  // 6. Test Sync Pull (Returns delta changes)
  const pullRes = await app.inject({
    method: 'GET',
    url: `/api/v1/sync/pull?since=${new Date(Date.now() - 60000).toISOString()}`,
    headers: bizHeaders,
  });
  assert.equal(pullRes.statusCode, 200);
  const pullBody = pullRes.json() as { changes: Array<{ entity: string }>; serverTime: string };
  assert.ok(Array.isArray(pullBody.changes));
  assert.ok(pullBody.changes.length >= 1);
  assert.ok(pullBody.serverTime);
});

test('GET /api/v1/gst/lookup/:gstin resolves business profile and deterministic fallback', async () => {
  // Test demo sandbox profile
  const demoRes = await app.inject({
    method: 'GET',
    url: '/api/v1/gst/lookup/29AAAAA0000A1Z5',
  });
  assert.equal(demoRes.statusCode, 200);
  const demoBody = demoRes.json() as any;
  assert.equal(demoBody.valid, true);
  assert.equal(demoBody.stateCode, '29');
  assert.equal(demoBody.state, 'Karnataka');
  assert.equal(demoBody.businessName, 'Modern Retail Store');
  assert.equal(demoBody.pan, 'AAAAA0000A');
  assert.equal(demoBody.constitution, 'Private Limited Company');

  // Test 16GPZPD6335F1ZH (Balaji Enterprise)
  const balajiRes = await app.inject({
    method: 'GET',
    url: '/api/v1/gst/lookup/16GPZPD6335F1ZH',
  });
  assert.equal(balajiRes.statusCode, 200);
  const balajiBody = balajiRes.json() as any;
  assert.equal(balajiBody.valid, true);
  assert.equal(balajiBody.stateCode, '16');
  assert.equal(balajiBody.state, 'Tripura');
  assert.equal(balajiBody.businessName, 'BALAJI ENTERPRISE');
  assert.equal(balajiBody.pan, 'GPZPD6335F');
  assert.equal(balajiBody.city, 'Dharmanagar');
  assert.equal(balajiBody.address, '09, Dharmanagar, Dharmanagar, North Tripura, Tripura');
  assert.equal(balajiBody.constitution, 'Sole Proprietorship');
});


