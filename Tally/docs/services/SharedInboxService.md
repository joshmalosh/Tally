## Purpose

Reads receipt files that the TallyShare extension deposits into the shared App Group container, so the main app can pick them up as pending expenses. The extension writes; the app consumes and deletes.

## Public surface

- `enum SharedInboxService` (`Tally/Services/SharedInboxService.swift:6`), `static let appGroupId = "group.com.asimplelife.tally"` (`:7`)
- `struct InboxItem { let url: URL; var isPDF: Bool }` (`:9-12`)
- `static func pendingItems() -> [InboxItem]` (`:21`) — all files in the Inbox directory, oldest first (by creation date).
- `static func loadImage(_ item: InboxItem) -> UIImage?` (`:36`) — loads a non-PDF item as an image.
- `static func claimPDF(_ item: InboxItem) -> URL?` (`:43`) — copies a pending PDF to a temp location for the add-expense flow to attach, then removes it from the inbox.
- `static func remove(_ item: InboxItem)` (`:53`) — deletes the inbox file without claiming it.
- `struct SharedPDFItem: Identifiable` (`:59`), `struct SharedImageItem: Identifiable` (`:65`) — `Identifiable` wrappers so a claimed PDF/image can drive `fullScreenCover(item:)`.

## Depends on

App Group container via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, `UIKit`.

## Used by

- `Tally/Views/Home/HomeView.swift` (only call site found).

## Gotchas

- Relies on the App Group ID matching exactly what the TallyShare extension target uses to write files — a mismatch would silently produce an empty inbox (`inboxURL` returns nil / directory read fails, both handled by returning `[]`).
- `claimPDF` only succeeds for PDFs (`item.isPDF` guard); images go through `loadImage` and are not "claimed"/removed by that path — callers must call `remove(_:)` themselves for images once consumed.
