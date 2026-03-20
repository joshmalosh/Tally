import { isNull } from 'drizzle-orm';
import { db } from './index.js';
import { categories } from './schema.js';

const DEFAULT_CATEGORIES = [
  { name: 'Travel', sortOrder: 0 },
  { name: 'Petrol', sortOrder: 1 },
  { name: 'Meals', sortOrder: 2 },
  { name: 'Subscriptions', sortOrder: 3 },
  { name: 'Equipment', sortOrder: 4 },
  { name: 'Marketing', sortOrder: 5 },
  { name: 'Office', sortOrder: 6 },
  { name: 'Shipping', sortOrder: 7 },
  { name: 'Other', sortOrder: 8 },
] as const;

async function seed() {
  const existing = await db
    .select()
    .from(categories)
    .where(isNull(categories.userId));

  if (existing.length > 0) {
    console.log('Default categories already exist. Skipping.');
    return;
  }

  await db.insert(categories).values(
    DEFAULT_CATEGORIES.map((cat) => ({
      userId: null,
      name: cat.name,
      sortOrder: cat.sortOrder,
    }))
  );
  console.log('Default categories seeded.');
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
