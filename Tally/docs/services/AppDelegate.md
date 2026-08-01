## Purpose

UIKit app-delegate shim used only to start the Google Mobile Ads SDK as early as possible, before SwiftUI's own lifecycle would get to it.

## Public surface

- `final class AppDelegate: NSObject, UIApplicationDelegate` (`Tally/Services/AppDelegate.swift:4`)
- `func application(_:didFinishLaunchingWithOptions:) -> Bool` (`:5`) — starts `GADMobileAds.sharedInstance()` and returns `true`.

## Depends on

`GoogleMobileAds` (`GADMobileAds`).

## Used by

- `Tally/TallyApp.swift:8` — wired in via `@UIApplicationDelegateAdaptor(AppDelegate.self)`.

## Gotchas

- Comment at `:9-11` explains the early start: it warms the WKWebView/WebContent process in the background so the first ad shown doesn't cause a ~1s freeze.
- `#if DEBUG` registers a hardcoded test device identifier (`:14`) so ads served on that device during development are Google's test ads, not live ones.
