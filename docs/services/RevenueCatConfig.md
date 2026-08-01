## Purpose

Static RevenueCat configuration (API key, entitlement/offering identifiers) plus a DEBUG-only flag to force Pro mode during development.

## Public surface

- `enum RevenueCatConfig` (`Tally/Services/RevenueCatConfig.swift:3`)
- `static let apiKey: String` (`:4`)
- `static let proEntitlementId: String` (`:5`) — `"A Simple Life - Tally Pro"`.
- `static let offeringIdentifier: String` (`:6`) — `"Tally Pro"`.
- `#if DEBUG static let forcePro: Bool = true` (`:23`) — compiled out entirely in release builds.

## Depends on

Nothing beyond `Foundation`. Consumed by `SubscriptionService` and RevenueCat SDK setup.

## Used by

- `Tally/Views/Settings/SubscriptionView.swift`, `Tally/TallyApp.swift`, `Tally/Services/SubscriptionService.swift`.

## Gotchas

- `forcePro` only exists in DEBUG builds; the comment block (`:8-21`) enumerates every Pro gate it affects app-wide (ad removal, expense/export caps, Pro-only export templates, OCR autofill, upsell prompts, Settings row).
- Trivial config enum — no logic beyond the DEBUG override.
