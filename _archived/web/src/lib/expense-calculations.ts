import type { Expense, Category, Subtag, MonthlyTotal } from '@/types';

export function calculateMonthlyTotal(
  expenses: Expense[],
  month: Date,
  currency: string
): MonthlyTotal {
  const year = month.getFullYear();
  const monthIdx = month.getMonth();

  const filtered = expenses.filter((e) => {
    if (e.deletedAt) return false;
    if (e.currency !== currency) return false;
    const d = new Date(e.date);
    return d.getFullYear() === year && d.getMonth() === monthIdx;
  });

  const totalCents = filtered.reduce((sum, e) => sum + e.amountCents, 0);
  return { totalCents, currency, expenseCount: filtered.length };
}

export function uploadCountThisMonth(expenses: Expense[]): number {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();

  return expenses.filter((e) => {
    if (e.deletedAt) return false;
    if (e.source !== 'camera' && e.source !== 'upload') return false;
    const d = new Date(e.createdAt);
    return d.getFullYear() === year && d.getMonth() === month;
  }).length;
}

export function groupByCategory(expenses: Expense[]): Record<string, Expense[]> {
  const result: Record<string, Expense[]> = {};
  for (const e of expenses) {
    if (e.deletedAt) continue;
    if (!result[e.categoryId]) result[e.categoryId] = [];
    result[e.categoryId].push(e);
  }
  return result;
}

export function sortByDate(expenses: Expense[], ascending = false): Expense[] {
  return expenses
    .filter((e) => !e.deletedAt)
    .sort((a, b) => {
      const diff = new Date(a.date).getTime() - new Date(b.date).getTime();
      return ascending ? diff : -diff;
    });
}

function csvEscape(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

export function generateCSV(
  expenses: Expense[],
  categories: Category[],
  subtags: Subtag[]
): string {
  const header =
    'date,description,merchant,amount,currency,category,subtag,notes,attachment_filename,source,created_at';
  const categoryMap = new Map(categories.map((c) => [c.id, c.name]));
  const subtagMap = new Map(subtags.map((s) => [s.id, s.name]));

  const rows = sortByDate(expenses, true).map((e) => {
    const amount = (e.amountCents / 100).toFixed(2);
    const category = categoryMap.get(e.categoryId) ?? 'Uncategorized';
    const subtag = e.subtagId ? subtagMap.get(e.subtagId) ?? '' : '';
    return [
      e.date,
      csvEscape(e.description ?? ''),
      csvEscape(e.merchant ?? ''),
      amount,
      e.currency,
      csvEscape(category),
      csvEscape(subtag),
      csvEscape(e.notes ?? ''),
      e.attachmentKey ?? '',
      e.source,
      e.createdAt,
    ].join(',');
  });

  return [header, ...rows].join('\n');
}
