const NO_DECIMAL_CURRENCIES = new Set(['JPY', 'KRW', 'VND', 'CLP']);

export function formatCurrency(
  cents: number,
  currencyCode = 'USD',
  locale = 'en-US'
): string {
  const hasDecimals = !NO_DECIMAL_CURRENCIES.has(currencyCode);
  const amount = hasDecimals ? cents / 100 : cents;
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: currencyCode,
    minimumFractionDigits: hasDecimals ? 2 : 0,
    maximumFractionDigits: hasDecimals ? 2 : 0,
  }).format(amount);
}

export function formatCurrencyCompact(
  cents: number,
  currencyCode = 'USD'
): string {
  const amount = cents / 100;
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`;
  if (amount >= 10_000) return `$${Math.round(amount / 1_000)}K`;
  return formatCurrency(cents, currencyCode);
}
