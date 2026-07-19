# Tally — Session Handover

*A snapshot of the current state of work for whoever (human or AI) picks this up next. For the full product/design/monetisation context, read `Tally/Tally - Everything You Need To Know.md` first — this file only covers where things stand right now.*

Handover written: 2026-07-17

---

## 1. Snapshot

- **Repo / branch:** working dir `E:\Projects\ASimpleLife` (Windows). App mirrors to **github.com/joshmalosh/Tally.git** via the `tally` remote. **Always push to `tally` `dev`.** Never `origin` (that's the website) and never `main`/`master` without explicit instruction.
- **Latest commit on `tally/dev`:** `ea769fa` — "Add pinch-zoom to full receipt view; self-loading thumbnails". Local `dev` is in sync with `tally/dev`; working tree clean apart from intentionally-untracked dirs (`.claude/` except the committed skill, `TallyRepo/`, `Website/`, `assets/`, ChatGPT brief).
- **Build/run happens on the user's Mac** (Xcode). This Windows box has **no Swift/Xcode toolchain** — you cannot compile, run, or execute tests here. The user pulls `dev` in Xcode via **⌥⌘X**, runs, and reports back (often with screenshots and device logs).
- **Test suite:** `TallyTests` runs on the Mac with **⌘U** (87 tests, all green as of the last run, including `ReceiptOCRServiceTests`).

---

## 2. What this session delivered (newest first)

- **Receipt viewer + thumbnails** (`ea769fa`): `FullImageView` now has native pinch-zoom (1×–6×), pan, double-tap, drag-to-dismiss. Thumbnails rebuilt as a **self-loading `ReceiptThumbnailView`** (each cell owns its state, loads on appear) — fixes the "hit or miss until you scroll" bug; removed the old global-`thumbnailVersion` machinery from HomeView.
- **Delete "shred" animation** (many commits, `36bfb98`→`0d5170e`): swipe-delete on Home is instant (no confirmation); the in-expense Delete keeps its confirmation. On delete a small receipt shreds at the bottom-centre behind the FAB/tab bar with a rigid haptic. Final form: tilted ~20° left, pivots on a centred base, lowers with a **subtle rotation-only rumble** (no vertical jump), drop shadow, ~1.6s. Built with bottom-alignment + padding (no GeometryReader — that caused drift/jitter). HTML preview: https://claude.ai/code/artifact/7d9459af-b56f-4e60-8a1f-cc5d30301707
- **OCR accuracy overhaul + regression net** (`e3fc22a`, `5b6e5c7`, `47129e6`, `0507ac6`): scored amount extraction with tax/savings-line exclusion, cross-confirmation (value restated on the card line), subtotal floor (rejects item-name coincidences like KFC "15 Wicked Wings $10"), French labels (MONTANT DU/TTC), future-date rejection, currency detection (€/£ set the expense currency; bare `$` never overrides), merchant guards (staff-name/URL/business-suffix). **`TallyTests/ReceiptOCRServiceTests.swift`** pins Hendry's, Sushia, Paris, Bunnings, Monos, KFC. **`ocr-regression` skill** (`.claude/skills/ocr-regression/SKILL.md`) enforces: every reported receipt becomes a test.
- **Quick Add / Add Expense fixes** (`9221bcd`, `e368d2e`, `a3bc85a`): amount-field caret fixed (real native field), "What was it?" text now always dark, tap-empty-space dismisses keyboard, and the **merchant-field lag** fixed by persisting one banner across the keypad↔keyboard swap (it was destroying/recreating the AdMob WebView).
- **Recurring filter** (`47129e6`): `isRecurring` now persists on `ExpenseModel`; a "Recurring only" toggle in the filter sheet lets users isolate subscriptions.
- **Home "Rise" gradient**: warm parchment → soft sage-forest, `0.65` opacity, Home tab only, **bottom-most layer** (every UI element sits opaquely on top — do not reintroduce a translucent tab bar over it).
- **Share-to-Tally**: extension writes to the App Group inbox; app auto-opens (`tally://`) into the review flow. Activation rule broadened to an explicit image/PDF predicate so it shows in the screenshot editor's share sheet too (`0507ac6`).
- **Ads**: banner is live (real ID release / test ID debug). SKAdNetwork IDs added (`61e5e95`). **Interstitial deliberately NOT used** (user decision, aligns with brief).
- **Canonical doc**: `Tally/Tally - Everything You Need To Know.md` written and maintained.

---

## 3. Settled decisions (do not relitigate without the user)

FAB opens the entry menu • celebrations/sounds stay • Home tag bar is user-chosen • Reports keeps its tab, Export keeps its button • single-tag rule (standalone / group / group+sub-tag) • Home gradient is the bottom layer • no pre-filled tag "suggestion" chips • `MONETISATION_BRIEF.md` is monetisation law (no usage caps on core tracking) • **no interstitial ads** • shred animation is rotation-only rumble, centred under the FAB.

---

## 4. Open items / next steps (roughly prioritised)

1. **Pro subscription is not purchasable yet.** RevenueCat logs show "offerings empty" every launch because the product **`com.asimplelife.tally.pro.monthly` doesn't exist in App Store Connect**. This is the biggest revenue leak — subscription income is currently $0. Create the app record + subscription in ASC. The user will likely want step-by-step help (they build on the Mac).
2. **TestFlight** for friends/family: archive → upload → external group/public link. Needs a privacy-policy URL and export-compliance answer (consider `ITSAppUsesNonExemptEncryption = NO`). Switch AdMob to **test** ad units for the beta.
3. **CloudKit is disabled** (`TallyApp.cloudKitEnabled = false`). Enable once Developer Program entitlements (iCloud) are configured. Note: adding the `isRecurring` model property relies on SwiftData lightweight migration — if a build ever fails to launch after a schema change, delete+reinstall resets the local store.
4. **SKAdNetwork list** — confirm it's current from Google's official page before App Store submission.
5. **Deferred design debt:** bulk-import `TagLinkPickerSheet` restyle to the shared picker; a written "component constitution" / colour-token reconciliation (colours drifted across redesigns).

---

## 5. OCR regression testing (read before touching the scanner)

OCR is a **paid** feature and it regressed repeatedly — one fix breaking a
previously-working receipt. This is the guardrail. The full workflow lives in
the **`ocr-regression` skill** (`.claude/skills/ocr-regression/SKILL.md`);
the essentials are here so they can't be missed.

### Hard rule

**Never change `ReceiptOCRService.swift` without adding/updating a test case for
the receipt that motivated the change.** Every receipt the user reports — right
or wrong — gets pinned in `TallyTests/ReceiptOCRServiceTests.swift`.

### The corpus (keep this current)

| Receipt   | Trap it guards against                                | Correct |
|-----------|-------------------------------------------------------|---------|
| Hendry's  | tax line "$0.54" misread as "$54"; total restated on card line | $5.89 |
| Sushia    | "Sale Staff: Melissa" as merchant; tax line; tilted photo | $30.90 |
| Paris     | French "MONTANT DU" / TVA / HT; euro currency          | €81.50  |
| Bunnings  | "GST included in the total"; date misread as future (2028) | $38.80 |
| Monos     | "TOTAL SAVINGS"; "Total (GST incl.)" is the real total | $300.00 |
| KFC       | item name "15 Wicked Wings $10" repeats the value 10   | $26.55  |

### Adding a new reported receipt

1. Add `func test<Merchant>_<trap>()` to `ReceiptOCRServiceTests.swift`.
2. Lay the receipt out with the `blk(_:x:y:)` helper — label and right-aligned
   amount as **separate blocks** sharing a `y`. Vision coordinates: `y` is
   normalised and **increases upward** (top ≈ 0.9, bottom ≈ 0.3).
3. Assert the amount via the `amount(_:from:)` helper; assert merchant /
   currency / date too where the receipt exercised those.
4. Add a row to the corpus table above **and** in the skill file.
5. Fix the parser with a **general** heuristic (a rule that explains a class of
   receipts), never a receipt-specific hack. Note the class in a code comment.
6. Re-check the whole corpus by hand before claiming it works.

### Running them (on the Mac — you cannot run them here)

- **⌘U** runs everything (87 tests, ~0.05s). Green banner = no regressions.
- **⌘6** opens the Test navigator to see per-test pass/fail; click a red one to
  jump to the failing assertion ("expected 26.55, got 10.0").
- To run **only** the OCR tests: open `ReceiptOCRServiceTests.swift` and click
  the diamond ◇ beside the class name (or beside a single `func test…`).
- Always end an OCR hand-off with an explicit "pull with ⌥⌘X, run ⌘U, re-scan
  the reported receipt." Never call an OCR fix *verified* until the user
  confirms a green run on the Mac.

---

## 6. How to work here (conventions the user cares about)

- **Push:** commit + `git push tally dev`. End commit messages with `Co-Authored-By: Claude …`. Don't run the pre-push reviewer for `dev` (only `main`/`master`).
- **Multi-step instructions to the user:** flat numbered steps, one action each, no branching; when re-explaining a step, restate all remaining steps; when many errors share a root cause, lead with the cause. (The user works on the Mac and doesn't want to jump between messages.)
- **OCR changes:** see section 5 above and the `ocr-regression` skill. Every reported receipt becomes a test; you cannot run the tests yourself.
- **Verification reality:** you can't build/run/test on Windows. State fixes as "pushed; pull with ⌥⌘X and test on device," never as "verified," unless the user has confirmed on the Mac.
- **New source files** need manual registration in `Tally.xcodeproj/project.pbxproj` (old-style project, no synchronized groups). Same for test files (TallyTests target).
- **Docs precedence:** code wins → `MONETISATION_BRIEF.md` (monetisation) → `Tally - Everything You Need To Know.md` → this handover.

---

## 7. Key files

- App entry `Tally/TallyApp.swift`; state `Tally/AppState/AppState.swift`; models `Tally/Models/`.
- OCR `Tally/Services/ReceiptOCRService.swift` (+ tests `TallyTests/ReceiptOCRServiceTests.swift`).
- Attachments/thumbnails `Tally/Services/AttachmentService.swift`, `ReceiptThumbnailView` in `Tally/Theme/Components.swift`.
- Add/edit expense `Tally/Views/AddExpense/AddExpenseView.swift`; detail + `FullImageView` `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`.
- Home (list, gradient, shred host, filters) `Tally/Views/Home/HomeView.swift`; shred + cards `Tally/Theme/Components.swift`; tab bar `Tally/Views/TallyTabBar.swift`.
- Share extension `TallyShare/` (needs the Xcode target + App Group `group.com.asimplelife.tally` on the Mac).
