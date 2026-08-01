## Purpose

Builds shareable artifacts from expense data: CSV (optionally zipped with receipt images), a plain-text summary of a single expense, and rendered image/PDF receipt cards.

## Public surface

All members are `static` on `enum ExpenseExportService` (`Tally/Services/ExpenseExportService.swift:4`).

- `static func buildCSVExport(expenses: [ExpenseModel], tags: [Tag], filenamePrefix: String, includeReceipts: Bool = false) -> URL?` (`:11`) — filters out soft-deleted expenses, sorts by date, generates CSV via `ExpenseCalculations.generateCSV`. If `includeReceipts` and any expense has an attachment, bundles CSV + `receipts/` folder into a ZIP via `NSFileCoordinator`; otherwise returns a plain `.csv` file URL. Returns `nil` on write/zip failure.
- `static func plainText(expense: ExpenseModel, tags: [TagModel], currency: String) -> String` (`:124`) — merchant/amount/date/tags/notes as newline-joined text, for share-sheet text export.
- `@MainActor static func generateImage(expense: ExpenseModel, tags: [TagModel], currency: String) -> UIImage` (`:155`) — renders a receipt-card SwiftUI view to a `UIImage` via `ImageRenderer` (3x scale).
- `@MainActor static func generatePDF(expense: ExpenseModel, tags: [TagModel], currency: String) -> URL` (`:225`) — draws a one-page PDF receipt card via `UIGraphicsPDFRenderer`, writes to a temp file, returns its URL.

## Depends on

`AttachmentService.shared` (loads receipt images), `ExpenseCalculations` (domain CSV generation), `CurrencyFormatter.shared`, `Color(hex:)` extension, `ExpenseModel`/`TagModel`/`Tag`/`Expense`/`ExpenseSource` domain types, `UIKit`, `SwiftUI`.

## Used by

- `Tally/Views/Home/HomeView.swift`, `Tally/Views/Export/GlobalExportSheet.swift`, `Tally/Views/Export/ExportView.swift`, `Tally/Views/Export/ExportExpenseSheet.swift`.

## Gotchas

- `generateImage` and `generatePDF` are `@MainActor` (SwiftUI rendering); `buildCSVExport` is not actor-isolated but does file I/O — callers should not assume it's cheap/synchronous-safe on the main thread for large exports.
- ZIP path only triggers when `includeReceipts` is true AND at least one expense actually has an attachment (`attachmentKey` or `attachmentData`); otherwise a plain CSV is returned even if `includeReceipts` was requested.
- Receipt filenames in the ZIP are index-prefixed and sanitized/truncated to 40 chars (`:34-41`); the attachment extension is validated as 1-4 letters or defaults to `jpg`.
- Uses `NSFileCoordinator(readingItemAt:options:.forUploading)` to get the zipped result — this is the mechanism macOS/iOS uses to trigger automatic zipping of a directory.
