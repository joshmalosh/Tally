# Tally — Session Handover

*A snapshot of the current state of work for whoever (human or AI) picks this up next. This file only covers where things stand right now.*

Handover written: 2026-07-17 · last updated: 2026-07-20

## Read these first (exact paths)

The canonical doc's filename **contains spaces** — quote it, don't glob it.
A previous session wasted two failed searches on this.

```
Tally/Tally - Everything You Need To Know.md      # full product/design/monetisation context
MONETISATION_BRIEF.md                             # monetisation law (root of repo)
.claude/skills/ocr-regression/SKILL.md            # OCR guardrail workflow
TallyTests/ReceiptOCRServiceTests.swift           # the receipt regression corpus
```

To open the canonical doc, read it by exact path (quoted) rather than a glob:
`Read "Tally/Tally - Everything You Need To Know.md"`.

**Precedence when docs disagree: the code wins**, then `MONETISATION_BRIEF.md`
for monetisation, then the canonical doc, then this handover. If you find a
contradiction, verify against the code and fix the doc in the same session —
don't leave it for later.

---

## 1. Snapshot

- **Repo / branch:** working dir `E:\Projects\ASimpleLife` (Windows). App mirrors to **github.com/joshmalosh/Tally.git** via the `tally` remote. **Always push to `tally` `dev`.** Never `origin` (that's the website) and never `main`/`master` without explicit instruction.
- **Latest commit on `tally/dev`:** see `git log -1` — this line goes stale fast. As of the last update local `dev` was at `68032a2` (OCR scan quota). Local `dev` tracks `tally/dev`; working tree clean apart from intentionally-untracked dirs (`.claude/` except the committed skill, `TallyRepo/`, `Website/`, `assets/`, ChatGPT brief).
- ⚠️ **`ef30412` and `68032a2` may still be unpushed and are definitely uncompiled.** Check `git status` for "ahead of tally/dev". See §2.
- **Build/run happens on the user's Mac** (Xcode). This Windows box has **no Swift/Xcode toolchain** — you cannot compile, run, or execute tests here. The user pulls `dev` in Xcode via **⌥⌘X**, runs, and reports back (often with screenshots and device logs). **Never claim code is verified from this box.** Say what you changed and what still needs a build.
- **Test suite:** `TallyTests` runs on the Mac with **⌘U** (87 tests green as of the last full run). Two files added since: `ReceiptOCRServiceTests` grew to 11 OCR cases, and **`MonetisationGatingTests.swift` is new and not yet in `project.pbxproj`** — it must be added to the TallyTests target or ⌘U passes while running none of it.
- **A DEBUG build is Pro by default** (`RevenueCatConfig.forcePro = true`). To see anything free-tier — ads, the Go Pro pill, the scan quota, the CSV limit — that constant must be flipped to `false`. There's also a persisted `Settings → Debug → Force Pro` toggle (`appState.debugForcePro`). `isPro` is the OR of both. If a gate "doesn't work", check these two first.

---

## 2. What this session delivered (newest first)

- **⚠️ Monetisation reconciliation + OCR scan quota** (`ef30412`, `68032a2`) — **written on Windows, never compiled.** An audit of the code against `MONETISATION_BRIEF.md` found six divergences; all six are now resolved in code and docs:
  1. **CSV export was incoherent.** `freeTierCSVExportsPerMonth` was 2, but four of the six export paths ignored the counter and hard-gated on `isPro`, so the same user got 2 free exports or 0 depending on which button they pressed. Now **1 everywhere** via `canExportCSV`. The two paths that honoured the counter used to fail *silently* at the cap — they now show the limit sheet.
  2. **OCR: field gating → volume quota.** Merchant/notes were Pro-only while amount/date were free, so free users saw a permanently blank merchant on every scan — reads as a broken scanner, not a paid tier. Now **10 successful scans/month**, full extraction for everyone. One pool across camera, library, PDF, share extension, and bulk import. **Only scans that extracted an amount are charged.** New `ScanLimitSheet` offers Upgrade / Enter manually; logging an expense is never blocked.
  3. **"Advanced filters" deleted** — no code ever gated it, so free users already had it. It was a false paywall claim.
  4. **"Monthly auto-export" deleted** from code, docs, and paywall — never built; user judged it overcomplicated the app.
  5. **Ads extended to the MyFitnessPal model**: every full screen incl. Expense Detail, plus inline in the Home list (below the pinned tags, then after every 10th expense, counted continuously across the list). This **supersedes** the old "no inline sponsored rows" rule.
  6. **Interstitials reconsidered and rejected again** — they'd sit inside the five-second logging loop. MFP doesn't run them either.
  Also added: **Go Pro pill** in the Home header (white pill, green text, crown, left of the gear) and a **daily upgrade prompt** (first open, every 3 days, 3-day grace, suppressed while another sheet is up). New `TallyTests/MonetisationGatingTests.swift` pins all the numbers — **not yet in the Xcode target.**
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

FAB opens the entry menu • celebrations/sounds stay • Home tag bar is user-chosen • Reports keeps its tab, Export keeps its button • single-tag rule (standalone / group / group+sub-tag) • Home gradient is the bottom layer • no pre-filled tag "suggestion" chips • `MONETISATION_BRIEF.md` is monetisation law (no usage caps on core tracking) • **no interstitial ads** (rejected twice) • shred animation is rotation-only rumble, centred under the FAB.

Added 2026-07-20: **OCR is metered by volume, never crippled by field** (10 successful scans/month free; don't reintroduce field gating) • **a failed scan is never charged** (only an extracted amount consumes quota) • **the paywall may only list built features the free tier lacks** • **CSV is 1/month, enforced identically on every path** • **ads on every full screen + inline in the list, but never in sheets**.

---

## 4. Open items / next steps (roughly prioritised)

0. **Build and verify `ef30412` + `68032a2` before anything else.** They were written without a compiler. On the Mac: ⌥⌘X → drag `TallyTests/MonetisationGatingTests.swift` into the TallyTests target → ⌘U (expect 11 OCR + 9 gating tests) → set `RevenueCatConfig.forcePro = false` → Run and check the Go Pro pill, inline ads at the right list positions, the CSV limit sheet on a second export, and the scan gate on the 11th scan.
1. **Pro subscription is not purchasable yet.** RevenueCat logs show "offerings empty" every launch because the product **`com.asimplelife.tally.pro.monthly` doesn't exist in App Store Connect**. This is the biggest revenue leak — subscription income is currently $0. Create the app record + subscription in ASC. The user will likely want step-by-step help (they build on the Mac).
2. **TestFlight** for friends/family: archive → upload → external group/public link. Needs a privacy-policy URL and export-compliance answer (consider `ITSAppUsesNonExemptEncryption = NO`). Switch AdMob to **test** ad units for the beta.
3. **CloudKit is disabled** (`TallyApp.cloudKitEnabled = false`). Enable once Developer Program entitlements (iCloud) are configured. **Schema note (verified in code):** there is no store-version/delete-store mechanism — SwiftData does automatic lightweight migration, which is why adding the defaulted `isRecurring` property was safe. A failed migration throws → `fatalError` → crash on launch; recovery is delete + reinstall. Anything riskier than adding a defaulted property needs a real `VersionedSchema`/`MigrationPlan` before CloudKit is on. Full detail in the canonical doc §5.
4. **SKAdNetwork list** — confirm it's current from Google's official page before App Store submission.
5. **Deferred design debt:** bulk-import `TagLinkPickerSheet` restyle to the shared picker; a written "component constitution" / colour-token reconciliation (colours drifted across redesigns).

---

## 5. OCR regression testing (read before touching the scanner)

OCR is **metered** — 10 successful scans a month on free, unlimited on Pro, and
a scan only counts if it extracted an **amount**. Accuracy is therefore directly
monetised in both directions: a wrong amount fails the user, and an empty one
silently refunds their scan. It has regressed repeatedly — one fix breaking a
previously-working receipt. This is the guardrail. The full workflow lives in
the **`ocr-regression` skill** (`.claude/skills/ocr-regression/SKILL.md`);
the essentials are here so they can't be missed.

**Merchant extraction is no longer Pro-gated.** If a user reports a blank
merchant, it's a parser bug now — it used to be the paywall. (That exact
confusion cost a session: the answer "it's the Pro gate" was correct for the
code at the time and completely useless to the user.)

### The loop (this is an ongoing, accumulating process)

Tally's OCR is **not** "finished". It improves by absorbing real-world failures
one at a time, and the corpus below is the accumulated memory of that:

1. **The user scans a receipt and it comes out wrong** — they send a photo of
   the receipt plus a screenshot of what Tally produced.
2. **Diagnose from the pair**: work out which line the parser actually latched
   onto and why (e.g. a savings figure that appears twice, a tax line, a staff
   name, a foreign label, an item name containing a `$`).
3. **Pin it as a test** in `ReceiptOCRServiceTests.swift` *before* fixing, so
   the failure is captured permanently.
4. **Fix with a general heuristic** that explains a whole class of receipts, not
   a hack for this one — and re-check the existing corpus by hand so the new
   rule doesn't break an older receipt.
5. **Add a row to the corpus table** here and in the skill file.
6. **The user runs ⌘U on the Mac** and re-scans the receipt to confirm.

Every pass makes the scanner more versatile and can never make it less so —
that's the whole point of the corpus. Expect this loop to keep running for a
long time; treat each new failing receipt as normal, not as a setback.

### Hard rule

**Never change `ReceiptOCRService.swift` without adding/updating a test case for
the receipt that motivated the change.** Every receipt the user reports — right
or wrong — gets pinned in `TallyTests/ReceiptOCRServiceTests.swift`.

### The corpus (keep this current — add a row per reported receipt)

| Receipt     | Trap it guards against                                | Correct |
|-------------|-------------------------------------------------------|---------|
| Hendry's    | tax line "$0.54" misread as "$54"; total restated on card line | $5.89 |
| Sushia      | "Sale Staff: Melissa" as merchant; tax line; tilted photo | $30.90 |
| Paris       | French "MONTANT DU" / TVA / HT; euro currency          | €81.50  |
| Bunnings    | "GST included in the total"; date misread as future (2028) | $38.80 |
| Monos       | "TOTAL SAVINGS"; "Total (GST incl.)" is the real total | $300.00 |
| KFC         | item name "15 Wicked Wings $10" repeats the value 10   | $26.55  |
| Woolworths  | savings ("You saved"/"Specials") + per-kg rate lines ("@ $33.00/kg") outrank the small-print TOTAL; label and amount are separate blocks | $49.49 |
| Woolworths (header) | large wordmark with three small lines beneath; on a skewed photo they drift into its band and the address line "parses an amount", so the merchant was discarded and extraction returned nil | merchant `Woolworths` |

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
- **When asked what a feature does, read the code — do not answer from the brief or from memory.** On 2026-07-20 the user called out repeated contradictory answers about the free/Pro split. The cause wasn't forgetfulness: the code genuinely disagreed with itself (CSV meant 2, 1, or 0 depending on the call site) and with the brief (four more divergences). Grep every `isPro` / quota call site and reconcile before answering. Answering confidently from one call site is how this happened.
- **Naming trap:** on Add Expense, the "banner" is a real AdMob ad; `proUpsellCompactBanner` is an in-app upsell strip. Say which one you mean.

---

## 7. Key files

- App entry `Tally/TallyApp.swift`; models `Tally/Models/`.
- **`Tally/AppState/AppState.swift` is where every free-tier limit lives** — `canExportCSV` / `recordCSVExport`, `canUseOCR` / `recordOCRScan` / `ocrScansRemaining`, `shouldShowUpgradePrompt`, `isPro` (+ the DEBUG `debugForcePro`). Change a limit here, not at a call site. Pinned by `TallyTests/MonetisationGatingTests.swift`.
- Pro/limit sheets: `ProFeatureSheet` and `ScanLimitSheet`, both at the bottom of `Tally/Views/Export/ExportView.swift`. Paywall `Tally/Views/Settings/SubscriptionView.swift`. Ad plumbing `Tally/Services/AdManager.swift`, `RevenueCatConfig.forcePro`.
- OCR `Tally/Services/ReceiptOCRService.swift` (+ tests `TallyTests/ReceiptOCRServiceTests.swift`).
- Attachments/thumbnails `Tally/Services/AttachmentService.swift`, `ReceiptThumbnailView` in `Tally/Theme/Components.swift`.
- Add/edit expense `Tally/Views/AddExpense/AddExpenseView.swift`; detail + `FullImageView` `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`.
- Home (list, gradient, shred host, filters) `Tally/Views/Home/HomeView.swift`; shred + cards `Tally/Theme/Components.swift`; tab bar `Tally/Views/TallyTabBar.swift`.
- Share extension `TallyShare/` (needs the Xcode target + App Group `group.com.asimplelife.tally` on the Mac).
