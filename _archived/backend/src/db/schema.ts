import {
  pgTable,
  pgEnum,
  uuid,
  varchar,
  integer,
  text,
  timestamp,
  index,
} from 'drizzle-orm/pg-core';

// Enums
export const subscriptionStatusEnum = pgEnum('subscription_status', [
  'free',
  'pro',
  'expired',
  'cancelled',
]);

export const subscriptionProviderEnum = pgEnum('subscription_provider', [
  'apple',
  'stripe',
  'none',
]);

export const authProviderEnum = pgEnum('auth_provider', [
  'email',
  'apple',
  'google',
]);

export const expenseSourceEnum = pgEnum('expense_source', [
  'camera',
  'upload',
  'manual',
]);

// Tables
export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  authProvider: authProviderEnum('auth_provider').notNull(),
  passwordHash: text('password_hash'),
  subscriptionStatus: subscriptionStatusEnum('subscription_status')
    .notNull()
    .default('free'),
  subscriptionProvider: subscriptionProviderEnum('subscription_provider')
    .notNull()
    .default('none'),
  createdAt: timestamp('created_at', { mode: 'date' }).notNull().defaultNow(),
});

export const categories = pgTable('categories', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').references(() => users.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 255 }).notNull(),
  sortOrder: integer('sort_order').notNull().default(0),
});

export const subtags = pgTable('subtags', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  categoryId: uuid('category_id')
    .notNull()
    .references(() => categories.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 255 }).notNull(),
});

export const expenses = pgTable(
  'expenses',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    amountCents: integer('amount_cents').notNull(),
    currency: varchar('currency', { length: 3 }).notNull(),
    date: varchar('date', { length: 10 }).notNull(), // ISO date YYYY-MM-DD
    description: text('description'),
    merchant: text('merchant'),
    categoryId: uuid('category_id')
      .notNull()
      .references(() => categories.id, { onDelete: 'restrict' }),
    subtagId: uuid('subtag_id').references(() => subtags.id, {
      onDelete: 'set null',
    }),
    notes: text('notes'),
    attachmentKey: text('attachment_key'),
    source: expenseSourceEnum('source').notNull(),
    createdAt: timestamp('created_at', { mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { mode: 'date' }).notNull().defaultNow(),
    deletedAt: timestamp('deleted_at', { mode: 'date' }),
  },
  (table) => [
    index('expenses_user_id_date_idx').on(table.userId, table.date),
    index('expenses_user_id_category_id_idx').on(table.userId, table.categoryId),
    index('expenses_user_id_deleted_at_idx').on(table.userId, table.deletedAt),
  ]
);
