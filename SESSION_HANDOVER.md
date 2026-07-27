# Tally — Project Brief & Session Handover

*Everything a new session (human or AI) needs to work on Tally: what the product
is, how it makes money, how it's built, how Josh works, what's shipped, what's
broken, and what to do next. Read it top to bottom before touching code.*

Last updated: 2026-07-20

---

## 0. Orientation — read these, in this order

```
SESSION_HANDOVER.md                               # this file — start here
Tally/Tally - Everything You Need To Know.md      # deep product/design/flow reference
MONETISATION_BRIEF.md                             # monetisation law (repo root)
.claude/skills/ocr-regression/SKILL.md            # OCR guardrail workflow
TallyTests/ReceiptOCRServiceTests.swift           # the receipt regression corpus
```

The canonical doc's filename **contains spaces** — quote it, don't glob it:
`Read "Tally/Tally - Everything You Need To Know.md"`. A previous session burned
two failed searches on this.

**Precedence when sources disagree: the code wins**, then `MONETISATION_BRIEF.md`
for monetisation, then the canonical doc, then this file. If you find a
contradiction, verify against the code and fix the doc **in the same session**.
Leaving it is how the mess in §6 happened.

---

## 1. What Tally is

A minimal iOS expense tracker for individuals and small businesses. Snap a
receipt, tag it, export it. Data lives in the user's own iCloud — no backend, no
server-side user data.

**The golden path must stay under ~60 seconds for a new user, and logging one
expense must feel like five seconds.** Almost every design argument on this
project resolves by asking whether a change protects or attacks that. It's why
interstitial ads keep getting rejected, and why the OCR quota meters volume
rather than blocking entry.

**Tally is NOT** accounting software, a reimbursement workflow, or a finance
dashboard. It is capture → tag → export. Resist feature requests that drag it
toward any of the three.

Platform: iOS, SwiftUI, SwiftData, `@Observable` state. Vision framework for
on-device OCR. RevenueCat over StoreKit 2. AdMob banners.

---

## 2. Who you're working with, and how to work

Josh (`joshmalosh`) — builds on a Mac, develops the repo on Windows. He is the
product owner and makes all product calls; bring him decisions, not surveys.

**Conventions he cares about, learned the hard way:**

- **Multi-step instructions: flat numbered steps, one action each, no
  branching.** When re-explaining any step, restate all remaining steps in the
  same message — he's on the Mac and won't scroll back. When many errors share
  one root cause, lead with the cause. He has called out instructions that
  "jump and change" and are "messy and overcomplicated."
- **Answer from the code, never from memory or the briefs.** On 2026-07-20 he
  called out repeatedly contradictory answers about the free/Pro split. The
  cause wasn't forgetfulness — the code genuinely disagreed with itself (CSV
  meant 2, 1, or 0 depending on which call site you read) and with the brief in
  four more places. Grep every call site and reconcile *before* answering.
- **Never claim something is verified from the Windows box** — no Swift toolchain
  here. But say it once, if at all. Josh develops on the PC and tests on the Mac;
  he knows the code is uncompiled and he knows how to pull and run it. **Do not
  append "still uncompiled" to every message, and do not spell out ⌥⌘X / ⌘U
  keystrokes.** Report what changed and why. He'll test it.
- **Be precise with names.** On Add Expense, the "banner" is a real AdMob ad;
  `proUpsellCompactBanner` is an in-app upsell strip. Saying "banner" ambiguously
  cost a whole exchange.
- **Don't dredge up old unresolved threads at the end of unrelated work.** Raise
  a problem when it's actionable, then fix it.
- **Push:** `git push tally dev`. End commit messages with `Co-Authored-By:
  Claude …`. Don't run the pre-push reviewer for `dev` (only `main`/`master`).

---

## 3. Environment & repo reality

- **Working dir** `E:\Projects\ASimpleLife` (Windows). The app mirrors to
  **github.com/joshmalosh/Tally.git** via the `tally` remote. **Always push to
  `tally` `dev`.** Never `origin` (that's the website repo), never `main`/`master`
  without explicit instruction. `TallyRepo/` inside the monorepo is a separate
  clone — don't edit it.
- **No Swift/Xcode toolchain on Windows.** You cannot compile, run, or test.
  Josh pulls `dev` in Xcode, runs, and reports back with screenshots
  and device logs.
- **New source files need manual registration** in
  `Tally.xcodeproj/project.pbxproj` (old-style project, no synchronized groups).
  This applies to test files too — a test file not added to the TallyTests
  target means ⌘U passes while running none of it, which is a silent failure
  and the worst kind. **You can edit `project.pbxproj` from here**; it's plain
  text. Four places per file: `PBXBuildFile`, `PBXFileReference`, the group's
  `children`, and the target's `Sources` build phase. Mirror an existing entry,
  use a unique 24-char-ish ID, then sanity-check with `grep -c` (expect 4 hits)
  and a brace-balance count. A malformed pbxproj fails loudly in Xcode, so this
  is a safe thing to attempt blind — unlike Swift, which fails at compile time
  you can't see.
- **Targets:** `Tally` (`com.asimplelife.tally`), `TallyShare` (share extension,
  `com.asimplelife.tally.share`), `TallyTests`. Both app and extension declare
  App Group `group.com.asimplelife.tally`. The app's entitlement being empty once
  silently broke the entire share handoff ("client is not entitled" in logs).
- **URL scheme** `tally://`, used by the share-extension handoff.
- ⚠️ **Josh runs Pro. This is confirmed and settled — do not question it again.**
  `RevenueCatConfig.forcePro = true` sets `subscriptionStatus = .pro` on launch,
  and `isPro` is `debugForcePro || subscriptionStatus == .pro`. So when he reports
  a bug, **he is a Pro user** — never explain a problem away as "the free-tier
  gate working as designed." That answer was given once about a blank merchant,
  was wrong, and wasted a real OCR bug.
  Free-tier behaviour (ads, Go Pro pill, scan quota, CSV limit) is therefore
  **not visible in his build**. Don't ask him to flip `forcePro` to check it
  unless he specifically wants to test the free tier.
- **Tests** run on the Mac with **⌘U**. ⌘6 opens the Test navigator; click a red
  test to jump to the failing assertion. Click the ◇ beside a class name to run
  one file.

---

## 4. Architecture & key files

- **Entry** `Tally/TallyApp.swift`. **Models** `Tally/Models/` (SwiftData
  `@Model`; soft delete via `deletedAt`). **Domain** `Tally/Domain/` (parsing,
  calculations). **Theme** `Tally/Theme/` (tokens + shared components).
- **`Tally/AppState/AppState.swift` owns every free-tier limit** —
  `canExportCSV`/`recordCSVExport`, `canUseOCR`/`recordOCRScan`/
  `ocrScansRemaining`, `shouldShowUpgradePrompt`, `isPro`. **Change a limit here,
  never at a call site.** Pinned by `TallyTests/MonetisationGatingTests.swift`.
- **OCR** `Tally/Services/ReceiptOCRService.swift` (+ corpus
  `TallyTests/ReceiptOCRServiceTests.swift`). See §9 before touching it.
- **Home** `Tally/Views/Home/HomeView.swift` — list, Rise gradient, shred host,
  filters, inline ads, Go Pro pill. It is also the **shell for the Reports and
  Tags tabs**, which is why the docked banner covers all three.
- **Add/edit** `Tally/Views/AddExpense/AddExpenseView.swift`;
  `MultiReceiptReviewView.swift` for bulk import. **Detail + `FullImageView`**
  `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`.
- **Paywall & limits:** `SubscriptionView.swift`; `ProFeatureSheet` and
  `ScanLimitSheet` both live at the bottom of `Tally/Views/Export/ExportView.swift`.
  Ad plumbing `Tally/Services/AdManager.swift`, `Services/RevenueCatConfig.swift`.
- **Export** `Views/Export/` — `GlobalExportSheet.swift` is the big one and has
  **six CSV/PDF call sites**; they must all agree on the limit.
- **Share extension** `TallyShare/` + `Services/SharedInboxService.swift`
  (App Group inbox; app auto-opens into the review flow).

**SwiftUI gotchas already paid for:** `.rotationEffect` after `.position()`
rotates around the *parent's* centre; combining two independently-animated
values in one `.offset(x:y:)` bleeds one animation into the other; GeometryReader
re-measures on parent re-renders (it caused the shred drift — the final version
uses bottom-alignment + padding instead).

---

## 5. The product model (free vs Pro)

`MONETISATION_BRIEF.md` is authoritative; these numbers were reconciled with the
code on 2026-07-20 and currently agree.

| Capability | Free | Pro ($4.99/mo) |
|---|---|---|
| Manual entry, uploads, tags, edit/delete, bulk delete, iCloud sync | Unlimited | Unlimited |
| **OCR receipt scanning** | **10 successful scans/month** | Unlimited |
| CSV export | 1 per calendar month | Unlimited |
| PDF export | No | Yes |
| Ads | Banners | None |

**OCR quota rules:** one pool across every entry point (camera, library, PDF,
share extension, bulk import — 5 receipts spends 5). 10 usable scans; the **11th**
is blocked. **Only a scan that extracted an amount is charged** — if the user
still has to type the number, we did nothing for them. Free users get the *full*
extraction (amount, date, merchant, notes); there is no field-level gating. The
gate never blocks logging an expense, only the automatic extraction.

**Ads (free only):** docked banner on Home/Reports/Tags, Add Expense, and Expense
Detail; inline in the Home list below the pinned tags and after **every 10th
expense**, counted continuously across the list. **Never in sheets or modals.**
**No interstitials** — rejected twice; they'd sit inside the five-second logging
loop.

**Upgrade prompts:** Go Pro pill in the Home header; Settings row; CSV limit
sheet; scan limit sheet; Pro benefits card on the 3rd/6th/9th expense of a month
(max 3/month, never mid-batch); daily prompt on first open every 3 days, never in
the user's first 3 days, suppressed while another sheet is up. Tone is always
calm — no urgency, no countdowns, no red. CTA "Upgrade to Pro" / "Go Pro",
dismiss "Not now".

**The paywall may only list built features the free tier lacks.** It previously
advertised "Advanced filters" (never a real feature — no code ever gated it) and
"Monthly auto-export" (never built). Both deleted.

---

## 6. Current state — what's shipped (newest first)

- **⚠️ Merchant extraction fix** (`aaf90bd`) — **uncompiled.** A Woolworths
  receipt returned a blank merchant on device while the synthetic test asserting
  `merchant == "Woolworths"` passed. `sameLine` divides vertical overlap by the
  *shorter* box, so on a skewed photo the small tagline under a large wordmark
  counted as sharing its line; the address line below parses "an amount" from its
  street and phone numbers, and the merchant was discarded as half of a
  label-value pair. Added `sharesPrintedLine` (÷ the *taller* box, ≤2× height
  ratio, horizontally disjoint) for merchant pairing only; `sameLine` is untouched
  so the amount corpus is unaffected. Also fixed noise-phrase stripping to match
  whole words ("cash" was turning "Cashmere Boutique" into "mere Boutique").
- **⚠️ Monetisation reconciliation + OCR scan quota** (`ef30412`, `68032a2`,
  `0cc4b6c`) — **uncompiled.** An audit of code vs. brief found six divergences:
  1. **CSV was incoherent** — the constant said 2, four of six export paths
     ignored it and hard-gated on `isPro` (0). Now **1 everywhere** via
     `canExportCSV`; the two paths that failed *silently* at the cap now show the
     limit sheet.
  2. **OCR: field gating → volume quota** (see §5). A permanently blank merchant
     read as a broken scanner, not a paid tier.
  3. **"Advanced filters" deleted** — a false paywall claim.
  4. **"Monthly auto-export" deleted** — never built.
  5. **Ads → MyFitnessPal model** — every full screen plus inline in the list.
     Supersedes the old "no inline sponsored rows" rule.
  6. **Interstitials rejected again.**
  Added the **Go Pro pill** and the **daily upgrade prompt**. New
  `TallyTests/MonetisationGatingTests.swift` pins every number; registered in
  `project.pbxproj` in `3272b01`. All four docs reconciled in `0cc4b6c`.
- **Receipt viewer + thumbnails** (`ea769fa`): `FullImageView` has pinch-zoom
  (1×–6×), pan, double-tap, drag-to-dismiss. Thumbnails rebuilt as a self-loading
  `ReceiptThumbnailView` (each cell owns its state) — fixed "hit or miss until you
  scroll."
- **Delete "shred" animation** (`36bfb98`→`0d5170e`): swipe-delete on Home is
  instant (no confirmation); in-expense Delete keeps its confirmation. A receipt
  shreds at bottom-centre behind the FAB with a rigid haptic — tilted ~20° left,
  pivoting on a centred base, **rotation-only rumble** (no vertical jump), drop
  shadow, ~1.6s.
- **OCR accuracy overhaul + regression net** (`e3fc22a`, `5b6e5c7`, `47129e6`,
  `0507ac6`): scored amount extraction, tax/savings exclusion, cross-confirmation,
  subtotal floor, French labels, future-date rejection, currency detection,
  merchant guards. Plus the `ocr-regression` skill.
- **Quick Add / Add Expense fixes** (`9221bcd`, `e368d2e`, `a3bc85a`): amount-field
  caret, dark placeholder text, tap-to-dismiss keyboard, and the **merchant-field
  lag** — caused by a banner in both branches of a conditional, destroying and
  recreating the AdMob WebView on every keyboard toggle.
- **Tag sort**: expense tag picker defaults to most-recently-used (derived from expense dates, no schema change); all tag lists gain an A–Z / Z–A / Recent filter button. `Tally/Views/Tags/TagSorting.swift`.
- **Recurring filter** (`47129e6`), **Home "Rise" gradient** (bottom-most layer —
  never put UI translucency over it), **share-to-Tally** with auto-open,
  **SKAdNetwork IDs** (`61e5e95`).

---

## 7. Settled decisions (do not relitigate without Josh)

FAB opens the entry menu • celebrations/sounds stay • Home tag bar is the user's
explicit choice • Reports keeps its tab, Export keeps its button • single-tag rule
(standalone / group / group+sub-tag) • **Home gradient is the bottom layer** • no
pre-filled tag "suggestion" chips that read as selections • `MONETISATION_BRIEF.md`
is monetisation law; no usage caps on core tracking • **no interstitial ads**
(rejected twice) • shred is a rotation-only rumble centred under the FAB.

Added 2026-07-20: **OCR is metered by volume, never crippled by field** • **a
failed scan is never charged** • **the paywall may only list built features the
free tier lacks** • **CSV is 1/month, enforced identically on every path** • **ads
on every full screen and inline in the list, but never in sheets**.

---

## 8. Open items (prioritised)

0. **Nothing from 2026-07-20 has been built.** `ef30412`…`09a2ada` went to both
   `tally/dev` and `tally/main` unbuilt. Expect 18 OCR + 9 gating tests. The
   open question is whether the Woolworths merchant now reads `WOOLWORTHS`.
   A pre-push review caught three defects in these commits, fixed in `4f8530d`:
   an undefined-symbol compile error in `TagExportPickerSheet`, a bulk-import
   quota that never enforced (the loop re-read a counter that only updates after
   the async Task completes), and an O(n²) rebuild on the Home list. The fixes
   are themselves unverified — if the build fails, start there.
   Josh runs Pro, so the free-tier work in `ef30412` (ads, Go Pro pill, limit
   sheets) won't appear in his build and doesn't need checking unless he asks.
   `MonetisationGatingTests.swift` is registered in `project.pbxproj` (`3272b01`)
   so no manual drag is needed — but that registration is itself unverified. If
   Xcode reports a corrupt project, that commit is the suspect; a bad pbxproj
   fails loudly and immediately.
1. **Pro is not purchasable.** `com.asimplelife.tally.pro.monthly` doesn't exist
   in App Store Connect, so RevenueCat offerings come back empty every launch and
   subscription revenue is **$0**. Biggest open item by a distance — every
   monetisation change above is free-tier only and earns nothing until this
   exists. Josh will want step-by-step help.
2. **TestFlight** for friends/family: archive → upload → external group/public
   link. Needs a privacy-policy URL and an export-compliance answer (consider
   `ITSAppUsesNonExemptEncryption = NO`). Switch AdMob to **test** ad units first.
3. **CloudKit is disabled** (`TallyApp.cloudKitEnabled = false`). Enable once
   iCloud entitlements are configured. **Schema note (verified in code):** there
   is no store-version/delete-store mechanism — SwiftData does automatic
   lightweight migration, which is why adding the defaulted `isRecurring` was
   safe. A failed migration throws → `fatalError` → crash on launch; recovery is
   delete + reinstall. Anything riskier than adding a defaulted property needs a
   real `VersionedSchema`/`MigrationPlan` before CloudKit goes on.
4. **SKAdNetwork list** — confirm current from Google's official page before
   submission.
5. **Deferred design debt:** bulk-import `TagLinkPickerSheet` restyle to the
   shared picker language; a written component constitution / colour-token
   reconciliation (colours drifted screen-by-screen across redesigns).

---

## 9. OCR regression testing (read before touching the scanner)

OCR is **metered** — 10 successful scans/month free, and a scan only counts if it
extracted an **amount**. Accuracy is therefore monetised in both directions: a
wrong amount fails the user, an empty one silently refunds their scan.

**Merchant extraction is no longer Pro-gated.** A reported blank merchant is a
parser bug now. (It used to be the paywall, and answering "that's the Pro gate"
was technically true and completely useless — don't repeat it.)

### The loop (ongoing and accumulating, by design)

The scanner is **not** "finished". It improves by absorbing real failures one at
a time; the corpus is the accumulated memory of that.

1. **Josh scans a receipt and it comes out wrong** — he sends the receipt photo
   plus a screenshot of what Tally produced.
2. **Diagnose from the pair**: work out which line the parser latched onto and
   why (a savings figure seen twice, a tax line, a staff name, a foreign label,
   an item name containing `$`).
3. **Pin it as a test *before* fixing**, so the failure is captured permanently.
4. **Fix with a general heuristic** that explains a whole class of receipts, never
   a hack for this one — then re-check the existing corpus by hand.
5. **Add a row** to the corpus table below **and** in the skill file.
6. **Josh builds and re-scans on the Mac** to confirm.

Expect this loop to keep running for a long time. A new failing receipt is the
process working, not a setback.

### Hard rules

- **Never change `ReceiptOCRService.swift` without adding or updating a test for
  the receipt that motivated it.**
- **A passing synthetic test does not mean the receipt works.** The layouts
  assume the lines you wrote actually OCR'd, and `blk()` gives every block the
  same height. Both assumptions have hidden real bugs: the Woolworths merchant
  case passed for days because its header sat alone with nothing near it. When a
  receipt fails in the field, reproduce the **real** geometry — explicit
  `CGRect`s if heights matter — and add a **degraded** variant with only the lines
  that plausibly survived.
- **Returning `nil` beats a confident wrong answer.** The user typing the amount
  is a far better outcome than silently saving the wrong one.

### The corpus (add a row per reported receipt)

| Receipt | Trap it guards against | Correct |
|---|---|---|
| Hendry's | tax line "$0.54" misread as "$54"; total restated on card line | $5.89 |
| Sushia | "Sale Staff: Melissa" as merchant; tax line; tilted photo | $30.90 |
| Paris | French "MONTANT DU" / TVA / HT; euro currency | €81.50 |
| Bunnings | "GST included in the total"; date misread as future (2028) | $38.80 |
| Monos | "TOTAL SAVINGS"; "Total (GST incl.)" is the real total | $300.00 |
| KFC | item name "15 Wicked Wings $10" repeats the value 10 | $26.55 |
| Woolworths | savings ("You saved"/"Specials") + per-kg rates ("@ $33.00/kg") outrank the small-print TOTAL; label and amount are separate blocks | $49.49 |
| Woolworths (header) | large wordmark + swirl logo, script tagline, address and ABN beneath. Largest-text pass takes the wordmark directly. A stray `@` from the logo glyph used to disqualify it via the email pattern. | merchant `Woolworths` |
| Cherry Beans | receipt floats mid-frame with table around it, so the wordmark sat below the image-relative top-40% gate and the merchant fell through to "chip" off the "Contactless chip" line. largestHeaderText now uses the receipt-relative top, like the masthead fallback. | merchant `Cherry Beans Kellyvil` |
| Deus (Bali, IDR) | grouped thousands "655,000" truncated to 655.00 by the cents regex; stylised logo OCR-ing as `€` set the currency to EUR; crisp promo banner at the foot beat the crumpled letterhead for merchant. Currency now falls back to the country named in the letterhead — receipts print where they were issued far more reliably than a currency code. | $4,640,000 IDR, `PT. Deus Ex Machina Indonesia` |
| Woolworths (store line) | `WOOLWORTHS 1659   KELLYVILLE   NSW` — name+store-number block rejected for containing a digit, so the suburb won | merchant `WOOLWORTHS` |

### Recurring trap families

- **Non-total lines that look total-ish**: tax/GST components, savings, specials,
  change, rounding, tips. Excluded by pattern.
- **Coincidental repeats**: a value appearing twice for unrelated reasons can fake
  cross-confirmation — the subtotal floor guards this (a total is always ≥ the
  subtotal).
- **Legibility bias**: large promotional print OCRs more reliably than the small
  monospace total on a long receipt shot at an angle, so the wrong figure can be
  the *only* thing read.
- **Unit rates, not amounts**: "0.047 kg NET @ $33.00/kg", "Qty 2 @ $7.00 each".
- **Locale/label variance**: French (MONTANT DU, TTC, TVA, HT), AU/UK phrasing.
- **Exclusion is a property of the LINE, not the block.** Vision splits a row into
  a left label and a right-aligned amount, so "Specials" and "$14.90" arrive
  separately. Use `isExcluded(_:in:)`, never the raw pattern match.
- **"Same line" is not one test.** `sameLine` (÷ the *shorter* box) is right for
  amounts, where a label and its right-aligned figure legitimately differ in
  height. `sharesPrintedLine` (÷ the *taller* box, ≤2× height ratio, horizontally
  disjoint) is required for merchant pairing, because a store name is printed
  large above small print.

### Adding a new receipt

1. Add `func test<Merchant>_<trap>()` to `ReceiptOCRServiceTests.swift`.
2. Lay it out with `blk(_:x:y:)` — label and right-aligned amount as **separate
   blocks** sharing a `y`. Vision coords: `y` is normalised and **increases
   upward** (top ≈ 0.9, bottom ≈ 0.3). Use explicit `CGRect`s when relative text
   size is part of the bug.
3. Assert the amount via `amount(_:from:)`; assert merchant/currency/date where
   the receipt exercised them.
4. Add a corpus row here **and** in the skill file.
5. Fix generally; note the class in a code comment.
6. Re-check the whole corpus by hand, then hand off. **Never call an OCR
   fix verified until Josh confirms a green run.**
