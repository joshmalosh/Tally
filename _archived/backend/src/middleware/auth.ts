import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { env } from '../config/env.js';

export interface AuthRequest extends Request {
  userId?: string;
}

// In-process token revocation list.
// Maps jti → expiry timestamp (ms). Entries are pruned lazily on each request
// and eagerly every 15 minutes to prevent unbounded memory growth.
//
// NOTE: For multi-instance deployments this must be replaced with a shared
// store (e.g. Redis SET with TTL) so that a logout on one instance invalidates
// the token across all instances.
const revokedTokens = new Map<string, number>();

setInterval(() => {
  const now = Date.now();
  for (const [jti, expiry] of revokedTokens) {
    if (now > expiry) revokedTokens.delete(jti);
  }
}, 15 * 60 * 1000);

export function revokeToken(jti: string, expiresAt: number): void {
  revokedTokens.set(jti, expiresAt);
}

export function requireAuth(req: AuthRequest, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ code: 'UNAUTHORIZED', message: 'Missing or invalid authorization header.' });
    return;
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, env.jwtSecret) as { sub: string; jti: string; exp: number };

    // Reject tokens that have been explicitly revoked (e.g. after logout).
    if (revokedTokens.has(payload.jti)) {
      res.status(401).json({ code: 'UNAUTHORIZED', message: 'Token has been revoked.' });
      return;
    }

    req.userId = payload.sub;
    next();
  } catch {
    res.status(401).json({ code: 'UNAUTHORIZED', message: 'Invalid or expired token.' });
  }
}

export function generateToken(userId: string): { token: string; jti: string; expiresAt: number } {
  const jti = uuidv4();
  // 7-day expiry. Short enough to limit exposure from stolen tokens; long
  // enough to avoid frequent re-logins for active users.
  const expiresIn = 7 * 24 * 60 * 60; // seconds
  const expiresAt = Date.now() + expiresIn * 1000;
  const token = jwt.sign({ sub: userId, jti }, env.jwtSecret, { expiresIn });
  return { token, jti, expiresAt };
}
