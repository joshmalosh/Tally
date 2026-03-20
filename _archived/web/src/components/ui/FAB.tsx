'use client';

export interface FABProps {
  onClick: () => void;
  'aria-label'?: string;
}

export function FAB({ onClick, 'aria-label': ariaLabel = 'Add expense' }: FABProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      className="
        fixed bottom-6 right-6 size-14 rounded-full
        bg-brand-primary text-white shadow-lg
        hover:bg-brand-pressed transition-colors duration-150
        flex items-center justify-center
        z-50
      "
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="currentColor"
        className="size-6"
        aria-hidden
      >
        <path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2h6Z" />
      </svg>
    </button>
  );
}
