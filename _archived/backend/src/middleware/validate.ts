import { Request, Response, NextFunction } from 'express';
import { ZodSchema, ZodError } from 'zod';
import { env } from '../config/env.js';

export function validate(schema: ZodSchema) {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      req.body = schema.parse(req.body);
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        // In production, return a generic message to avoid leaking schema
        // structure. In development, include field-level details for debugging.
        const message = env.nodeEnv === 'production'
          ? 'Invalid request data.'
          : err.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join(', ');
        res.status(400).json({ code: 'VALIDATION_ERROR', message });
        return;
      }
      next(err);
    }
  };
}
