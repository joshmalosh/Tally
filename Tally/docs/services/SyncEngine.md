## Purpose

Observes network reachability and CloudKit sync completion events so the UI can show online/offline state and last-synced time. Does not perform sync itself — SwiftData + CloudKit handles that automatically.

## Public surface

- `final class SyncEngine` (`Tally/Services/SyncEngine.swift:8`), `@Observable`
- `private(set) var isOnline: Bool` (`:9`) — updated from `NWPathMonitor`.
- `private(set) var lastSyncDate: Date?` (`:10`) — updated on successful CloudKit export events, persisted to `UserDefaults` under `"lastCloudKitSyncDate"`.

## Depends on

`Network` (`NWPathMonitor`), `CoreData` (`NSPersistentCloudKitContainer.eventChangedNotification`), `UserDefaults`.

## Used by

- `Tally/TallyApp.swift:10` — owns `@State private var syncEngine = SyncEngine()`.
- `Tally/ContentView.swift` — injects it via `.environment(SyncEngine())` and observes `isOnline`.
- `Tally/Views/Home/HomeView.swift`, `Tally/Views/Settings/SettingsView.swift` — read `isOnline` / `lastSyncDate`.

## Gotchas

- `ContentView.swift:299` calls `.environment(SyncEngine())`, a second instance separate from the one `TallyApp` owns — confirm which instance actually reaches a given view before relying on its state.
- `lastSyncDate` only updates on a *successful* `.export` event with a non-nil `endDate`; import-only syncs don't move it.
- Network monitoring runs on a dedicated serial queue (`com.tally.network-monitor`) but publishes to `isOnline` via `DispatchQueue.main.async`.
