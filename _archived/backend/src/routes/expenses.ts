import { Router, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { expenses } from '../db/schema.js';
import { eq, and, isNull, gte, lte, desc, sql, count } from 'drizzle-orm';
import { requireAuth, type AuthRequest } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { FREE_TIER_LIMITS } from '../types/index.js';

const router = Router();

router.use(requireAuth);

function isValidCalendarDate(s: string): boolean {
  const d = new Date(s);
  return !isNaN(d.getTime()) && s === d.toISOString().slice(0, 10);
}

const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be in YYYY-MM-DD format.')
  .refine(isValidCalendarDate, 'Invalid calendar date.');

const createExpenseSchema = z.object({
  amountCents: z.number().int().min(0),
  currency: z.string().length(3),
  date: isoDate,
  description: z.string().max(500).optional(),
  merchant: z.string().max(255).optional(),
  categoryId: z.string().uuid(),
  subtagId: z.string().uuid().optional(),
  notes: z.string().max(2000).optional(),
  source: z.enum(['camera', 'upload', 'manual']),
});

const updateExpenseSchema = z.object({
  amountCents: z.number().int().min(0).optional(),
  currency: z.string().length(3).optional(),
  date: isoDate.optional(),
  description: z.string().max(500).nullable().optional(),
  merchant: z.string().max(255).nullable().optional(),
  categoryId: z.string().uuid().optional(),
  subtagId: z.string().uuid().nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
});

const listQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
  startDate: isoDate.optional(),
  endDate: isoDate.optional(),
  categoryId: z.string().uuid().optional(),
  subtagId: z.string().uuid().optional(),
  search: z.string().max(100).optional(),
});

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const query = listQuerySchema.parse(req.query);
    const conditions = [
      eq(expenses.userId, req.userId!),
      isNull(expenses.deletedAt),
    ];

    if (query.startDate) conditions.push(gte(expenses.date, query.startDate));
    if (query.endDate) conditions.push(lte(expenses.date, query.endDate));
    if (query.categoryId) conditions.push(eq(expenses.categoryId, query.categoryId));
    if (query.subtagId) conditions.push(eq(expenses.subtagId, query.subtagId));

    const where = and(...conditions);
    const offset = (query.page - 1) * query.pageSize;

    const [data, [{ total }]] = await Promise.all([
      db.select()
        .from(expenses)
        .where(where)
        .orderBy(desc(expenses.date), desc(expenses.createdAt))
        .limit(query.pageSize)
        .offset(offset),
      db.select({ total: count() })
        .from(expenses)
        .where(where),
    ]);

    res.json({ data, total, page: query.page, pageSize: query.pageSize });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ code: 'VALIDATION_ERROR', message: err.message });
      return;
    }
    console.error('List expenses error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to fetch expenses.' });
  }
});

router.get('/monthly-total', async (req: AuthRequest, res: Response) => {
  try {
    const { month, currency = 'USD' } = req.query as { month?: string; currency?: string };
    const now = new Date();
    const year = month ? parseInt(month.toString().slice(0, 4)) : now.getFullYear();
    const monthIdx = month ? parseInt(month.toString().slice(5, 7)) : now.getMonth() + 1;
    const startDate = `${year}-${String(monthIdx).padStart(2, '0')}-01`;
    const endDay = new Date(year, monthIdx, 0).getDate();
    const endDate = `${year}-${String(monthIdx).padStart(2, '0')}-${String(endDay).padStart(2, '0')}`;

    const [result] = await db.select({
      totalCents: sql<number>`COALESCE(SUM(${expenses.amountCents}), 0)`,
      expenseCount: count(),
    })
      .from(expenses)
      .where(and(
        eq(expenses.userId, req.userId!),
        isNull(expenses.deletedAt),
        eq(expenses.currency, currency),
        gte(expenses.date, startDate),
        lte(expenses.date, endDate),
      ));

    res.json({ totalCents: Number(result.totalCents), currency, expenseCount: result.expenseCount });
  } catch (err) {
    console.error('Monthly total error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to calculate monthly total.' });
  }
});

router.get('/upload-count', async (req: AuthRequest, res: Response) => {
  try {
    const now = new Date();
    const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;

    const [result] = await db.select({ count: count() })
      .from(expenses)
      .where(and(
        eq(expenses.userId, req.userId!),
        isNull(expenses.deletedAt),
        gte(expenses.date, startDate),
        sql`${expenses.source} IN ('camera', 'upload')`,
      ));

    res.json({
      count: result.count,
      limit: FREE_TIER_LIMITS.uploadsPerMonth,
      remaining: Math.max(0, FREE_TIER_LIMITS.uploadsPerMonth - result.count),
    });
  } catch (err) {
    console.error('Upload count error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to check upload count.' });
  }
});

router.get('/:id', async (req: AuthRequest, res: Response) => {
  try {
    const [expense] = await db.select()
      .from(expenses)
      .where(and(
        eq(expenses.id, req.params.id),
        eq(expenses.userId, req.userId!),
        isNull(expenses.deletedAt),
      ))
      .limit(1);

    if (!expense) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Expense not found.' });
      return;
    }

    res.json(expense);
  } catch (err) {
    console.error('Get expense error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to fetch expense.' });
  }
});

router.post('/', validate(createExpenseSchema), async (req: AuthRequest, res: Response) => {
  try {
    const body = req.body;

    const [expense] = await db.insert(expenses).values({
      userId: req.userId!,
      amountCents: body.amountCents,
      currency: body.currency,
      date: body.date,
      description: body.description ?? null,
      merchant: body.merchant ?? null,
      categoryId: body.categoryId,
      subtagId: body.subtagId ?? null,
      notes: body.notes ?? null,
      source: body.source,
    }).returning();

    res.status(201).json(expense);
  } catch (err) {
    console.error('Create expense error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to create expense.' });
  }
});

router.patch('/:id', validate(updateExpenseSchema), async (req: AuthRequest, res: Response) => {
  try {
    const [existing] = await db.select({ id: expenses.id })
      .from(expenses)
      .where(and(
        eq(expenses.id, req.params.id),
        eq(expenses.userId, req.userId!),
        isNull(expenses.deletedAt),
      ))
      .limit(1);

    if (!existing) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Expense not found.' });
      return;
    }

    const [updated] = await db.update(expenses)
      .set({ ...req.body, updatedAt: new Date() })
      .where(eq(expenses.id, req.params.id))
      .returning();

    res.json(updated);
  } catch (err) {
    console.error('Update expense error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to update expense.' });
  }
});

router.delete('/:id', async (req: AuthRequest, res: Response) => {
  try {
    const [existing] = await db.select({ id: expenses.id })
      .from(expenses)
      .where(and(
        eq(expenses.id, req.params.id),
        eq(expenses.userId, req.userId!),
        isNull(expenses.deletedAt),
      ))
      .limit(1);

    if (!existing) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Expense not found.' });
      return;
    }

    await db.update(expenses)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(eq(expenses.id, req.params.id));

    res.status(204).end();
  } catch (err) {
    console.error('Delete expense error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to delete expense.' });
  }
});

export default router;
