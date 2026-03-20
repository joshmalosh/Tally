export type SubscriptionStatus = 'free' | 'pro' | 'expired' | 'cancelled';
export type SubscriptionProvider = 'apple' | 'stripe' | 'none';
export type AuthProvider = 'email' | 'apple' | 'google';
export type ExpenseSource = 'camera' | 'upload' | 'manual';

export interface User {
  id: string;
  email: string;
  authProvider: AuthProvider;
  subscriptionStatus: SubscriptionStatus;
  subscriptionProvider: SubscriptionProvider;
  createdAt: string;
}

export interface Expense {
  id: string;
  userId: string;
  amountCents: number;
  currency: string;
  date: string;
  description: string | null;
  merchant: string | null;
  categoryId: string;
  subtagId: string | null;
  notes: string | null;
  attachmentKey: string | null;
  source: ExpenseSource;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface Category {
  id: string;
  userId: string | null;
  name: string;
  sortOrder: number;
}

export interface Subtag {
  id: string;
  userId: string;
  categoryId: string;
  name: string;
}

export interface MonthlyTotal {
  totalCents: number;
  currency: string;
  expenseCount: number;
}

export const DEFAULT_CATEGORIES = [
  'Travel',
  'Petrol',
  'Meals',
  'Software',
  'Equipment',
  'Marketing',
  'Office',
  'Shipping',
  'Other',
] as const;

export const FREE_TIER_LIMITS = {
  uploadsPerMonth: 25,
  storageBytes: 500 * 1024 * 1024,
  maxFileSize: 20 * 1024 * 1024,
} as const;
