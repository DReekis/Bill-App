import assert from 'node:assert/strict';
import test from 'node:test';

import { app } from '../src/server.js';

test('Google Play Console Test Phone (9999999999) bypasses SMS gateway and signs in with 123456', async () => {
  // 1. Request OTP for 9999999999
  const otpRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/phone/otp',
    payload: { phone: '9999999999' },
  });

  assert.equal(otpRes.statusCode, 200);
  const otpBody = otpRes.json();
  assert.equal(otpBody.success, true);
  assert.equal(otpBody.isTestMode, true);
  assert.ok(otpBody.sessionId);

  // 2. Verify OTP with static test OTP 123456
  const verifyRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/phone/verify',
    payload: {
      phone: '9999999999',
      otp: '123456',
      sessionId: otpBody.sessionId,
    },
  });

  assert.equal(verifyRes.statusCode, 200);
  const auth = verifyRes.json();
  assert.ok(auth.token, 'Must return JWT auth token');
  assert.equal(auth.user.phone, '9999999999');
  assert.equal(auth.user.name, 'Google Play Reviewer');
  assert.equal(auth.user.role, 'owner');
  assert.equal(auth.business.name, 'Billket Superstore');
});

test('Google Play Console Test Phone also accepts 4-digit OTP 1234', async () => {
  const otpRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/phone/otp',
    payload: { phone: '9876543210' },
  });

  assert.equal(otpRes.statusCode, 200);

  const verifyRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/phone/verify',
    payload: {
      phone: '9876543210',
      otp: '1234',
    },
  });

  assert.equal(verifyRes.statusCode, 200);
  const auth = verifyRes.json();
  assert.ok(auth.token);
  assert.equal(auth.user.role, 'owner');
});
