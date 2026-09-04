## Purpose

Observes network reachability and CloudKit sync completion events so the UI can show online/offline state and last-synced time. Does not perform sync itself — SwiftData + CloudKit handles that automatically.

## Public surface

- `final class SyncEngine` (`Tally/Services/SyncEngine.swift:8`), `@Observable`
- `private(set) var isOnline: Bool` (`:9`) — updated from `NWPathMonitor`.
- `private(set) var lastSyncDate: Date?` (`:10`) — updated on successful CloudKit export events, persisted to `UserDefaults` under `"lastCloudKitSyncDate"`.
- `private(set) var isSignedIntoiCloud: Bool` — whether the device has an iCloud account, from `FileManager.ubiquityIdentityToken` (no CloudKit entitlement needed). Auto-updates on `.NSUbiquityIdentityDidChange`.
- `func refreshAccountStatus()` — re-checks the iCloud account; call on foreground / when Settings appears.

## Depends on

`Network` (`NWPathMonitor`), `CoreData` (`NSPersistentCloudKitContainer.eventChangedNotification`), `Foundation` (`FileManager.ubiquityIdentityToken`, `.NSUbiquityIdentityDidChange`), `UserDefaults`.

## Used by

- `Tally/TallyApp.swift:10` — owns `@State private var syncEngine = SyncEngine()`.
- `Tally/ContentView.swift` — injects it via `.environment(SyncEngine())` and observes `isOnline`.
- `Tally/Views/Home/HomeView.swift`, `Tally/Views/Settings/SettingsView.swift` — read `isOnline` / `lastSyncDate`.

## Gotchas

- `ContentView.swift:299` calls `.environment(SyncEngine())`, a second instance separate from the one `TallyApp` owns — confirm which instance actually reaches a given view before relying on its state.
- `lastSyncDate` only updates on a *successful* `.export` event with a non-nil `endDate`; import-only syncs don't move it.
- Network monitoring runs on a dedicated serial queue (`com.tally.network-monitor`) but publishes to `isOnline` via `DispatchQueue.main.async`.
- CloudKit events are handled **off the main thread** on a serial utility `OperationQueue` (`com.tally.cloudkit-events`), not `.main` — a burst of sync events must never do main-thread work mid-scroll. The `lastSyncDate` refresh is throttled to at most once per minute (`lastExportEventAt`, `@ObservationIgnored`, touched only on that serial queue) and hops to main only for the actual write. The "cloudkit export ok" info log is DEBUG-only; the failure log stays in release.
- This throttling only covers *our* observer's work. SwiftData still merges each CloudKit import into the view context and re-runs `@Query`, which has no public throttle knob — keep per-refresh work in the observing views cheap.
