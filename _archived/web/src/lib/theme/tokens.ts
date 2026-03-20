export const colors = {
  brand: {
    primary: '#346049',
    accent: '#4A7D62',
    tint: '#E8EFE9',
    pressed: '#2A4E3B',
  },
  bg: {
    primary: '#F6F5F3',
    secondary: '#FFFFFF',
  },
  border: '#E3E8E5',
  text: {
    primary: '#111417',
    secondary: '#6B7280',
    muted: '#9CA3AF',
  },
  chip: {
    default: '#EEEDEB',
    defaultText: '#4B5563',
  },
  danger: '#C84646',
  success: '#2E7D5B',
} as const;

export const spacing = {
  xs: '4px',
  sm: '8px',
  md: '16px',
  lg: '24px',
  xl: '32px',
} as const;

export const radius = {
  sm: '8px',
  md: '12px',
  lg: '16px',
  full: '9999px',
} as const;

export const typography = {
  fontFamily: {
    sans: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    mono: '"JetBrains Mono", "SF Mono", "Fira Code", monospace',
  },
  fontSize: {
    xs: '12px',
    sm: '13px',
    base: '16px',
    lg: '18px',
    xl: '20px',
    '2xl': '24px',
    '3xl': '28px',
    '4xl': '36px',
  },
} as const;
