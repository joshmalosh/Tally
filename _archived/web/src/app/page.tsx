'use client';

import { useState } from 'react';
import { DEFAULT_CATEGORIES } from '@/types';
import { Chip } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { FAB } from '@/components/ui/FAB';

function getMonthRange(): string {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  return `${start.toLocaleDateString('en-US', { month: 'short' })} 1 – ${end.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
}

export default function Home() {
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);

  return (
    <main className="min-h-screen flex flex-col bg-bg-primary">
      {/* Header */}
      <header className="px-4 pt-6 pb-4 border-b border-border">
        <p className="text-text-secondary text-sm font-medium">This Month</p>
        <p className="text-text-primary text-2xl font-semibold mt-1">$0.00</p>
        <p className="text-text-muted text-xs mt-1">{getMonthRange()}</p>
      </header>

      {/* Filter chips */}
      <div className="px-4 py-3 overflow-x-auto">
        <div className="flex gap-2">
          <Chip
            label="All"
            isActive={selectedCategory === null}
            onClick={() => setSelectedCategory(null)}
          />
          {DEFAULT_CATEGORIES.map((cat) => (
            <Chip
              key={cat}
              label={cat}
              isActive={selectedCategory === cat}
              onClick={() => setSelectedCategory(selectedCategory === cat ? null : cat)}
            />
          ))}
        </div>
      </div>

      {/* Expense list area */}
      <div className="flex-1 px-4 pb-24">
        <EmptyState
          icon="📋"
          title="No expenses yet"
          message="Add your first expense to start tracking. Tap the + button below."
          actionTitle="Add expense"
          onAction={() => {}}
        />
      </div>

      <FAB onClick={() => {}} />
    </main>
  );
}
