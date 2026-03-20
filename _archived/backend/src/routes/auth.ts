import { Router, Request, Response } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { db } from '../db/index.js';
import { users } from '../db/schema.js';
import { eq } from 'drizzle-orm';
import { generateToken, requireAuth, revokeToken, type AuthRequest } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

const router = Router();

// Password must be at least 8 characters and contain at least one uppercase
// letter, one lowercase letter, and one digit.
const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters.')
  .regex(/[A-Z]/, 'Password must contain at least one uppercase letter.')
  .regex(/[a-z]/, 'Password must contain at least one lowercase letter.')
  .regex(/[0-9]/, 'Password must contain at least one number.');

const registerSchema = z.object({
  email: z.string().email(),
  password: passwordSchema,
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

router.post('/register', validate(registerSchema), async (req: Request, res: Response) => {
  try {
    const { email, password } = req.body;

    const existing = await db.select({ id: users.id })
      .from(users)
      .where(eq(users.email, email))
      .limit(1);

    if (existing.length > 0) {
      res.status(409).json({ code: 'EMAIL_EXISTS', message: 'An account with this email already exists.' });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const [user] = await db.insert(users).values({
      email,
      authProvider: 'email',
      passwordHash,
    }).returning({ id: users.id, email: users.email });

    const { token } = generateToken(user.id);
    res.status(201).json({ token, user: { id: user.id, email: user.email } });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to create account.' });
  }
});

router.post('/login', validate(loginSchema), async (req: Request, res: Response) => {
  try {
    const { email, password } = req.body;

    const [user] = await db.select()
      .from(users)
      .where(eq(users.email, email))
      .limit(1);

    // Use a constant-time comparison path regardless of whether the user
    // exists, to prevent user enumeration via timing differences.
    const dummyHash = '$2a$12$invalidhashpadding000000000000000000000000000000000000';
    const hashToCompare = user?.passwordHash ?? dummyHash;
    const valid = await bcrypt.compare(password, hashToCompare);

    if (!user || !user.passwordHash || !valid) {
      res.status(401).json({ code: 'INVALID_CREDENTIALS', message: 'Invalid email or password.' });
      return;
    }

    const { token } = generateToken(user.id);
    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        subscriptionStatus: user.subscriptionStatus,
      },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Login failed.' });
  }
});

// Logout: adds the token's jti to the revocation list so it can't be reused
// even before its natural expiry.
router.post('/logout', requireAuth, (req: AuthRequest, res: Response) => {
  const header = req.headers.authorization!;
  const token = header.slice(7);

  try {
    // jwt.verify already ran in requireAuth, so this decode is safe.
    const payload = JSON.parse(
      Buffer.from(token.split('.')[1], 'base64url').toString('utf8')
    ) as { jti: string; exp: number };

    revokeToken(payload.jti, payload.exp * 1000);
    res.status(204).end();
  } catch {
    res.status(400).json({ code: 'BAD_REQUEST', message: 'Could not parse token.' });
  }
});

router.get('/me', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const [user] = await db.select({
      id: users.id,
      email: users.email,
      subscriptionStatus: users.subscriptionStatus,
      subscriptionProvider: users.subscriptionProvider,
      createdAt: users.createdAt,
    })
      .from(users)
      .where(eq(users.id, req.userId!))
      .limit(1);

    if (!user) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'User not found.' });
      return;
    }

    res.json(user);
  } catch (err) {
    console.error('Get user error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to fetch user.' });
  }
});

export default router;
