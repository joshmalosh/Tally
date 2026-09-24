---
name: ocr-regression
description: >
  Guardrail workflow for any change to Tally's receipt OCR. Invoke whenever
  editing Tally/Services/ReceiptOCRService.swift, when a user reports a receipt
  the scanner got wrong (amount/merchant/date/currency), or before claiming an
  OCR fix is done. Ensures every reported receipt becomes a permanent
  regression test so the parser can only get more versatile, never regress.
---

# OCR regression guardrail

Tally's OCR is **metered** — free users get 10 successful scans a month, Pro is
unlimited, and a scan only counts as successful if it extracted an amount. That
makes accuracy directly monetised: a wrong or empty amount both fails the user
and refunds their scan. Its accuracy has repeatedly regressed
when one fix broke a previously-working receipt. This workflow makes that
impossible to do silently.

## Hard rule

**Never change `ReceiptOCRService.swift` without adding or updating a test case
for the receipt that motivated the change.** Every receipt a user reports —
right or wrong — gets pinned in `TallyTests/ReceiptOCRServiceTests.swift`.

**Launch gate: every receipt in the corpus below must pass before release.**
These are all real receipts Josh reported. The whole suite (⌘U) must be green,
with no corpus receipt regressed, as a condition of shipping.

## Environment reality

The dev machine is **Windows with no Swift/Xcode toolchain**, so the tests
**cannot be executed here** — the parser depends on Vision/CoreGraphics. Tests
run on the user's **Mac**. Therefore:

- You must **reason through** the new receipt against the scoring logic by hand
  and state the expected outcome before editing. Trace the actual block text
  through every filter — reasoning from the corpus instead of from the reported
  layout has shipped two wrong "fixes" for the same receipt.
- Do not claim an OCR fix is "verified" — it's verified only after the Mac test
  run passes.
- **Don't restate that the code is uncompiled, and don't give keystrokes.** Josh
  develops on the PC and tests on the Mac; he knows. Say what changed and why.

## Steps for every OCR change

1. **Capture the receipt as a test.** Add a `func test<Merchant>_<what>()` to
   `ReceiptOCRServiceTests.swift` using the `blk(_:x:y:)` helper to lay out the
   real lines (label + right-aligned amount as separate blocks; Vision y
   increases upward, top ≈ 0.9, bottom ≈ 0.3). Assert the correct amount, and
   merchant/currency/date where the receipt exercised those.
2. **Reason before editing.** Trace the receipt through `extractAmount`'s
   scoring: exclusion patterns → labelled-total candidates (strong/generic/
   payment/subtotal) → cross-confirmation (`repeats`) → subtotal floor →
   fallbacks. Identify exactly why the current code picks the wrong value.
3. **Make the change general, not receipt-specific.** Prefer a heuristic that
   explains a *class* of receipts (e.g. "a total is always ≥ the subtotal",
   "the total is restated on the payment line") over a pattern that only fixes
   this one. Note the class in a code comment.
4. **Re-check the whole corpus in your head.** Walk the existing test cases
   (Hendry's, Sushia, Paris, Bunnings, Monos, KFC, …) and confirm the change
   doesn't break them. If any would regress, rethink.
5. **Hand off.** Commit test + fix together. State the root cause and what
   changed — no keystrokes, no "still uncompiled".

## The corpus so far (keep this list current)

| Receipt     | Trap                                                   | Correct |
|-------------|--------------------------------------------------------|---------|
| Hendry's    | tax line "$0.54" misread as "$54"; total restated      | $5.89   |
| Sushia      | "Sale Staff: Melissa"; tax line; tilted                | $30.90  |
| Paris       | French "MONTANT DU"; TVA/HT; euro                      | €81.50  |
| Bunnings    | "GST included in the total"; future-date misread       | $38.80  |
| Monos       | "TOTAL SAVINGS"; "Total (GST incl.)"                   | $300.00 |
| KFC         | item name "15 Wicked Wings $10" repeats value 10       | $26.55  |
| Woolworths  | savings ("You saved"/"Specials") + per-kg rate lines ("@ $33.00/kg") beat the small-print TOTAL; label and amount are separate blocks | $49.49 |
| Woolworths (header) | large wordmark + swirl logo, script tagline, address and ABN packed beneath. Largest-text pass now takes the wordmark directly. A stray `@` from the logo glyph used to disqualify it via the email pattern. | merchant `Woolworths` |
| Liquorland | long docket; letter-spaced wordmark at the top OCR'd at low confidence so the whole-receipt high-confidence pass took the crisp "TOTAL (Inc GST)" as the merchant. Total/structural labels are now rejected as merchant candidates. | merchant not a total line |
| Cherry Beans | receipt floats mid-frame with table around it, so the wordmark sat below the image-relative top-40% gate and the merchant fell through to "chip" off the "Contactless chip" line. largestHeaderText now uses the receipt-relative top, like the masthead fallback. | merchant `Cherry Beans Kellyvil` |
| Deus (Bali, IDR) | grouped thousands "655,000" truncated to 655.00 by the cents regex; stylised logo OCR-ing as `€` set the currency to EUR; crisp promo banner at the foot beat the crumpled letterhead for merchant. Currency now falls back to the country named in the letterhead — receipts print where they were issued far more reliably than a currency code. | $4,640,000 IDR, `PT. Deus Ex Machina Indonesia` |
| Woolworths (store line) | `WOOLWORTHS 1659   KELLYVILLE   NSW` — the store number parses as an amount, so the chain name looked like half of a label-value pair and the suburb won. Took three attempts: the first two diagnosed plausible-but-wrong causes from the corpus instead of tracing these blocks. | merchant `WOOLWORTHS` |
| Berry General Store | wordmark "BERRY GENERAL STORE" split across two stacked lines; a lone "NSW" won the all-caps pass. Fixes: reconstruct stacked all-caps header lines into the wordmark; a recurring 2+ word phrase beats a one-word token (no place list). The auto-note grabbed the "1 Aug 2026" date line, so dates/times are excluded from item detection. | merchant `BERRY GENERAL STORE`; note `Ricotta Hotcakes ×2` |
| Maw Maw (Kellyville) | bold shop name "MAW MAW" OCR-garbled to "MAH MAN" up top; two address lines then out-ranked it. (1) The centre "KELLYVILLE GROVE" recurs (header + footer "Kellyville Grove/30") → fixed by dropping any street/centre-suffix phrase (GROVE/COURT/ROAD…) from the recurring-phrase boost (suffix only — a suburb-token test would break "Berry General Store"). (2) "KELLYVILLE NSW 2154" had its postcode stripped by `dropTrailingStoreNumber` → "KELLYVILLE NSW", which recurred with the footer state line and won → fixed by never treating a 4-digit number after a state abbrev as a store number. With both out, the garbled header "MAH MAN" is unusable, so the name is recovered from the footer return-address: a clean "<Business> <Suburb>" line ("Maw Maw Kellyville") with the suburb stripped → "Maw Maw". `footerBusinessName` fires only when the receipt names a suburb (a "<suburb> STATE postcode" line) and is ranked *below* the header wordmark passes, so a clear header always wins and only a garbled one falls through to it. | merchant `Maw Maw` ($46.70) |
| Maw Maw (date) | date line `#189682-71 KAW 27-Aug-2026 12:07:18` — a written month with **hyphen** separators. The written-date regex only allowed space/comma between day, month and year (`\d{1,2}\s+MON[\s,]+\d{2,4}`), and the numeric regex needs digits in all three slots, so `27-Aug-2026` matched neither and the date fell back to Today. Fix (a class, not this receipt): the written-date separators are now any of space/comma/hyphen/dot, and `parseWrittenDate` normalises them all to single spaces before formatting. | date `2026-08-27` |
| Woolworths (Castle Hill) | two-word suburb "CASTLE HILL" prints in the letterhead address AND the EFTPOS footer ("CASTLE HILL" beside "NSW"), so it recurred and won the recurring-2+word-phrase boost over the wordmark ("HILL" isn't a street/centre suffix). Plus the wordmark carried the swirl logo OCR'd as an "O" ("Woolworths O"). Fixes: `suburbPhrases` (same-block "<suburb> STATE postcode" **and** split "<suburb block> <STATE block>" on one line) are excluded from the recurring-phrase anchor; `stripCorroboratedLogoGlyph` drops a lone leading/trailing single letter when the de-glyphed name stands alone in another block (footer "WOOLWORTHS"), so a real "Big W" is safe. | merchant `Woolworths` ($19.75) |
| Bónus (Iceland, ISK) | total "4.031" is 4031 krónur — Iceland (much of Europe) prints "." as the **thousands** separator and ISK has no minor unit. The grouped-thousands handling only covered a comma ("655,000"); the dot form parsed as 4.03. Fix (a class): a separator (`.` or `,`) before exactly **3** digits is a thousands group, not cents (cents are always 2 digits) — added a dot-grouped alternative to `amountPattern` and dot-stripping to `parseAmount`. | $4031 |
| US / global regions | the suburb-recurrence guard was Australia-only (`NSW\|VIC\|…`). Tally is global, so `regionCodeAlternation` now covers US states and Canadian provinces too; "NORTH LAS VEGAS NV" and "MONTREAL QC" are recognised as places like "CASTLE HILL NSW". Also: `footerBusinessName` had split "NORTH LAS VEGAS" into "NORTH LAS" (stripping only the last word "vegas" as the suburb), which recurred and expanded back to the full address — so a recurring anchor that is a **whole-word fragment** of a suburb phrase ("north las" ⊂ "north las vegas") is now excluded, not only an exact match. | merchant `Walmart`, not the city |
| Jack in the Box (US) | topmost line is "Drive-Thru Order# 1044"; merchant is the line below. Total $39.09 (subtotal + tax); "(4 @ 3.49)" is a unit rate. Passed as-is — pinned so it stays that way. | $39.09 |
| Trader Joe's (US) | no "TOTAL" label — the bill is "Balance to pay" / card, both $81.87 (cross-confirmed). "Tax: $66.63 @ 1.8%" is a taxable base @ rate, excluded by `@ $n`. Passed as-is — pinned. | $81.87 |
| Meijer (US) | savings block up top ("SAVINGS TOTAL 2.00") excluded; store brand recurs on item lines ("MEIJER MILK/EGGS") but is one word so it can't hijack the merchant. Passed as-is — pinned. | $18.80 |
| Woolworths (sideways photo) | not a scoring bug — the block dump showed every box taller than wide (each line running top-to-bottom), because the camera photo was stored with a `.right` orientation flag and OCR ran on the raw `image.cgImage` with no orientation given to Vision. Read rotated 90°, "top of receipt" and "largest text" pointed at the wrong axis and the suburb won. Fix is upstream of scoring: pass the UIImage's orientation to `VNImageRequestHandler`. Block-injection tests can't reach this (they feed upright boxes); the mapping is pinned by `testImageOrientation_mappedForVision_notByRawValue`. | merchant `Woolworths` |

When a new receipt is reported, add a row here and a test case.

## This is a long-running loop, by design

The scanner improves by absorbing real failures one at a time. The user will
keep sending "here's another receipt that failed" — that is the process working,
not a setback. Each pass: diagnose from the receipt photo + the app screenshot,
pin the failure as a test, fix with a rule that generalises, re-check the corpus,
add the row. The corpus is the accumulated memory that stops
any of these ever coming back.

### Recurring trap families seen so far

- **Non-total lines that look total-ish**: tax/GST components, savings/specials/
  promotional amounts, change, rounding, tips. Excluded outright by pattern.
- **Coincidental repeats**: a value that appears twice for unrelated reasons
  (an item name containing `$10` priced $10.00) can fake cross-confirmation —
  the subtotal floor guards this, since a total is always ≥ the subtotal.
- **Legibility bias**: large promotional print OCRs more reliably than the small
  monospace total on long receipts shot at an angle, so the wrong figure can be
  the *only* thing read. Exclusions must therefore be robust, and returning
  nothing is better than returning a confidently wrong amount.
- **Locale/label variance**: French (MONTANT DU, TTC, TVA, HT) and AU/UK phrasing
  ("Take Away Total", "TOTAL includes GST"). Expect more languages over time.
- **Unit rates, not amounts**: weighed-item lines ("0.047 kg NET @ $33.00/kg")
  and "Qty 2 @ $7.00 each" are per-unit prices. Excluded via `@ $n`, `/kg`,
  `each`.
- **"Same line" is not one test.** Vision boxes differ in height, so which box
  you divide by decides the answer. `sameLine` (÷ the *shorter* box) is right
  for amounts, where a label and its right-aligned figure legitimately differ
  in size. `sharesPrintedLine` (÷ the *taller* box, plus a ≤2× height-ratio
  gate and a horizontal-disjointness test) is required for merchant pairing:
  a store name is printed large above small print, so the loose test made the
  tagline "share a line" with the wordmark on any skewed photo. Use the strict
  one whenever the question is "is this block half of a label-value pair?"
- **Substring matching eats real names.** Noise phrases must be stripped with
  word boundaries — a bare `replacingOccurrences` of "cash"/"pos"/"time"
  mangles "Cashmere Boutique", "Post Office", "Timezone".
- **Exclusion is a property of the LINE, not the block.** Vision splits a row
  into a left label and a right-aligned amount, so "Specials" and "$14.90"
  arrive separately. Excluding only the label leaves the amount free to win a
  fallback — this is exactly how Woolworths returned $14.90 even after
  "Specials" was added to the exclusion list. `isExcluded(_:in:)` makes an
  amount inherit the exclusion of anything sharing its line; **use it, never
  the raw `matches(amountExclusionPattern:)`, when scanning blocks for
  amounts.**

### Look at the receipt photo, not the app screenshot

The app's hero image **crops** the receipt. A session read that thumbnail,
concluded the source photo had no wordmark, and said so in a commit message —
the full photo has a large clear one. Four wrong diagnoses of one receipt all
came from inferring the input instead of looking at it. Ask for the original
photo, and use the `OCR|` block dump for what Vision actually returned.

### A passing test does not mean the receipt works

The synthetic layouts assume the lines you wrote actually OCR'd. A real photo
may drop the small print entirely, so a test can pass while the receipt still
fails. When a receipt fails in the field, add a **degraded** variant too — only
the lines that plausibly survived OCR — and assert the wrong value is *never*
returned. Returning `nil` (user types the amount) beats a confident wrong
answer.
