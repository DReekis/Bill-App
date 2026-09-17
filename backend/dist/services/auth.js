import { hashPassword, verifyPassword } from '../lib/crypto.js';
import { signAccessToken } from '../lib/jwt.js';
import { prisma } from './db.js';
export async function registerUser(input) {
    const existing = await prisma.user.findUnique({ where: { email: input.email } });
    if (existing) {
        throw new Error('USER_EXISTS');
    }
    const user = await prisma.user.create({
        data: {
            name: input.name,
            email: input.email,
            passwordHash: await hashPassword(input.password),
            role: 'owner',
        },
    });
    const token = signAccessToken({ sub: user.id, email: user.email, role: user.role });
    return { token, user: { id: user.id, name: user.name, email: user.email, role: user.role } };
}
export async function loginUser(input) {
    const user = await prisma.user.findUnique({ where: { email: input.email } });
    if (!user) {
        throw new Error('INVALID_CREDENTIALS');
    }
    const valid = await verifyPassword(input.password, user.passwordHash);
    if (!valid) {
        throw new Error('INVALID_CREDENTIALS');
    }
    const token = signAccessToken({ sub: user.id, email: user.email, role: user.role });
    return { token, user: { id: user.id, name: user.name, email: user.email, role: user.role } };
}
