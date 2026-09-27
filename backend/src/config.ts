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
    clientId:
      process.env.GOOGLE_CLIENT_ID ||
      '594956382165-jgm12poc8g1lmtj38ilj87cu8upggban.apps.googleusercontent.com',
    clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? '',
    androidClientId:
      process.env.GOOGLE_ANDROID_CLIENT_ID ||
      '594956382165-f7qljarc4oepch4do89hmpe1sf2ro2is.apps.googleusercontent.com',
    iosClientId:
      process.env.GOOGLE_IOS_CLIENT_ID ||
      '594956382165-c8pqnkq6u5u75ldgohnuvjgv30t7i0pu.apps.googleusercontent.com',
  },
};

export const ALLOWED_GOOGLE_CLIENT_IDS = [
  config.google.clientId,
  config.google.androidClientId,
  config.google.iosClientId,
].filter(Boolean);

