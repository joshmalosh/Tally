## Purpose

UIKit app-delegate shim: starts the Google Mobile Ads SDK as early as possible (before SwiftUI's lifecycle would), and installs the app-wide tap-to-dismiss-keyboard gesture once the window exists.

## Public surface

- `final class AppDelegate: NSObject, UIApplicationDelegate` (`Tally/Services/AppDelegate.swift:4`)
- `func application(_:didFinishLaunchingWithOptions:) -> Bool` (`:5`) — starts `GADMobileAds.sharedInstance()` and returns `true`.
- `func applicationDidBecomeActive(_:)` — calls `KeyboardDismissGesture.shared.install()` (defined in `Tally/Theme/UIApplication+ResignFirstResponder.swift`), which adds one window-level tap recogniser that resigns the first responder on any tap off a text field. Idempotent (guards against double-install), so running it every activation is safe.

## Depends on

`GoogleMobileAds` (`GADMobileAds`).

## Used by

- `Tally/TallyApp.swift:8` — wired in via `@UIApplicationDelegateAdaptor(AppDelegate.self)`.

## Gotchas

- Comment at `:9-11` explains the early start: it warms the WKWebView/WebContent process in the background so the first ad shown doesn't cause a ~1s freeze.
- `#if DEBUG` registers a hardcoded test device identifier (`:14`) so ads served on that device during development are Google's test ads, not live ones.
