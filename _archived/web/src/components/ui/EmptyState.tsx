'use client';

import { PrimaryButton } from './Button';

export interface EmptyStateProps {
  icon: React.ReactNode;
  title: string;
  message: string;
  actionTitle?: string;
  onAction?: () => void;
}

export function EmptyState({
  icon,
  title,
  message,
  actionTitle,
  onAction,
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center text-center px-6 py-12">
      <div className="text-text-muted text-4xl mb-4" aria-hidden>
        {icon}
      </div>
      <h3 className="text-text-primary font-semibold text-lg mb-2">{title}</h3>
      <p className="text-text-secondary text-sm max-w-sm mb-6">{message}</p>
      {actionTitle && onAction && (
        <PrimaryButton onClick={onAction}>{actionTitle}</PrimaryButton>
      )}
    </div>
  );
}
