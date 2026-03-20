import { Router, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { categories, subtags } from '../db/schema.js';
import { eq, or, isNull, and, asc } from 'drizzle-orm';
import { requireAuth, type AuthRequest } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

const router = Router();

router.use(requireAuth);

const createCategorySchema = z.object({
  name: z.string().min(1).max(100),
  sortOrder: z.number().int().min(0).optional(),
});

const createSubtagSchema = z.object({
  categoryId: z.string().uuid(),
  name: z.string().min(1).max(100),
});

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const cats = await db.select()
      .from(categories)
      .where(or(isNull(categories.userId), eq(categories.userId, req.userId!)))
      .orderBy(asc(categories.sortOrder));

    res.json(cats);
  } catch (err) {
    console.error('List categories error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to fetch categories.' });
  }
});

router.post('/', validate(createCategorySchema), async (req: AuthRequest, res: Response) => {
  try {
    const [cat] = await db.insert(categories).values({
      userId: req.userId!,
      name: req.body.name,
      sortOrder: req.body.sortOrder ?? 0,
    }).returning();

    res.status(201).json(cat);
  } catch (err) {
    console.error('Create category error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to create category.' });
  }
});

router.patch('/:id', validate(createCategorySchema), async (req: AuthRequest, res: Response) => {
  try {
    const [existing] = await db.select()
      .from(categories)
      .where(and(eq(categories.id, req.params.id), eq(categories.userId, req.userId!)))
      .limit(1);

    if (!existing) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Category not found or is a system default.' });
      return;
    }

    const [updated] = await db.update(categories)
      .set({ name: req.body.name, sortOrder: req.body.sortOrder ?? existing.sortOrder })
      .where(eq(categories.id, req.params.id))
      .returning();

    res.json(updated);
  } catch (err) {
    console.error('Update category error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to update category.' });
  }
});

router.delete('/:id', async (req: AuthRequest, res: Response) => {
  try {
    const [existing] = await db.select()
      .from(categories)
      .where(and(eq(categories.id, req.params.id), eq(categories.userId, req.userId!)))
      .limit(1);

    if (!existing) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Category not found or is a system default.' });
      return;
    }

    await db.delete(categories).where(eq(categories.id, req.params.id));
    res.status(204).end();
  } catch (err) {
    console.error('Delete category error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to delete category.' });
  }
});

// --- Subtags ---

router.get('/:categoryId/subtags', async (req: AuthRequest, res: Response) => {
  try {
    const subs = await db.select()
      .from(subtags)
      .where(and(
        eq(subtags.categoryId, req.params.categoryId),
        eq(subtags.userId, req.userId!),
      ));

    res.json(subs);
  } catch (err) {
    console.error('List subtags error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to fetch subtags.' });
  }
});

router.post('/:categoryId/subtags', validate(createSubtagSchema), async (req: AuthRequest, res: Response) => {
  try {
    const [sub] = await db.insert(subtags).values({
      userId: req.userId!,
      categoryId: req.params.categoryId,
      name: req.body.name,
    }).returning();

    res.status(201).json(sub);
  } catch (err) {
    console.error('Create subtag error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to create subtag.' });
  }
});

router.delete('/:categoryId/subtags/:subtagId', async (req: AuthRequest, res: Response) => {
  try {
    const [existing] = await db.select()
      .from(subtags)
      .where(and(
        eq(subtags.id, req.params.subtagId),
        eq(subtags.userId, req.userId!),
      ))
      .limit(1);

    if (!existing) {
      res.status(404).json({ code: 'NOT_FOUND', message: 'Subtag not found.' });
      return;
    }

    await db.delete(subtags).where(eq(subtags.id, req.params.subtagId));
    res.status(204).end();
  } catch (err) {
    console.error('Delete subtag error:', err);
    res.status(500).json({ code: 'INTERNAL_ERROR', message: 'Failed to delete subtag.' });
  }
});

export default router;
