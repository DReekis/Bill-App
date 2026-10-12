import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT ?? 4000),
  jwtSecret: process.env.JWT_SECRET ?? 'dev-secret-change-me',
  nodeEnv: process.env.NODE_ENV ?? 'development',
  admin: {
    email: process.env.ADMIN_EMAIL ?? 'admin@pricepilot.in',
    password: process.env.ADMIN_PASSWORD ?? '',
  },
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID || '',
    clientSecret: process.env.GOOGLE_CLIENT_SECRET || '',
    androidClientId: process.env.GOOGLE_ANDROID_CLIENT_ID || '',
    iosClientId: process.env.GOOGLE_IOS_CLIENT_ID || '',
  },
  razorpay: {
    keyId: process.env.RAZORPAY_KEY_ID || '',
    keySecret: process.env.RAZORPAY_KEY_SECRET || '',
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
  },
  sandbox: {
    apiKey: process.env.SANDBOX_API_KEY || '',
    apiSecret: process.env.SANDBOX_API_SECRET || '',
    baseUrl: process.env.SANDBOX_BASE_URL || 'https://api.sandbox.co.in',
  },
  twoFactor: {
    apiKey: process.env.TWOFACTOR_API_KEY || '',
    baseUrl: process.env.TWOFACTOR_BASE_URL || 'https://2factor.in/API/V1',
  },
};

export const ALLOWED_GOOGLE_CLIENT_IDS = [
  config.google.clientId,
  config.google.androidClientId,
  config.google.iosClientId,
].filter(Boolean);

