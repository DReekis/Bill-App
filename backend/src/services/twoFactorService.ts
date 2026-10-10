import { config } from '../config.js';

interface OtpSession {
  sessionId: string;
  expiresAt: number;
  lastSentAt: number;
}

export class TwoFactorService {
  private static instance: TwoFactorService;
  private sessions = new Map<string, OtpSession>();

  public static getInstance(): TwoFactorService {
    if (!TwoFactorService.instance) {
      TwoFactorService.instance = new TwoFactorService();
    }
    return TwoFactorService.instance;
  }

  /**
   * Sanitizes phone number to standard 10-digit Indian mobile format.
   */
  public cleanPhone(rawPhone: string): string {
    const digits = (rawPhone || '').replace(/\D/g, '');
    return digits.length >= 10 ? digits.slice(-10) : digits;
  }

  /**
   * Validates standard 10-digit Indian mobile numbers.
   */
  public isValidIndianPhone(cleanPhone: string): boolean {
    return /^[6-9]\d{9}$/.test(cleanPhone);
  }

  /**
   * Dispatches OTP via 2Factor.in SMS Gateway.
   */
  public async sendOtp(rawPhone: string): Promise<{
    success: boolean;
    sessionId?: string;
    message?: string;
    isTestMode?: boolean;
  }> {
    const phone = this.cleanPhone(rawPhone);
    if (!this.isValidIndianPhone(phone)) {
      return {
        success: false,
        message: 'Please provide a valid 10-digit Indian mobile number',
      };
    }

    // Cooldown check (25 seconds between requests for same number)
    const existing = this.sessions.get(phone);
    if (existing && Date.now() - existing.lastSentAt < 25000) {
      const waitSeconds = Math.ceil((25000 - (Date.now() - existing.lastSentAt)) / 1000);
      return {
        success: false,
        message: `Please wait ${waitSeconds}s before requesting a new OTP`,
      };
    }

    // Fast-path for unit tests or dedicated test phone
    if (config.nodeEnv === 'test' || phone === '9876543210') {
      const mockSessionId = `test_session_${phone}_${Date.now()}`;
      this.sessions.set(phone, {
        sessionId: mockSessionId,
        expiresAt: Date.now() + 5 * 60 * 1000,
        lastSentAt: Date.now(),
      });
      return {
        success: true,
        sessionId: mockSessionId,
        isTestMode: true,
        message: 'OTP sent in test mode (Use 1234)',
      };
    }

    const { apiKey, baseUrl } = config.twoFactor;
    if (!apiKey) {
      return {
        success: false,
        message: 'SMS gateway is not configured',
      };
    }

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 7000);
      const url = `${baseUrl}/${apiKey}/SMS/${phone}/AUTOGEN`;

      const res = await fetch(url, {
        method: 'GET',
        signal: controller.signal,
        headers: { Accept: 'application/json' },
      });
      clearTimeout(timeout);

      const json: any = await res.json().catch(() => null);

      if (res.ok && json?.Status === 'Success' && json?.Details) {
        const sessionId = String(json.Details);
        this.sessions.set(phone, {
          sessionId,
          expiresAt: Date.now() + 5 * 60 * 1000,
          lastSentAt: Date.now(),
        });
        return {
          success: true,
          sessionId,
          message: 'OTP sent successfully via SMS',
        };
      }

      return {
        success: false,
        message: json?.Details || 'Failed to dispatch SMS through gateway',
      };
    } catch (err: any) {
      return {
        success: false,
        message: err?.message || 'Gateway network timeout while dispatching SMS',
      };
    }
  }

  /**
   * Verifies OTP against 2Factor.in SMS Gateway session.
   */
  public async verifyOtp(
    rawPhone: string,
    rawOtp: string,
    explicitSessionId?: string,
  ): Promise<{ success: boolean; message?: string }> {
    const phone = this.cleanPhone(rawPhone);
    const otp = (rawOtp || '').trim();

    if (!otp) {
      return { success: false, message: 'Please enter the OTP' };
    }

    // Fast-path for unit tests or dedicated test phone
    if (config.nodeEnv === 'test' || phone === '9876543210') {
      if (otp === '1234' || otp === '0000') {
        this.sessions.delete(phone);
        return { success: true };
      }
    }

    const session = this.sessions.get(phone);
    const sessionId = explicitSessionId || session?.sessionId;

    if (!sessionId) {
      return {
        success: false,
        message: 'No active OTP session found. Please request a new OTP.',
      };
    }

    if (session && Date.now() > session.expiresAt) {
      this.sessions.delete(phone);
      return {
        success: false,
        message: 'OTP has expired. Please request a new OTP.',
      };
    }

    const { apiKey, baseUrl } = config.twoFactor;
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 7000);
      const url = `${baseUrl}/${apiKey}/SMS/VERIFY/${sessionId}/${otp}`;

      const res = await fetch(url, {
        method: 'GET',
        signal: controller.signal,
        headers: { Accept: 'application/json' },
      });
      clearTimeout(timeout);

      const json: any = await res.json().catch(() => null);

      if (res.ok && json?.Status === 'Success' && json?.Details === 'OTP Matched') {
        this.sessions.delete(phone);
        return { success: true };
      }

      return {
        success: false,
        message: json?.Details || 'Invalid OTP entered',
      };
    } catch (err: any) {
      return {
        success: false,
        message: err?.message || 'Gateway connection error during OTP verification',
      };
    }
  }
}
