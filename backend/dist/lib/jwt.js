import jwt from 'jsonwebtoken';
import { config } from '../config.js';
export function signAccessToken(payload) {
    // Mobile business apps require long-lived sessions (90 days)
    return jwt.sign(payload, config.jwtSecret, { expiresIn: '90d' });
}
export function verifyAccessToken(token) {
    return jwt.verify(token, config.jwtSecret);
}
export function verifyExpiredToken(token) {
    return jwt.verify(token, config.jwtSecret, { ignoreExpiration: true });
}
