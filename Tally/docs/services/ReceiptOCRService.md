## Purpose

Runs Vision text recognition over a receipt photo and extracts amount, merchant, date, currency, and a best-guess notes line via a large set of heuristics (regex + positional scoring). Also hosts `TagSuggestionEngine`, a keyword-based tag suggester that runs on the OCR output.

## Public surface

- `struct ReceiptOCRResult` (`Tally/Services/ReceiptOCRService.swift:4`) — `amount: Double?`, `merchant: String?`, `date: Date?`, `notes: String?`, `currencyCode: String?` (ISO 4217, only when unambiguous), `merchantAlternates: [String]` (lower-ranked merchant guesses for a "Doesn't look right?" picker).
- `enum ReceiptOCRService` (`:17`)
- `static func extractFullText(from image: UIImage) async -> String` (`:20`) — all recognized text blocks, top-to-bottom, newline-joined; used for bulk import.
- `static func extract(from image: UIImage) async -> ReceiptOCRResult` (`:68`) — the main entry point: runs Vision, then amount/merchant/date/currency/notes extraction.
- `#if DEBUG static func extractForTesting(...)` (`:46`, `:53`) — runs the extraction pipeline over synthetic `(text, box[, confidence])` tuples, bypassing Vision, for regression tests against real receipt layouts.
- `enum TagSuggestionEngine` (`:1035`) — `struct Suggestion { let tag: TagModel; let reason: String }` (`:1037`); `static func suggest(merchant: String, notes: String, tags: [TagModel]) -> Suggestion?` (`:1046`) matches merchant+notes text against a fixed keyword-to-tag-hint rule table (dining, transport, groceries, subscriptions, health, shopping, home/hardware, office, travel/accommodation, utilities).

## Depends on

`Vision` (`VNRecognizeTextRequest`, `.accurate` recognition level, language correction on), `UIKit`, `TagModel` domain type.

## Used by

- OCR extraction: `Tally/Views/AddExpense/AddExpenseView.swift`, `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`, `Tally/Views/AddExpense/MultiReceiptReviewView.swift`, `Tally/Views/AddMultipleExpenses/AddMultipleExpensesView.swift`, `Tally/Theme/Components.swift`.

## Gotchas

- All Vision work is dispatched to a background queue inside `recognizeText(in:)` (`:121-141`) since `handler.perform` is synchronous and would block if called directly from a `@MainActor` context.
- Amount extraction is scored, not first-match: candidates get points for label strength (strong total > generic total > payment line), cross-confirmation (same amount appearing ≥2 times), and position; a candidate needs score ≥45 to win outright, else falls back through repeated-amount / subtotal-floor / currency-marked / bottom-half heuristics (`:268-375`). Extensive inline comments document real misreads each rule was added to fix (e.g. Indonesian grouped-thousands, "TOTAL SAVINGS" false positives, French totals).
- Currency detection never trusts a bare `$` (ambiguous across AUD/USD/NZD/CAD); it only trusts explicit ISO codes, unambiguous symbols (€/£/¥/₹) next to a digit, or — as a last resort — a recognized place name in the letterhead (`:379-455`).
- Date parsing rejects results more than 2 days in the future or before 2015 — guards against thermal-print digit misreads like 2026→2028 (`:518-522`). Ambiguous DD/MM vs MM/DD numeric dates default to DD/MM.
- Merchant extraction is a multi-pass ranked pipeline (`rankedMerchants`, `:743-805`): largest header wordmark → registered-business-suffix line (Pty/Ltd/Inc/…) → ALL-CAPS masthead text → masthead then whole-receipt candidates by confidence tier. Results are deduped case-insensitively, then a recurring multi-word phrase (name printed twice, e.g. wordmark + letterhead) is preferred and promoted to the fullest matching form.
- `#if DEBUG` `dumpBlocks` (`:824`) prints every recognized block's geometry/confidence/text prefixed `OCR|` for filtering in Xcode console; `extract(from:)` also prints a DEBUG-only summary line of the final decision.
- `TagSuggestionEngine.suggest` prefers a non-system tag over a system tag when both match a hint, and returns the first rule/keyword/hint combination that matches — not the best or most specific match.
