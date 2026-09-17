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
