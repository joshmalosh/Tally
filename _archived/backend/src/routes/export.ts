import { Router, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { expenses, categories, subtags } from '../db/schema.js';
import { eq, and, isNull, gte, lte, or, asc } from 'drizzle-orm';
import { requireAuth, type AuthRequest } from '../middleware/auth.js';

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

const exportQuerySchema = z.object({
  startDate: isoDate,
  endDate: isoDate,
  categoryId: z.string().uuid().optional(),
  format: z.enum(['csv', 'zip']).default('csv'),
});

function csvEscape(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const query = exportQuerySchema.parse(req.query);

    if (query.format === 'zip') {
      // TODO: Check Pro subscription status before allowing ZIP export
      res.status(403).json({ code: 'PRO_REQUIRED', message: 'ZIP export requires a Pro subscription. Go Pro for unlimited exports with attachments.' });
      return;
    }

    const conditions = [
      eq(expenses.userId, req.userId!),
      isNull(expenses.deletedAt),
      gte(expenses.date, query.startDate),
      lte(expenses.date, query.endDate),
    ];
    if (query.categoryId) conditions.push(eq(expenses.categoryId, query.categoryId));

    const [expenseRows, categoryRows, subtagRows] = await Promise.all([
      db.select()
        .from(expenses)
        .where(and(...conditions))
        .orderBy(asc(expenses.date)),
      db.select()
        .from(categories)
        .where(or(isNull(categories.userId), eq(categories.userId, req.userId!))),
      db.select()
        .from(subtags)
        .where(eq(subtags.userId, req.userId!)),
    ]);

    const categoryMap = new Map(categoryRows.map((c) => [c.id, c.name]));
    const subtagMap = new Map(subtagRows.map((s) => [s.id, s.name]));

    const header = 'date,description,merchant,amount,currency,category,subtag,notes,attachment_filename,source,created_at';
    const rows = expenseRows.map((e) => {
      const amount = (e.amountCents / 100).toFixed(2);
      return [
        e.date,
        csvEscape(e.description ?? ''),
        csvEscape(e.merchant ?? ''),
        amount,
        e.currency,
        csvEscape(categoryMap.get(e.categoryId) ?? 'Uncategorized'),
        csvEscape(e.subtagId ? subtagMap.get(e.subtagId) ?? '' : ''),
        csvEscape(e.notes ?? ''),
        csvEscape(e.attachmentKey ?? ''),
        e.source,
        e.createdAt.toISOString(),
      ].join(',');
    });

    const csv = [header, ...rows].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="expenses_${query.startDate}_to_${query.endDate}.csv"`);
    res.send(csv);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ code: 'VALIDATION_ERROR', message: err.message });
      return;
    }
    console.error('Export error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to export expenses.' });
  }
});

export default router;
