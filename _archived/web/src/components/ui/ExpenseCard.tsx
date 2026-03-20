'use client';

import type { Expense } from '@/types';
import { formatCurrency } from '@/lib/currency';

export interface ExpenseCardProps {
  expense: Expense;
  categoryName: string;
  subtagName?: string | null;
  onClick?: () => void;
}

function getInitial(text: string): string {
  return text.charAt(0).toUpperCase() || '?';
}

export function ExpenseCard({
  expense,
  categoryName,
  subtagName,
  onClick,
}: ExpenseCardProps) {
  const displayText =
    expense.description ?? expense.merchant ?? 'No description';
  const formattedDate = new Date(expense.date).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });

  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full text-left bg-white shadow-sm rounded-lg p-4 hover:bg-bg-secondary transition-colors duration-150"
    >
      <div className="flex gap-3">
        {/* Left: category icon placeholder */}
        <div
          className="size-10 shrink-0 rounded-full bg-brand-tint flex items-center justify-center text-brand-primary font-semibold text-sm"
          aria-hidden
        >
          {getInitial(categoryName)}
        </div>

        {/* Middle: description/merchant, date */}
        <div className="flex-1 min-w-0">
          <p className="text-text-primary font-medium truncate">{displayText}</p>
          <p className="text-text-secondary text-sm mt-0.5">{formattedDate}</p>
        </div>

        {/* Right: amount */}
        <div className="shrink-0 font-mono text-text-primary font-medium">
          {formatCurrency(expense.amountCents, expense.currency)}
        </div>
      </div>

      {/* Bottom row: category and subtag pills */}
      <div className="flex flex-wrap gap-2 mt-3">
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-brand-tint text-brand-primary">
          {categoryName}
        </span>
        {subtagName && (
          <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-chip-default text-chip-text">
            {subtagName}
          </span>
        )}
      </div>
    </button>
  );
}
