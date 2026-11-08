import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export function signAccessToken(payload: Record<string, unknown>): string {
  // Mobile business apps require long-lived sessions (90 days)
  return jwt.sign(payload, config.jwtSecret, { expiresIn: '90d' });
}

export function verifyAccessToken(token: string): Record<string, unknown> {
  return jwt.verify(token, config.jwtSecret) as Record<string, unknown>;
}

export function verifyExpiredToken(token: string): Record<string, unknown> {
  return jwt.verify(token, config.jwtSecret, { ignoreExpiration: true }) as Record<string, unknown>;
}
