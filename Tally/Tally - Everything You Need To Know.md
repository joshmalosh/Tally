# Tally — Everything You Need To Know

*The canonical onboarding document. If you are a person or an AI working on Tally, read this first. It explains what Tally is, why it exists, how it makes money, how it's designed, how the code and repos are organised, and which decisions are settled. Where this document disagrees with the code, the code wins — then update this document.*

Last updated: 2026-07-14

---

## 1. What Tally Is

Tally is a modern, minimal, premium **expense tracking app** for individuals, freelancers, and small-business owners, built natively for iOS (SwiftUI + SwiftData). Users capture spending — snap a receipt, share a screenshot into the app, upload a PDF, paste a list from notes, or type it in — tag it with one tag, and export clean CSV/PDF reports when they need them (tax time, month end, reimbursement).

**Positioning line:** *Expense tracking. That's it.*
**Supporting line:** *Easily add, track and export expenses without the fluff.*

### Why it exists

Every existing tool in this space is overbuilt. Expensify, QuickBooks, Xero — they're accounting suites, reimbursement workflows, enterprise approval chains. The person who just needs to keep receipts organised for their tax return is forced through software designed for a finance department. Tally is the deliberate opposite: a shoebox for receipts that's actually pleasant to use and produces a clean export at the end. The entire product bet is **restraint** — the app wins by doing fewer things better.

### Brand core

- **Mission:** Make expense tracking clean, simple and organised.
- **Belief:** Complexity does not equal value.
- **Philosophy:** Restraint is the advantage.
- **Personality:** Focused, calm, confident, disciplined, modern, efficient. Never playful-for-its-own-sake, edgy, corporate, or flashy.
- **Emotional outcome:** Users should feel organised, calm, in control, productive. The product should feel like a well-made tool, not an app experiment.
- **The single biggest product risk is feature creep.** Every proposed feature must answer: does this make expense tracking simpler, or does it add a dashboard/budget/workflow layer? If the latter, it doesn't belong.

### What Tally is NOT

- NOT accounting software — no double-entry, ledgers, or chart of accounts.
- NOT a reimbursement workflow — no approvals, teams, or roles.
- NOT a finance dashboard — no budgets, forecasts, or goals. (Light reporting exists — see Reports — but it stops at "where did my money go.")
- NOT payroll, invoicing, or bank reconciliation. No bank syncing, ever.
- NOT Android (not currently planned).
- NOT a currency converter — expenses store the currency they were made in; totals are per-currency; no FX math.
- No accounting jargon anywhere: it's a "Tag", never a "Cost Center"; "Export as CSV", never "accountant-ready".

---

## 2. How Tally Makes Money

**Source of truth: `MONETISATION_BRIEF.md` at the repo root.** If anything conflicts with it (including this file), the brief wins. The model was re-affirmed in July 2026 after a stray 15-expenses/month cap was found in the code and removed for violating it.

**Philosophy:** Free is fully usable, ad-supported, with no artificial pain. Pro removes friction and saves time. Free users never feel punished; Pro users get genuine value.

### Tiers

| Capability | Free | Pro ($4.99/mo) |
|---|---|---|
| Manual entry, uploads, tags, editing, bulk delete | Unlimited | Unlimited |
| iCloud sync | Yes | Yes |
| CSV export | 1 per calendar month (resets on the 1st) | Unlimited |
| PDF export | No | Yes |
| OCR receipt scanning | 10 **successful** scans per calendar month | Unlimited |
| Ads | Banner only | None |

There are **no caps on core tracking**. No expense caps, upload caps, or storage caps — storage is the user's own iCloud, so there's no cost pressure to gate it. The OCR quota is not an exception: it meters the *automatic extraction*, never the ability to log an expense. Manual entry always stays open, and the limit sheet offers "Enter manually" beside the upgrade.

**The OCR scan quota (added 2026-07-20, replacing Pro-only field gating):**

- 10 successful scans per calendar month, reset on the 1st.
- **One pool across every entry point** — camera, photo library, file/PDF upload, share extension, bulk import. Importing 5 receipts spends 5 scans.
- **10 usable scans; the 11th is blocked.** Not gate-on-the-10th.
- **Only a scan that extracted an amount is charged.** Amount is the whole reason to scan — if the user still has to type the number, we did nothing for them, and billing for that makes the allowance feel like a scam. Merchant or date alone don't count.
- Free users get the **full** extraction on those 10 (amount, date, merchant, notes). No field-level gating.

Why it changed: merchant/notes were Pro-only while amount/date were free, so free users saw a permanently blank merchant on every scan. That read as a broken scanner rather than a paid tier — constant low-grade friction, little demonstrated value, weak conversion. Metering volume instead lets everyone see the feature work completely and puts the wall in front of the heavy users who actually convert.

### Upgrade prompts

All reactive triggers fire when the user touches a locked thing:

| Trigger | Surface |
|---|---|
| 2nd CSV export in a month | Export-limit sheet (`ProFeatureSheet(limitReached:)`) |
| Tap PDF export (free) | Standard upgrade sheet |
| 11th receipt scan in a month | `ScanLimitSheet` — Upgrade to Pro / Enter manually |
| Home header **Go Pro pill** | Subscription view |
| Settings "Go Pro" row | Subscription view |
| **First open of the day, every 3 days** | Subscription view — proactive. Never in the user's first 3 days; suppressed while another sheet is up so prompts never stack. |
| **3rd, 6th, and 9th expense saved in a month (free)** | **Pro benefits card** — proactive. Max 3 showings/month, never mid-batch, lists only real Pro benefits (unlimited scanning, unlimited CSV, PDF, no ads). |

**Never claim a benefit the free tier already has, or a feature that isn't built.** The paywall previously advertised "Advanced filters" (never a real feature — no code ever gated it, so free users already had it) and "Monthly auto-export" (never built). Both were deleted on 2026-07-20.

**Go Pro pill:** Home header, immediately left of the Settings gear. White pill, brand-green text, `crown.fill` icon. Hidden for Pro.

**Tone rules (non-negotiable):** calm, never aggressive. No countdown timers, urgency language, or red. CTAs are "Upgrade to Pro" (sheets) and "Go Pro" (settings); dismiss is always "Not now".

### Ad placement

Revised 2026-07-20 to the MyFitnessPal model — ads on every full screen, including inline in the list. This **superseded** the earlier "no inline sponsored rows" rule.

- **Banner ads only** (AdMob). Bottom-docked above the tab bar on **Home / Reports / Tags**; bottom of **Add Expense**; below the delete button on **Expense Detail**.
- **Inline in the Home list:** one banner below the pinned tags above the first expense, then one after every 10th expense. The count is **continuous across the whole list**, not per day group — otherwise a run of single-expense days stacks ads back to back.
- Add Expense banner: hides while the keyboard is up so it doesn't fight the number pad.
- **Never**: ads in any sheet/modal (tag picker, export, settings, confirmations) — sheets are opened for one deliberate action and are low-dwell, so they earn little while doing the most damage to how the app feels.
- **No interstitials, no rewarded ads.** Interstitials were reconsidered on 2026-07-20 and rejected again: the core pitch is logging an expense in five seconds, and an interstitial sits directly in that loop. MyFitnessPal, the reference for this ad model, doesn't run them either.
- Note the naming trap: the *Add Expense banner* is a real AdMob ad; `proUpsellCompactBanner` on the same screen is an in-app upsell strip. Two different things.

### Subscription plumbing

- **RevenueCat SDK** over StoreKit 2. Product ID: `com.asimplelife.tally.pro.monthly`. Pro status is `appState.isPro`; on expiry the app reverts to free with all data preserved.
- **Two DEBUG-only Pro overrides exist** — check both before concluding a gate is broken: `RevenueCatConfig.forcePro` (a compile-time constant, currently `true`, which sets `subscriptionStatus = .pro` on launch) and `appState.debugForcePro` (a persisted UserDefaults flag toggled from Settings → Debug). `isPro` is `debugForcePro || subscriptionStatus == .pro`. Both compile out of release builds. Because `forcePro` is `true`, **a DEBUG build is Pro by default** — free-tier behaviour has to be tested with it flipped off.
- ⚠️ Current state: the subscription product does not yet exist in App Store Connect, so RevenueCat offerings come back empty ("Error fetching offerings") and the paywall can't complete a purchase. This must be set up before TestFlight testers can trial Pro.

---

## 3. Information Architecture

Bottom tab bar + centre FAB:

| Surface | Purpose |
|---|---|
| **Home** | Hero spending card (selectable period), search + Filter, horizontal tag-card quick-filter bar (user-chosen tags only), grouped expense list, multi-select for bulk delete/export. Hero collapses on scroll and during search. |
| **Tags** | Manage tags & groups: create, edit, colour, group into folders, toggle which tags appear on the Home bar. Serif "Tags & Groups" heading; Add tag / Add folder buttons. |
| **FAB (+)** | Always creates an expense. Opens the entry-mode picker sheet — it never navigates, edits, imports directly, or exports. |
| **Reports** | Spending trend over 3M/6M/1Y/All, period-over-period % comparison, monthly bars, category/tag breakdown drill-down. Deliberately stops short of budgets/forecasts. |
| **Export** | A tab-bar action (not a browsable destination) opening the global export sheet. Kept as a first-class button deliberately: exporting is the product's deliverable and its biggest Pro conversion surface. |

Other surfaces (sheets/covers): Expense Detail, Settings (subscription, default currency, financial-year start month, about), Onboarding + currency setup, Subscription/paywall, entry flows below.

---

## 4. App Flows

### Golden path (must stay under ~60 seconds for a new user)

FAB → entry picker → capture/type → (review) → Save → celebration → expense in list.

### Entry picker (FAB sheet)

Serif headline "How'd you spend it?" with five modes:
1. **Snap a receipt** (camera) — hero option, "FASTEST" badge.
2. **From library** — photo picker; multiple photos route to multi-receipt review.
3. **Upload file** — PDF/doc, with PDF preview and OCR.
4. **Quick add** — manual entry: hero amount with custom keypad, rotating amount prompt (money questions only: "What's the damage?", "How much was it?", "Where'd it go?", "What did it cost?"), merchant card with autocomplete from history, note card ("WHAT WAS IT?"), tag card, date row, recurring card. Merchant history can auto-apply the tag used last time at that merchant, and shows a playful returning-merchant line ("Another Monos visit… $300 this year and counting").
5. **Import from notes** — paste freeform text (or OCR a photo of notes); a parser extracts description + amount lines, suggests tags from headings, groups the review by tag, supports linking suggested tags to existing ones, a global date + per-row overrides, then bulk-saves. A genuine differentiator; competitors don't offer paste-to-parse.

### Receipt review (photo/file attached)

Uses **the same card language as Quick Add** (this was a deliberate unification — the two flows must read as one app): receipt hero image up top with VIEW RECEIPT / Replace / Remove, then a compact AMOUNT card (never the giant hero amount when a receipt is attached), the shared merchant/note/tag cards, date row, recurring card. OCR fills amount/merchant/date/note with "Detecting…" placeholders and spinners — **all four fields for every tier**, drawing on the monthly scan quota (§2); user always reviews before saving.

### Share-to-Tally (share extension)

Share a screenshot/photo/PDF from anywhere → "Added to Tally" → **Tally auto-opens** (responder-chain `UIApplication.open` of `tally://inbox`; best-effort but working on iOS 26) → single image lands directly on the receipt review page; multiple images land in multi-receipt review; PDFs open the file review flow one at a time. Mechanics: the TallyShare extension writes files into the App Group container (`group.com.asimplelife.tally`) inbox; HomeView consumes it on foreground/launch, never interrupting an open flow.

### Tagging (single-selection rule)

An expense carries **one** selection: a standalone tag, a group alone, or a group + one sub-tag (stored as the child's id; the group is derived via `parentId`). Never multiple tags/groups. The shared tag picker (`SharedTagPickerSheet`) is styled to match the Tags tab (serif "Select tag" heading, Add tag / Add folder buttons, white card rows), tap-to-select-and-dismiss, creation auto-selects. Chips render "Group · Child" for sub-tags and a folder glyph for group-alone. When no tag is selected, the tag card shows a single dashed "+ Add a tag" pill — **never** pre-filled tag chips that look already-selected.

### Export

From the Export button, multi-select, or filtered views. CSV free (1/month) / unlimited Pro; PDF Pro. Selection can be all expenses, a period, tags/groups (group selection matches group-tagged and child-tagged expenses), or a manual selection. Plain copy: "Export as CSV" / "Export as PDF".

### Celebration

On save: coin sound + haptic + landing animation; confetti + monthly toast on milestones. Deliberate, restrained delight — never gamified, and the user explicitly wants these kept.

---

## 5. Data, Privacy, Sync

- **Local persistence:** SwiftData (`ExpenseModel`, `TagModel`). Expenses use soft delete (`deletedAt`). `tagIds` is an array constrained to ≤1 element by the UI (legacy multi-tag data displays until re-tagged; never destroyed silently). Legacy `tagId` string is kept in sync (`resolvedTagIds` handles fallback).
- **Cloud:** designed for CloudKit private database (`iCloud.com.asimplelife.tally`) — **currently disabled** (`TallyApp.cloudKitEnabled = false`) until Apple Developer Program entitlements are configured. When enabled, sync is Apple-managed; no custom sync engine.
- **No proprietary backend.** User data lives on-device and (when enabled) in the user's own iCloud. Messaging: *"Securely stored in your iCloud"* — never generic "cloud sync". This is a trust position, not just an architecture choice: no GDPR data-controller burden for content, no server costs, no breach surface.
- **Attachments:** images/PDFs in the app's documents (Attachments/ + Thumbnails/, 20 MB cap, thumbnails downsampled via ImageIO off the main thread). Share-extension handoff via App Group container.
- **OCR:** on-device Apple Vision. No third-party API, no per-scan cost.
- **Schema changes (verified against the code, 2026-07-17):** there is **no** store-version / delete-and-recreate mechanism, no `VersionedSchema` and no `MigrationPlan` anywhere in the sources. `TallyApp.init` builds the `ModelContainer` directly and calls `fatalError` if it throws. Practical consequences:
  - SwiftData attempts **automatic lightweight migration**. Every `@Model` property carries a default value (CloudKit-friendly), so *adding* a defaulted property migrates cleanly — that's how `isRecurring` was added.
  - Riskier edits (renaming, removing, or changing the type of an existing property) can defeat lightweight migration. If it fails, the container throws → `fatalError` → **the app crashes on launch**; there is no automatic recovery.
  - Recovery for a dev build is **delete the app and reinstall** (local data is discarded). Before doing anything riskier than adding a defaulted property, discuss it with Josh — once CloudKit is enabled and there is real user data, this needs a proper `VersionedSchema` + `MigrationPlan` instead.
  - *(An older store-version-bump mechanism is described in `AGENTS.md`; it no longer exists in the code. Code wins.)*

---

## 6. Design System

### Color

Foundational tokens (Theme/DesignSystem.swift): warm parchment background `#F0EDE6` (docs originally said `#F6F5F3`; the app drifted warmer), white surfaces, forest green primary — deep `#2F402E` for actions/FAB/hero/active states (original brand doc: `#346049`, still in the logo/icon), sage `#8F9E94` for secondary/inactive, border `#DEDAD2`, near-black text `#1C1C1E`, danger `#C84646`. Badge pattern: `#B8D9C0` background with `#2F402E` text.

**Green rules:** green signals action and selection. Amounts are always dark neutral, never green. Do not overuse green — the UI is a neutral canvas with green as the highlight.

**Home gradient ("Rise"):** the one sanctioned large-scale green: a vertical wash from parchment into sage-forest (`#9DB598` end) rendered at **0.65 opacity** over parchment, Home tab only. **It is the bottom-most layer — every UI element including the tab bar and FAB sits opaquely on top of it.** (This layering rule was violated once with a frosted tab bar and explicitly corrected by Josh; do not reintroduce translucency over it.)

### Typography

- UI: system (SF Pro).
- Serif display for headline moments (`Font.dmSerifDisplay(...)`; Fraunces faces are bundled) — entry picker headline, hero amount, merchant field, Tags headings. This serif accent is a deliberate premium note on top of the utilitarian sans.
- Monospace for amounts in lists/exports.
- Uppercase 10pt bold tracked labels ("MERCHANT", "TAG", "DATE") head the white form cards.

### Components & patterns

- **Cards:** white, 16pt continuous radius, 1px `#DEDAD2` stroke, flat (no heavy shadows). The Quick Add card set is the benchmark form language — any expense-editing surface reuses those exact cards.
- **FilterRow** (Theme/Components.swift): the shared selection row (full-row hit target, brand-green press flash) used by the Home filter sheet and tag picker. Built as a real Button — a zero-distance DragGesture breaks ScrollView scrolling; don't regress this.
- **Haptics:** FAB uses `.sensoryFeedback(.impact(weight: .heavy))` on touch-down — instant and reliable. Never create a throwaway `UIImpactFeedbackGenerator` without `prepare()`; the cold Taptic Engine drops or delays the hit. The FAB feel is a stated make-or-break: "this has to feel incredibly satisfying."
- **Motion:** fast and subtle (~150ms fades, springs without cartoon bounce); modals slide up; buttons darken on press rather than scale-popping (FAB's balloon press is the sanctioned exception).
- **Photo viewer:** full-screen receipt view has an X (white glyph on translucent dark circle — visible over white receipts) and drag-down to dismiss. Every screen must have a way back; no dead ends.

### Logo & icon

Wordmark "Tally" with the tally-mark built into the double-l (diagonal thinner than verticals, contained within their bounds). App icon: four vertical bars + one diagonal on parchment. Flat, no gradients/outlines/gloss. Works in green and pure black/white.

---

## 7. Settled Decisions (do not relitigate without Josh)

1. **FAB opens the entry-mode menu.** Not straight into the keypad.
2. **Celebration effects/sounds stay.**
3. **Home tag bar contents are the user's explicit choice** (showOnHome toggles) — never auto-populated by usage.
4. **Reports keeps its tab; Export keeps its button.** Export is the conversion surface and the product's deliverable.
5. **Single-tag rule** (standalone / group / group+sub-tag) as described above.
6. **The Home gradient is the bottom layer.** Everything renders opaquely above it.
7. **No pre-filled tag "suggestion" chips** that read as selections.
8. **MONETISATION_BRIEF.md is monetisation law.** No usage caps on core tracking; the 15/month cap was removed deliberately. Metering the OCR *extraction* is not a core-tracking cap — logging an expense is never blocked.
9. **OCR is metered by volume, not crippled by field.** 10 successful scans/month free, full extraction for everyone. Do not reintroduce field-level gating.
10. **A failed scan is never charged.** Only an extraction that produced an amount consumes quota.
11. **No interstitial ads.** Rejected twice (2026-02-28, 2026-07-20). Inline list banners are the agreed alternative.
12. **The paywall may only list built features the free tier lacks.** "Advanced filters" and "Monthly auto-export" were removed for failing this.
13. **Multi-step instructions to Josh:** flat numbered steps, one action each, no branching; when re-explaining any step, restate all remaining steps; when many errors share one root cause, lead with the cause.

---

## 8. Voice & Copy

Concise, professional, calm, slightly human. Actions as verb phrases ("Export your expenses"). Invitations, not commands ("Go Pro", not "Upgrade Now"). No urgency mechanics ever. Empty states always pair a plain statement with a CTA ("No expenses yet. Tap + to add your first."). iCloud copy: "Securely stored in your iCloud" / "iCloud unavailable — data saved locally." Splash taglines rotate dry one-liners ("Making expenses boring again.", "No spreadsheets were harmed."). Amount prompts are money questions only — "What's it for?" belongs to the note field, not the amount.

---

## 9. Engineering & Repo Conventions

- **Repos:** the working monorepo is `E:\Projects\ASimpleLife` (Windows). The Tally app is mirrored to **github.com/joshmalosh/Tally.git** via the `tally` remote — **always push to `tally` `dev`**; never `origin` (that's the website repo) and never `main` without explicit instruction. Josh builds on his Mac from a clone of Tally.git (Desktop/Tally), pulling `dev` via Xcode (⌥⌘X). `TallyRepo/` inside the monorepo is a separate clone — don't edit it.
- **Project file:** old-style `project.pbxproj` (no filesystem-synchronized groups) — new source files must be registered manually (PBXBuildFile, PBXFileReference, group children, Sources phase).
- **Targets:** `Tally` (app, `com.asimplelife.tally`), `TallyShare` (share extension, `com.asimplelife.tally.share`), `TallyTests`. Both app and extension declare App Group `group.com.asimplelife.tally` in committed `.entitlements` files — the app's entitlement being empty once silently broke the whole share handoff ("client is not entitled" in logs).
- **URL scheme:** `tally://` (Info.plist), used by the share extension handoff.
- **Docs hierarchy:** code > MONETISATION_BRIEF.md (for monetisation) > PROJECT_BRIEF.md > this file's narrative. `AGENTS.md` holds AI-collaborator working rules (minimal scope, match existing style, no doc rewrites unless asked, execute don't delegate). `CHANGELOG.md` follows Keep a Changelog.
- **Key locations:** entry `TallyApp.swift`; state `AppState/AppState.swift` (filters, pro status, export counting, financial-year start); models `Models/`; parser + calculations `Domain/`; services `Services/` (attachments, OCR, sounds, shared inbox, RevenueCat config, sync); UI `Views/` by feature; tokens `Theme/`.

---

## 10. Current Status & Near-Term Roadmap

**Working today:** all five capture flows, share-to-Tally with auto-open, single-tag system + unified picker, exports (CSV/PDF, free-tier limit), Reports with drill-down, Home gradient, celebrations, merchant history, on-device OCR with monthly quota, ads (docked + inline), Go Pro pill, daily upgrade prompt, ProBenefitsCard, bulk import with dates/editing, expense shred animation.

**⚠️ Unverified as of 2026-07-20:** commits `ef30412` and `68032a2` (the monetisation reconciliation and the OCR quota) were written on Windows with **no Swift toolchain — they have never been compiled**. They need a build before being trusted. `TallyTests/MonetisationGatingTests.swift` is a **new file not yet registered in `project.pbxproj`**; until it's added to the TallyTests target, ⌘U passes while running none of it.

**Known gaps / next up:**
- **App Store Connect: create the `com.asimplelife.tally.pro.monthly` subscription.** Highest priority — Pro is literally unpurchasable, RevenueCat offerings come back empty, and subscription revenue is $0. Every monetisation change above is free-tier only and earns nothing until this exists.
- **TestFlight** external beta for friends/family (archive → upload → external group/public link; needs privacy policy URL and export-compliance answer — consider `ITSAppUsesNonExemptEncryption = NO`).
- Switch AdMob to test ad units for beta. Verify the SKAdNetwork ID list is current before submission.
- Enable CloudKit (`cloudKitEnabled = true`) once Developer Program entitlements are in place.
- OCR accuracy: an ongoing accumulating loop — see §5 of `SESSION_HANDOVER.md` and the `ocr-regression` skill. Corpus is at 7 receipts.
- Deferred design debt: bulk import's `TagLinkPickerSheet` restyle to the shared picker language; a written component constitution / design-token reconciliation (colors drifted screen-by-screen across redesigns).

---

*Maintenance: update this file when a settled decision changes, a monetisation rule moves, or a major surface ships. Keep it truthful to the code — this document orients; the code decides.*
