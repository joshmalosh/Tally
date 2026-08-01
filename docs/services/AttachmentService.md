## Purpose

Owns on-disk storage for receipt attachments (full image/file + a separately generated thumbnail) under the app's Documents directory, and fast off-main-thread thumbnail decoding.

## Public surface

- `actor AttachmentService`, singleton `static let shared` (`Tally/Services/AttachmentService.swift:4-5`)
- `nonisolated static func downsampledThumbnail(from: Data, maxPixel: CGFloat = 300) -> UIImage?` (`:13`) — ImageIO downsample-decode, safe to call off the main thread.
- `func saveImage(_ image: UIImage, id: String) throws -> String` (`:45`) — JPEG-compresses (0.8 quality), enforces a 20MB cap, writes it and a thumbnail, returns the storage key (`"<id>.jpg"`).
- `func saveFile(from sourceURL: URL, id: String) throws -> String` (`:61`) — copies an arbitrary file (e.g. PDF) in, enforcing the same 20MB cap; no thumbnail generated.
- `nonisolated static func exceedsMaxSize(_ image: UIImage) -> Bool` (`:75`) — cheap pixel-count-based pre-check before attempting a save.
- `nonisolated func loadImage(key: String) -> UIImage?` (`:81`) — loads the full-resolution attachment.
- `nonisolated func loadThumbnail(key: String) -> UIImage?` (`:87`) — loads and force-decodes the stored thumbnail.
- `nonisolated func loadImageData(key: String) -> Data?` (`:94`) — raw bytes of the full attachment.
- `func saveThumbnail(_ image: UIImage, key: String)` (`:101`) — regenerates/persists a thumbnail for an attachment missing one.
- `func deleteAttachment(key: String)` (`:105`) — removes both the attachment and its thumbnail file.
- `func attachmentURL(for key: String) -> URL` (`:112`) — path to the full attachment file.
- `enum AttachmentError: LocalizedError` (`:130`) — `.compressionFailed`, `.fileTooLarge`.

## Depends on

`UIKit`, `ImageIO`, `FileManager`. No other app services.

## Used by

- `Tally/Views/AddExpense/AddExpenseView.swift`, `Tally/Views/AddExpense/MultiReceiptReviewView.swift`, `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`, `Tally/Views/Home/HomeView.swift`, `Tally/Theme/Components.swift` (thumbnail-loading view), `Tally/Services/ExpenseExportService.swift`.

## Gotchas

- `downsampledThumbnail` and the `nonisolated` load methods are safe to call off the main thread by design — comment at `:7-12` explains this exists specifically to avoid decoding full-res receipts on the main thread at draw time.
- 20MB size cap enforced in both `saveImage` and `saveFile`; `exceedsMaxSize` is a separate, cheaper pre-check callers can use before starting a save.
- Thumbnail generation (`generateThumbnail`, private) caps at 200pt max dimension, JPEG quality 0.6 — distinct from the `downsampledThumbnail` 300px/ImageIO path used for redecoding.
