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
  createdAt: Date;
}

export interface Expense {
  id: string;
  userId: string;
  amountCents: number;
  currency: string;
  date: string; // ISO date YYYY-MM-DD
  description: string | null;
  merchant: string | null;
  categoryId: string;
  subtagId: string | null;
  notes: string | null;
  attachmentKey: string | null;
  source: ExpenseSource;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

export interface Category {
  id: string;
  userId: string | null; // null = system default
  name: string;
  sortOrder: number;
}

export interface Subtag {
  id: string;
  userId: string;
  categoryId: string;
  name: string;
}

// API request/response types
export interface CreateExpenseRequest {
  amountCents: number;
  currency: string;
  date: string;
  description?: string;
  merchant?: string;
  categoryId: string;
  subtagId?: string;
  notes?: string;
  source: ExpenseSource;
}

export interface UpdateExpenseRequest {
  amountCents?: number;
  currency?: string;
  date?: string;
  description?: string | null;
  merchant?: string | null;
  categoryId?: string;
  subtagId?: string | null;
  notes?: string | null;
}

export interface CreateCategoryRequest {
  name: string;
  sortOrder?: number;
}

export interface CreateSubtagRequest {
  categoryId: string;
  name: string;
}

export interface ExportRequest {
  startDate: string;
  endDate: string;
  categoryId?: string;
  subtagId?: string;
  format: 'csv' | 'zip';
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ApiError {
  code: string;
  message: string;
}

// Subscription limits
export const FREE_TIER_LIMITS = {
  uploadsPerMonth: 25,
  storageBytes: 500 * 1024 * 1024, // 500MB
  maxFileSize: 20 * 1024 * 1024, // 20MB
} as const;
