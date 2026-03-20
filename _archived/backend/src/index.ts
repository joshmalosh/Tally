import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { env } from './config/env.js';
import { rateLimit, authRateLimit } from './middleware/rateLimit.js';
import authRoutes from './routes/auth.js';
import expenseRoutes from './routes/expenses.js';
import categoryRoutes from './routes/categories.js';
import exportRoutes from './routes/export.js';

dotenv.config();

const app = express();
const PORT = env.port;

// Redirect HTTP → HTTPS in production (when behind a reverse proxy like nginx/Vercel).
app.use((req: Request, res: Response, next: NextFunction): void => {
  if (env.nodeEnv === 'production' && req.headers['x-forwarded-proto'] !== 'https') {
    res.redirect(301, `https://${req.headers.host}${req.url}`);
    return;
  }
  next();
});

app.use(helmet());

// CORS: only allow explicitly configured origins.
app.use(cors({
  origin: (origin, callback) => {
    // Allow non-browser requests (e.g. native mobile) and whitelisted origins.
    if (!origin || env.allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin '${origin}' is not allowed.`));
    }
  },
  credentials: true,
}));

app.use(express.json({ limit: '1mb' }));
app.use(rateLimit);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'tally-api', timestamp: new Date().toISOString() });
});

// Auth routes get a stricter per-IP rate limit to slow brute-force attempts.
app.use('/api/auth', authRateLimit, authRoutes);
app.use('/api/expenses', expenseRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api/export', exportRoutes);

app.use((_req, res) => {
  res.status(404).json({ code: 'NOT_FOUND', message: 'Route not found.' });
});

app.listen(PORT, () => {
  console.log(`Tally API running on port ${PORT}`);
});

export default app;
