interface AttemptRecord {
  count: number;
  firstAttempt: number;
  blockedUntil?: number;
}

export class LoginRateLimiter {
  private attempts = new Map<string, AttemptRecord>();
  private readonly maxAttempts: number;
  private readonly windowMs: number;
  private readonly lockoutMs: number;

  constructor(options: { maxAttempts?: number; windowMs?: number; lockoutMs?: number } = {}) {
    this.maxAttempts = options.maxAttempts ?? 5; // Max 5 failed attempts
    this.windowMs = options.windowMs ?? 15 * 60 * 1000; // 15-minute window
    this.lockoutMs = options.lockoutMs ?? 15 * 60 * 1000; // 15-minute lockout
  }

  isBlocked(key: string): { blocked: boolean; remainingSeconds?: number } {
    const record = this.attempts.get(key);
    if (!record) return { blocked: false };

    const now = Date.now();
    if (record.blockedUntil && record.blockedUntil > now) {
      const remainingSeconds = Math.ceil((record.blockedUntil - now) / 1000);
      return { blocked: true, remainingSeconds };
    }

    if (now - record.firstAttempt > this.windowMs) {
      this.attempts.delete(key);
      return { blocked: false };
    }

    return { blocked: false };
  }

  recordFailure(key: string): { blocked: boolean; remainingAttempts: number; remainingSeconds?: number } {
    const now = Date.now();
    let record = this.attempts.get(key);

    if (!record || (now - record.firstAttempt > this.windowMs)) {
      record = { count: 1, firstAttempt: now };
      this.attempts.set(key, record);
      return { blocked: false, remainingAttempts: this.maxAttempts - 1 };
    }

    record.count += 1;
    if (record.count >= this.maxAttempts) {
      record.blockedUntil = now + this.lockoutMs;
      const remainingSeconds = Math.ceil(this.lockoutMs / 1000);
      return { blocked: true, remainingAttempts: 0, remainingSeconds };
    }

    return { blocked: false, remainingAttempts: this.maxAttempts - record.count };
  }

  recordSuccess(key: string): void {
    this.attempts.delete(key);
  }

  reset(): void {
    this.attempts.clear();
  }
}

export const adminLoginLimiter = new LoginRateLimiter();
