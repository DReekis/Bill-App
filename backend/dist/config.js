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
        clientId: process.env.GOOGLE_CLIENT_ID ||
            '1088562819881-tesapmissm77nd7o5maom90nh4sjv87h.apps.googleusercontent.com',
        clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? '',
        androidClientId: process.env.GOOGLE_ANDROID_CLIENT_ID ||
            '1088562819881-rv6kpg40eqnlsaqp196g5ligiqeujunr.apps.googleusercontent.com',
        iosClientId: process.env.GOOGLE_IOS_CLIENT_ID ||
            '1088562819881-sfbc09v1khbn6188ps24o2kd5qmp39hu.apps.googleusercontent.com',
    },
    razorpay: {
        keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_TlVBcJ5F1D187V',
        keySecret: process.env.RAZORPAY_KEY_SECRET || 'wEQAJKA0T1iJNITsDV9jRRI3',
        webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || 'wEQAJKA0T1iJNITsDV9jRRI3',
    },
    sandbox: {
        apiKey: process.env.SANDBOX_API_KEY || 'key_live_23b25d5294db404da8ff74be13354c73',
        apiSecret: process.env.SANDBOX_API_SECRET || '',
        baseUrl: process.env.SANDBOX_BASE_URL || 'https://api.sandbox.co.in',
    },
    sentry: {
        dsn: process.env.SENTRY_DSN || 'https://b81fe0dccbe91fc92f403d905cdf88d4@o4512214034677760.ingest.us.sentry.io/4512230552043520',
        environment: process.env.NODE_ENV || 'production',
    },
};
export const ALLOWED_GOOGLE_CLIENT_IDS = [
    config.google.clientId,
    config.google.androidClientId,
    config.google.iosClientId,
].filter(Boolean);
