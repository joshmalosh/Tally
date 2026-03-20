'use client';

import type { ButtonHTMLAttributes } from 'react';

export interface ButtonBaseProps {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  isLoading?: boolean;
  className?: string;
  type?: ButtonHTMLAttributes<HTMLButtonElement>['type'];
}

export function PrimaryButton({
  children,
  onClick,
  disabled = false,
  isLoading = false,
  className = '',
  type = 'button',
}: ButtonBaseProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || isLoading}
      className={`
        w-full min-h-[50px] rounded-lg bg-brand-primary text-white
        font-medium transition-colors duration-150
        hover:bg-brand-pressed disabled:opacity-50 disabled:cursor-not-allowed
        flex items-center justify-center gap-2
        ${className}
      `}
    >
      {isLoading ? (
        <span className="size-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
      ) : (
        children
      )}
    </button>
  );
}

export function SecondaryButton({
  children,
  onClick,
  disabled = false,
  isLoading = false,
  className = '',
  type = 'button',
}: ButtonBaseProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || isLoading}
      className={`
        w-full min-h-[50px] rounded-lg bg-transparent border border-brand-primary text-brand-primary
        font-medium transition-colors duration-150
        hover:bg-brand-tint disabled:opacity-50 disabled:cursor-not-allowed
        flex items-center justify-center gap-2
        ${className}
      `}
    >
      {isLoading ? (
        <span className="size-5 animate-spin rounded-full border-2 border-brand-primary border-t-transparent" />
      ) : (
        children
      )}
    </button>
  );
}
