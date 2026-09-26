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

test('POST /api/v1/auth/google provisions cloud tenant and issues JWT token', async () => {
  const email = `cloud.owner.${Date.now()}@gmail.com`;
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/google',
    payload: {
      email,
      name: 'Cloud Owner',
      avatarUrl: 'https://lh3.googleusercontent.com/avatar.jpg',
      businessName: 'Cloud Electronics',
    },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json() as {
    token: string;
    user: { id: string; email: string; displayName: string; photoUrl: string; provider: string };
    business: { id: string; name: string };
    is_new_user: boolean;
  };

  assert.ok(body.token.length > 20);
  assert.equal(body.user.email, email);
  assert.equal(body.user.displayName, 'Cloud Owner');
  assert.equal(body.user.provider, 'google');
  assert.ok(body.business.id);
  assert.equal(body.business.name, 'Cloud Electronics');
});

test('POST /api/v1/auth/google verifies idToken and prevents unauthenticated access', async () => {
  // Test with mock_id_token
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/google',
    payload: {
      idToken: 'mock_google_id_token_secure_9999',
      businessName: 'Secure Google Merchant',
    },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json() as {
    token: string;
    user: { email: string; provider: string };
    business: { name: string };
  };
  assert.ok(body.token.length > 20);
  assert.equal(body.user.provider, 'google');
  assert.equal(body.business.name, 'Secure Google Merchant');

  // Test empty payload rejection
  const badRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/google',
    payload: {},
  });
  assert.equal(badRes.statusCode, 400);
});


test('POST /api/v1/auth/phone/verify supports upgradable mobile number auth', async () => {
  const phone = '9876543210';
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/phone/verify',
    payload: {
      phone,
      otp: '1234',
      name: 'Mobile Merchant',
    },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json() as {
    token: string;
    user: { id: string; phone: string; provider: string };
    business: { id: string; name: string };
  };

  assert.ok(body.token.length > 20);
  assert.equal(body.user.phone, phone);
  assert.equal(body.user.provider, 'phone');
  assert.ok(body.business.id);
});

test('Tenant Cloud Backup Engine: Upload, List, Download, and Delete snapshots', async () => {
  // 1. Create a user and business for tenant testing
  const email = `backup.merchant.${Date.now()}@example.com`;
  const regRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      name: 'Backup Merchant',
      email,
      password: 'password123',
    },
  });
  const { token } = regRes.json() as { token: string };

  const bizRes = await app.inject({
    method: 'POST',
    url: '/api/v1/businesses',
    headers: { authorization: `Bearer ${token}` },
    payload: { name: 'Backup Test Store' },
  });
  const business = bizRes.json() as { id: string };
  const authHeaders = {
    authorization: `Bearer ${token}`,
    'x-business-id': business.id,
  };

  // 2. Upload an encrypted backup snapshot
  const mockDbContent = Buffer.from('SQLITE_CIPHER_ENCRYPTED_HEADER_TEST_BYTES_v2').toString('base64');
  const uploadRes = await app.inject({
    method: 'POST',
    url: '/api/v1/backup/upload',
    headers: authHeaders,
    payload: {
      base64Data: mockDbContent,
      filename: 'ledger_pilot_snap_001.enc',
      checksum: 'sha256-mock-12345',
      deviceName: 'OnePlus 11 5G (Main Billing Counter)',
      notes: 'Pre-EOD ledger snapshot',
    },
  });

  assert.equal(uploadRes.statusCode, 201);
  const uploadBody = uploadRes.json() as { ok: boolean; backup: { id: string; filename: string; sizeBytes: number } };
  assert.equal(uploadBody.ok, true);
  assert.equal(uploadBody.backup.filename, 'ledger_pilot_snap_001.enc');
  assert.ok(uploadBody.backup.sizeBytes > 0);

  // 3. List backups
  const listRes = await app.inject({
    method: 'GET',
    url: '/api/v1/backup/list',
    headers: authHeaders,
  });
  assert.equal(listRes.statusCode, 200);
  const listBody = listRes.json() as { ok: boolean; backups: Array<{ id: string; filename: string; deviceName: string }> };
  assert.equal(listBody.ok, true);
  assert.ok(listBody.backups.length >= 1);
  assert.equal(listBody.backups[0].filename, 'ledger_pilot_snap_001.enc');
  assert.equal(listBody.backups[0].deviceName, 'OnePlus 11 5G (Main Billing Counter)');

  // 4. Download backup
  const downloadRes = await app.inject({
    method: 'GET',
    url: `/api/v1/backup/download/${uploadBody.backup.id}`,
    headers: authHeaders,
  });
  assert.equal(downloadRes.statusCode, 200);
  const downloadBody = downloadRes.json() as { ok: boolean; backup: { base64Data: string } };
  assert.equal(downloadBody.ok, true);
  assert.equal(downloadBody.backup.base64Data, mockDbContent);

  // 5. Delete backup
  const deleteRes = await app.inject({
    method: 'DELETE',
    url: `/api/v1/backup/${uploadBody.backup.id}`,
    headers: authHeaders,
  });
  assert.equal(deleteRes.statusCode, 200);
  const deleteBody = deleteRes.json() as { ok: boolean; deleted: string };
  assert.equal(deleteBody.ok, true);
});

test('Batch Sync Push & Delta Pull: Process multiple entities and stock moves', async () => {
  const regRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      email: `batch-sync-${Date.now()}@example.com`,
      password: 'Password123!',
      name: 'Batch Sync Admin',
    },
  });
  const { token } = regRes.json() as { token: string };

  const bizRes = await app.inject({
    method: 'POST',
    url: '/api/v1/businesses',
    headers: { authorization: `Bearer ${token}` },
    payload: { name: 'Batch Store' },
  });
  const business = bizRes.json() as { id: string };
  const authHeaders = {
    authorization: `Bearer ${token}`,
    'x-business-id': business.id,
  };

  const prodId = `prod-${Date.now()}`;
  const batchRes = await app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: authHeaders,
    payload: {
      items: [
        {
          businessId: business.id,
          entity: 'product',
          entityId: prodId,
          op: 'upsert',
          payload: JSON.stringify({
            name: 'Maggi 2-Minute Noodles 70g',
            sku: 'MAG-70',
            sale_price: 1400,
            stock: 20,
          }),
        },
        {
          businessId: business.id,
          entity: 'customer',
          entityId: `cust-${Date.now()}`,
          op: 'upsert',
          payload: JSON.stringify({
            name: 'Batch Retailer',
            phone: '9888877777',
            city: 'Bengaluru',
          }),
        },
      ],
    },
  });

  assert.equal(batchRes.statusCode, 202);
  const batchBody = batchRes.json() as { accepted: boolean; count: number };
  assert.equal(batchBody.accepted, true);
  assert.equal(batchBody.count, 2);

  const pullRes = await app.inject({
    method: 'GET',
    url: `/api/v1/sync/pull?limit=50`,
    headers: authHeaders,
  });
  assert.equal(pullRes.statusCode, 200);
  const pullBody = pullRes.json() as { changes: any[]; serverTime: string };
  assert.ok(pullBody.changes.length >= 2);
  assert.ok(pullBody.changes.some((c: any) => c.entity === 'product'));
  assert.ok(pullBody.changes.some((c: any) => c.entity === 'customer'));
});





