import test from 'node:test';
import assert from 'node:assert/strict';
import { app } from '../src/server.js';
import { prisma } from '../src/services/db.js';

test('Admin REST API Suite', async (t) => {
  const adminEmail = `admin-${Date.now()}@example.com`;
  let adminToken = '';
  let businessId = '';

  await t.test('POST /api/v1/auth/register creates an owner user', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        name: 'System SuperAdmin',
        email: adminEmail,
        password: 'password123',
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.body);
    assert.ok(body.token);
    assert.equal(body.user.role, 'owner');
    adminToken = body.token;
  });

  await t.test('POST /api/v1/admin/login authenticates admin user', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/login',
      payload: {
        email: adminEmail,
        password: 'password123',
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.ok(body.token);
    assert.equal(body.user.email, adminEmail);
  });

  await t.test('POST /api/v1/businesses creates a business for testing', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/businesses',
      headers: { authorization: `Bearer ${adminToken}` },
      payload: {
        name: 'Admin Test Corporation',
        ownerName: 'System SuperAdmin',
        gstin: '29ABCDE1234F1Z5',
        city: 'Bengaluru',
        state: 'Karnataka',
        currency: 'INR',
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.body);
    businessId = body.id;
    assert.ok(businessId);
  });

  await t.test('GET /api/v1/admin/overview returns aggregated platform metrics', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/overview',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.ok(body.totalBusinesses >= 1);
    assert.ok(body.totalUsers >= 1);
    assert.ok(body.syncStats);
    assert.ok(Array.isArray(body.tierBreakdown));
  });

  await t.test('GET /api/v1/admin/businesses lists businesses with counts and revenue', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/businesses',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(res.statusCode, 200);
    const list = JSON.parse(res.body);
    assert.ok(Array.isArray(list));
    const target = list.find((b: any) => b.id === businessId);
    assert.ok(target);
    assert.equal(target.name, 'Admin Test Corporation');
    assert.equal(target.subscriptionTier, 'pro');
    assert.equal(target.subscriptionStatus, 'active');
  });

  await t.test('PATCH /api/v1/admin/businesses/:id/subscription modifies tier and grace mode', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/businesses/${businessId}/subscription`,
      headers: { authorization: `Bearer ${adminToken}` },
      payload: {
        tier: 'enterprise',
        status: 'grace_period',
        maxDevices: 10,
        expiresAt: '2027-12-31T23:59:59.000Z',
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.equal(body.subscriptionTier, 'enterprise');
    assert.equal(body.subscriptionStatus, 'grace_period');
    assert.equal(body.maxDevices, 10);
  });

  await t.test('GET /api/v1/admin/users lists platform users', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/users',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(res.statusCode, 200);
    const users = JSON.parse(res.body);
    assert.ok(Array.isArray(users));
    assert.ok(users.some((u: any) => u.email === adminEmail));
  });

  await t.test('GET /api/v1/admin/health returns live database and memory telemetry', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/health',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(res.statusCode, 200);
    const health = JSON.parse(res.body);
    assert.equal(health.status, 'healthy');
    assert.ok(health.database.sizeBytes >= 0);
    assert.ok(health.system.memory.rssMb);
  });

  await t.test('POST & GET /api/v1/admin/backups generates and lists atomic SQLite snapshots', async () => {
    const createRes = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/backups',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(createRes.statusCode, 201);
    const backup = JSON.parse(createRes.body);
    assert.ok(backup.filename);
    assert.ok(backup.sizeBytes > 0);

    const listRes = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/backups',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(listRes.statusCode, 200);
    const list = JSON.parse(listRes.body);
    assert.ok(Array.isArray(list));
    assert.ok(list.some((b: any) => b.filename === backup.filename));
  });

  await t.test('GET /api/v1/admin/audit-logs returns administrative audit trail', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/audit-logs',
      headers: { authorization: `Bearer ${adminToken}` },
    });

    assert.equal(res.statusCode, 200);
    const logs = JSON.parse(res.body);
    assert.ok(Array.isArray(logs));
    assert.ok(logs.some((l: any) => l.action === 'UPDATE_SUBSCRIPTION'));
  });

  await t.test('GET /admin and static files are served cleanly', async () => {
    // Redirect test
    const redirectRes = await app.inject({
      method: 'GET',
      url: '/admin',
    });
    assert.equal(redirectRes.statusCode, 302);
    assert.equal(redirectRes.headers.location, '/admin/');

    // HTML shell test
    const htmlRes = await app.inject({
      method: 'GET',
      url: '/admin/',
    });
    assert.equal(htmlRes.statusCode, 200);
    assert.ok(htmlRes.headers['content-type']?.includes('text/html'));
    assert.ok(htmlRes.body.includes('Billket Executive Cloud Admin'));

    // CSS stylesheet test
    const cssRes = await app.inject({
      method: 'GET',
      url: '/admin/css/admin.css',
    });
    assert.equal(cssRes.statusCode, 200);
    assert.ok(cssRes.headers['content-type']?.includes('text/css'));
    assert.ok(cssRes.body.includes('--bg-app'));

    // JS module test
    const jsRes = await app.inject({
      method: 'GET',
      url: '/admin/js/admin.js',
    });
    assert.equal(jsRes.statusCode, 200);
    assert.ok(jsRes.headers['content-type']?.includes('javascript'));
    assert.ok(jsRes.body.includes('Billket Executive Cloud Admin'));
  });
});
