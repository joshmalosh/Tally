import dotenv from 'dotenv';
dotenv.config();

const DEV_JWT_SECRET = 'dev-secret-change-me';

export const env = {
  port: parseInt(process.env.PORT || '3001', 10),
  databaseUrl: process.env.DATABASE_URL || '',
  jwtSecret: process.env.JWT_SECRET || DEV_JWT_SECRET,
  allowedOrigins: (process.env.ALLOWED_ORIGINS || 'http://localhost:3000')
    .split(',')
    .map((o) => o.trim()),
  s3Bucket: process.env.S3_BUCKET || '',
  s3Region: process.env.S3_REGION || 'us-east-1',
  nodeEnv: process.env.NODE_ENV || 'development',
} as const;

// Fail fast in production if critical secrets are unset or still at default values.
if (env.nodeEnv === 'production') {
  if (!env.databaseUrl) {
    throw new Error('DATABASE_URL must be set in production.');
  }
  if (env.jwtSecret === DEV_JWT_SECRET) {
    throw new Error('JWT_SECRET must be set to a strong secret in production.');
  }
}
