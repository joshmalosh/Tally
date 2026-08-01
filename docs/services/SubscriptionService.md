## Purpose

Refreshes the app's Pro/free subscription status from RevenueCat and writes it into `AppState`.

## Public surface

- `enum SubscriptionService` (`Tally/Services/SubscriptionService.swift:4`)
- `static func refreshProStatus(appState: AppState) async` (`:6`) — in DEBUG, short-circuits to `.pro` if `RevenueCatConfig.forcePro`; otherwise fetches `Purchases.shared.customerInfo()` and sets `appState.subscriptionStatus` to `.pro` if the configured entitlement is active, `.free` on any failure or inactive entitlement.

## Depends on

`RevenueCat` (`Purchases`), `RevenueCatConfig` (entitlement ID, DEBUG force-pro flag), `AppState` (`subscriptionStatus` written on `MainActor`).

## Used by

- `Tally/Views/Settings/SubscriptionView.swift`, `Tally/TallyApp.swift`.

## Gotchas

- On any error fetching `customerInfo`, status is set to `.free` (fails closed), and the error is only printed in DEBUG.
- All `appState` mutation happens via `await MainActor.run` — safe to call `refreshProStatus` from any context.
- `RevenueCatConfig.forcePro` DEBUG override bypasses the network call entirely; behaves as if always Pro in debug builds unless that flag is flipped.
