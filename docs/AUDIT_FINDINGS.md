# Tally audit findings — Phase 1

Date: 2026-10-04. This is the "find before we fix" pass. **Nothing here has been
changed.** It is a list of what the audit turned up, ranked by severity, for you
to triage before any fix lands.

---

## How this was audited

Two methods, used together:

1. **On-device drive** (iPhone 17 Pro simulator) of the paths that changed most in
   the recent redesign burst: Quick Add, the home header (full, compacted, filtered,
   large-total-on-free), and the add/save flow.
2. **Code review** of the delete / undo / multi-select, the breakdown-bar and
   period-filter maths, the financial-year anchor, and the attachment gating.

Coverage is deliberately weighted to the areas that just changed. Reports, Insights,
Settings, OCR, statement import and sync were **not** re-driven end to end this pass
(they were untouched in the redesign), so they carry a lighter, code-only confidence.
If you want a dedicated deep drive of any of those, say which and I will.

A build with the current working tree compiles clean (exit 0, no Swift warnings).

---

## Findings

### F1 · Quick Add cannot save on an amount alone (High)

`canSave` (AddExpenseView, ~line 178) returns false for a manual entry whenever the
merchant is empty: `if !hasAttachment && merchant.trimmed.isEmpty { return false }`.
So on Quick Add, which is meant to "drop you straight into the amount field", typing
an amount and hitting Save does nothing. The Save CTA stays greyed out until a
merchant is typed, then turns green.

This directly contradicts the agreed Quick Add intent (amount-first, one tap). It is
also almost certainly what made Save look dead in earlier Quick Add testing: the
button was disabled, not blocked.

Verified on device: $42.50 with a tag but no merchant kept Save greyed; adding
"Blue Bottle" turned it green.

**Decision needed from you:** should amount-only save (merchant optional, defaulting
to blank or "Expense"), or is a merchant genuinely required? That is a product call,
not something I should pick.

---

### F2 · The free-tier ad banner overlaps the Save button in the simulator (High, on-device UNVERIFIED)

On the simulator, the AdMob **test** banner renders at the very bottom and its WebView
sits over the Save CTA's tap region. With a valid, enabled (green) Save button, four
taps dead on the button did nothing. Two banners were stacking at once (one above, one
below the button), which is a test-banner layout glitch.

I could not confirm whether this also happens on your real device with a real banner,
so I am labelling it **UNVERIFIED on device**. What is certain is that the primary Save
CTA and a WebView ad share the bottom edge, which is fragile by construction. Two
consequences:

- It needs one check on your phone: does the real banner cover Save on the free tier?
- Regardless of the answer, the UI tests must launch with ads disabled or they cannot
  reliably tap anything at the bottom of the screen.

---

### F3 · Dead Quick Add code left behind (Medium, cleanup)

The Quick Add rewrite replaced eight view builders but did not remove the old ones.
All are now unreferenced in AddExpenseView: `quickAddHeroAmountBlock`,
`quickAddMerchantCard`, `quickAddExtrasRow`, `quickAddNoteCard`, `quickAddTagCard`,
`quickAddAttendeeCard`, `quickAddRecurringCard`, `quickAddKeypadChrome`.

Swift does not warn on unused private members of a type, so these compile silently and
will rot. Not a bug today, but dead weight that will confuse the next change to this
file. Safe to delete in the fix phase.

---

### F4 · "Add receipt" row still invites a receipt after a PDF is attached (Low)

The manual docket swaps to the photo layout only when an **image** is attached
(`receiptImageAttached = attachedImage != nil`). A PDF does not set that, so after
attaching a PDF the docket keeps the "Snap or upload a receipt" row at the top while
the PDF card shows below it. Confusing, not broken.

---

### F5 · Multi-delete does not post the delete notification (Low)

Single swipe-delete posts `.expenseDeleted` (HomeView line 1272); the multi-select
`deleteSelectedExpenses` (line 1363) does not. If anything refreshes off that
notification, a bulk delete would skip it. Worth making the two paths consistent.

---

### F6 · Breakdown bar excludes untagged spend (Low, by design — confirm it reads right)

`spendBreakdownSegments` only counts expenses whose resolved tag exists. Untagged
spend is left out of the bar. On a month that is mostly untagged, the coloured bar
will represent much less than the headline total, which could read as a mismatch.
Intended behaviour, but worth a look on real data before we call it final.

---

### F7 · Filtered-tag eyebrow colour may be faint for pale tags (Low)

When a pinned tag filters the view, the eyebrow shows the tag name in
`tag.colour.lightened(0.4)` on the dark green header. For an already-pale tag colour
that blend lands close to white and the 11px label loses contrast. Check the lightest
tags against the header.

---

## Things checked and found healthy

- **Large total on free no longer truncates.** The amount now sits on its own
  full-width row with `minimumScaleFactor(0.7)` and `lineLimit(1)`; the earlier
  "$33,…64" squeeze is fixed.
- **Soft-delete / undo / restore is sound.** Delete sets `deletedAt`, keeps the
  attachment, and undo re-fetches by id and clears it. No data-loss path found.
- **Financial-year anchor is correct.** `currentFinancialYearStart` rolls the year
  properly around the configured start month. The old "This Year / FY shows no top
  category" complaint is obsolete: the top-category element was replaced by the
  breakdown bar in the redesign.
- **Period and currency filtering is consistent** across the hero and the compacted
  header (both go through the same `spendBreakdownSegments` / `periodExpenses` logic),
  and foreign-currency expenses are correctly excluded from totals.

---

## Not bugs — known-pending features (from your earlier batch)

These are deferred work you already asked for, listed so they are not mistaken for
defects: Reports multi-select delete; the Recently Deleted redesign (home-list style
with a "deleted after 30 days" note); and the Breakdown / Trend toggle on the header.
