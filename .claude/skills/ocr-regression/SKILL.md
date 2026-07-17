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

Tally's OCR is a **paid** feature and its accuracy has repeatedly regressed
when one fix broke a previously-working receipt. This workflow makes that
impossible to do silently.

## Hard rule

**Never change `ReceiptOCRService.swift` without adding or updating a test case
for the receipt that motivated the change.** Every receipt a user reports —
right or wrong — gets pinned in `TallyTests/ReceiptOCRServiceTests.swift`.

## Environment reality

The dev machine is **Windows with no Swift/Xcode toolchain**, so the tests
**cannot be executed here** — the parser depends on Vision/CoreGraphics. Tests
run on the user's **Mac** via **Cmd+U** (or `xcodebuild test`). Therefore:

- You must **reason through** the new receipt against the scoring logic by hand
  and state the expected outcome before editing.
- Every OCR change's hand-off message MUST end with an explicit instruction to
  run the OCR test bundle on the Mac (Cmd+U) and re-scan the reported receipts.
- Do not claim an OCR fix is "verified" — it's verified only after the Mac test
  run passes. Say "added a test; run Cmd+U to confirm."

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
5. **Hand off with the run instruction.** Commit test + fix together. Tell the
   user: pull, **Cmd+U** to run the OCR suite, and re-scan the reported
   receipt(s).

## The corpus so far (keep this list current)

| Receipt   | Trap                                              | Correct |
|-----------|---------------------------------------------------|---------|
| Hendry's  | tax line "$0.54" misread as "$54"; total restated | $5.89   |
| Sushia    | "Sale Staff: Melissa"; tax line; tilted           | $30.90  |
| Paris     | French "MONTANT DU"; TVA/HT; euro                 | €81.50  |
| Bunnings  | "GST included in the total"; future-date misread  | $38.80  |
| Monos     | "TOTAL SAVINGS"; "Total (GST incl.)"              | $300.00 |
| KFC       | item name "15 Wicked Wings $10" repeats value 10  | $26.55  |

When a new receipt is reported, add a row here and a test case.
