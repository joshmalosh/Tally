'use client';

export interface ChipProps {
  label: string;
  isActive: boolean;
  onClick: () => void;
}

export function Chip({ label, isActive, onClick }: ChipProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`
        rounded-full px-3 py-1.5 text-sm cursor-pointer transition-colors duration-150
        shrink-0
        ${
          isActive
            ? 'bg-brand-tint text-brand-primary border border-brand-accent'
            : 'bg-chip-default text-chip-text border border-transparent'
        }
      `}
    >
      {label}
    </button>
  );
}
