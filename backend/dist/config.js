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
        apiKey: process.env.SANDBOX_API_KEY || 'key_live_6000130d928043638b3d70dd31d79f6c',
        apiSecret: process.env.SANDBOX_API_SECRET || 'secret_live_a36390af553441d5907967ddb7c14ad8',
        baseUrl: process.env.SANDBOX_BASE_URL || 'https://api.sandbox.co.in',
    },
};
export const ALLOWED_GOOGLE_CLIENT_IDS = [
    config.google.clientId,
    config.google.androidClientId,
    config.google.iosClientId,
].filter(Boolean);
