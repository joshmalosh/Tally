import { Request, Response, NextFunction } from 'express';

// NOTE: This is an in-process, single-instance rate limiter suitable for
// development and single-server deployments. For production environments with
// multiple server instances, replace this with a Redis-backed solution
// (e.g. `rate-limiter-flexible` or `express-rate-limit` with a Redis store).

interface RateLimitOptions {
  windowMs: number;
  maxRequests: number;
}

function createRateLimiter({ windowMs, maxRequests }: RateLimitOptions) {
  const requestCounts = new Map<string, { count: number; resetAt: number }>();

  // Prune expired entries periodically to prevent unbounded memory growth.
  setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of requestCounts) {
      if (now > entry.resetAt) requestCounts.delete(key);
    }
  }, windowMs);

  return function rateLimitMiddleware(req: Request, res: Response, next: NextFunction): void {
    const key = req.ip ?? 'unknown';
    const now = Date.now();
    const entry = requestCounts.get(key);

    if (!entry || now > entry.resetAt) {
      requestCounts.set(key, { count: 1, resetAt: now + windowMs });
      next();
      return;
    }

    entry.count++;
    if (entry.count > maxRequests) {
      res.status(429).json({ code: 'RATE_LIMITED', message: 'Too many requests. Please try again later.' });
      return;
    }
    next();
  };
}

// General API: 100 requests per minute.
export const rateLimit = createRateLimiter({ windowMs: 60_000, maxRequests: 100 });

// Auth endpoints: 10 attempts per minute — slows brute-force credential attacks.
export const authRateLimit = createRateLimiter({ windowMs: 60_000, maxRequests: 10 });
