## Purpose

Thin `@Observable` holder for whether the banner ad should show, and for the AdMob banner unit ID (test ID in DEBUG, real ID in release).

## Public surface

- `final class AdManager` (`Tally/Services/AdManager.swift:5`)
- `var shouldShowBannerAd: Bool` (`:6`) — observed by views to decide whether to render the banner. **Defaults to `false`** so no banner loads on the first frame before `configure(isPro:)` has run; a free user's banner appears a beat after launch instead of a Pro user's briefly network-loading at launch.
- `static var bannerAdUnitID: String` (`:8`) — DEBUG returns Google's sample test unit ID; release returns Tally's production unit ID.
- `func configure(isPro: Bool)` (`:17`) — sets `shouldShowBannerAd = !isPro`.

## Depends on

`GoogleMobileAds` (GADBannerView is built by the caller using `AdManager.bannerAdUnitID`).

## Used by

- `Tally/TallyApp.swift:11` — owns the single `@State private var adManager = AdManager()`.
- `Tally/ContentView.swift`, `Tally/Views/AddExpense/AddExpenseView.swift`, `Tally/Views/Home/HomeView.swift` — read `shouldShowBannerAd` / call `configure(isPro:)`.
- `Tally/Theme/Components.swift:458` — the banner ad `UIViewRepresentable` reads `AdManager.bannerAdUnitID`.

## Gotchas

- `configure(isPro:)` must be called (or re-called) whenever Pro status changes, or the banner state goes stale — this class does not observe subscription state itself.
