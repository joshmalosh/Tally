# Tally/Services

One doc per file in `Tally/Services/`. Regenerated in full each run — see individual files for details, line refs, gotchas.

| Service | Purpose |
|---|---|
| [APIService](APIService.md) | Archived stub — `APIError` type only, kept so the Xcode project file doesn't need editing. |
| [AdManager](AdManager.md) | Holds whether the banner ad should show and the AdMob banner unit ID. |
| [AppDelegate](AppDelegate.md) | UIKit shim that starts the Google Mobile Ads SDK early at launch. |
| [AttachmentService](AttachmentService.md) | Saves/loads/deletes receipt attachments and thumbnails on disk. |
| [DocumentPicker](DocumentPicker.md) | `UIDocumentPickerViewController` wrapper for picking a receipt PDF/image from Files. |
| [ExpenseExportService](ExpenseExportService.md) | Builds CSV/ZIP, plain-text, image, and PDF exports of expenses. |
| [ExpenseSoundService](ExpenseSoundService.md) | Plays the coin-drop sound + haptic on expense logged; defines related notification names. |
| [ImagePicker](ImagePicker.md) | Custom camera capture view (`CameraPicker`) and multi-select photo picker (`PhotosPicker`). |
| [ReceiptOCRService](ReceiptOCRService.md) | Vision-based OCR extraction of amount/merchant/date/currency/notes from a receipt photo, plus `TagSuggestionEngine`. |
| [RevenueCatConfig](RevenueCatConfig.md) | Static RevenueCat API key/entitlement config, with a DEBUG-only force-Pro flag. |
| [SharedInboxService](SharedInboxService.md) | Reads receipt files the TallyShare extension drops in the shared App Group container. |
| [SubscriptionService](SubscriptionService.md) | Refreshes Pro/free status from RevenueCat into `AppState`. |
| [SyncEngine](SyncEngine.md) | Observes network reachability and CloudKit sync events for online/last-synced UI state. |
