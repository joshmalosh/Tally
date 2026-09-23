# Tally — Project & Monetisation Brief

*The single living project doc. Product spec first, then the monetisation model,
then engineering and session state at the end. The Monetisation part is the
source of truth for anything money-related. Keep this current in the same turn
as the work — a stale brief is a bug. `CLAUDE.md` holds the rules for working
with Josh; everything else about Tally lives here.*

## 0) One-Paragraph Summary

Tally is a modern, minimal, premium expense tracking app for individuals and small businesses. Users snap receipts, upload invoices, log manual expenses, tag them with unlimited custom tags, and export clean CSV and PDF files. It runs on iOS (SwiftUI) with data stored entirely in the user's iCloud via CloudKit — no proprietary backend, no server-side user data. Free users get unlimited expenses, unlimited uploads, unlimited tags, 10 receipt scans and 1 CSV export per month, with banner ads; Pro ($4.99/month) removes ads and unlocks unlimited receipt scanning, unlimited CSV exports, and PDF export. It is NOT accounting software, NOT a reimbursement workflow, and NOT a finance dashboard — it is a capture + tag + export system.

## 1) Product Goals and Non-Goals

### Goals
1. **Speed** — New user can add an expense in under 60 seconds.
2. **Simplicity** — Radically simpler than Expensify or any enterprise tool.
3. **Seamless sync** — Expenses and receipts sync across devices via iCloud.
4. **Sustainable monetization** — Free tier is genuinely usable; Pro removes friction completely.
5. **Professional output** — Exports are clean, structured, and ready to use.

### Non-Goals
- NOT accounting software (no double-entry, no ledgers, no chart of accounts).
- NOT a reimbursement workflow (no approvals, no team hierarchies).
- NOT a finance dashboard (no budgets, no charts, no analytics, no forecasting).
- NOT payroll, invoicing, or bank reconciliation.
- NOT Android (not now).
- NOT multi-currency conversion (store currency per expense, no FX logic).

### Strategic Note
The biggest risk to Tally is feature creep. Do not add dashboards, charts, budgeting, payroll, or bank syncing. Tally wins by staying disciplined.

## 2) Brand Core

### Positioning
**Primary line:** Expense tracking. That's it.
**Supporting line:** Easily add, track and export expenses without the fluff.

### Brand Mission
Make expense tracking clean, simple and organised.

### Brand Belief
Complexity does not equal value.

### Product Philosophy
Restraint is the advantage. The app does fewer things better.

### Brand Personality

Tally is:
- Focused
- Calm
- Confident
- Disciplined
- Modern
- Efficient

Tally is not:
- Playful
- Edgy
- Corporate
- Overly friendly
- Flashy

Tone is concise and professional.

### Emotional Outcome
Users should feel: organised, calm, in control, productive.
The product should feel like a tool, not an app experiment.

## 3) Core Concepts / Modes / Behavioral Rules

### Core Features
- Add expense manually
- Upload receipt or invoice
- Add custom tags (unlimited)
- Export as CSV
- Export as PDF (Pro)
- OCR auto-fill from receipts (free: 10 successful scans/month; Pro: unlimited)
- Simple search
- Filtering by tag, group, and recurring (all tiers)

The Free vs Pro split, tier comparison table, ad placement, and upgrade-prompt
behavior all live in the **Monetisation** part below. Pro removes friction; it
does not unlock complexity.

## 4) Navigation Structure

### iOS
- **Home** — Monthly total, filter chips, expense list, FAB (+), export button.
- **Add Expense** — Sheet/modal. Three entry points: Camera, Upload, Quick Add.
- **Expense Detail** — View/edit an existing expense.
- **Export** — Date range picker, format selection, generate.
- **Settings** — Account, subscription, tags management, about.

### Web (Deprioritised)
Web app is deprioritised in favour of the iCloud-native iOS experience. If pursued later, it would require CloudKit JS and Apple ID sign-in on web. Not in scope for Phase 1 or Phase 2.

### Navigation Rules
- Every screen has a way back or dismiss.
- Sheet dismissal cleans up form state.
- No dead ends.

## 5) Data Model

### Entities

**Expense**
- id, amount_cents (integer), currency, date, description, merchant
- tag_id, notes, attachment_data, source (camera/upload/manual)
- created_at, updated_at, deleted_at (soft delete)

**Tag**
- id, name, color_id, sort_order, is_default (bool)

**ExportRecord** (local tracking only)
- id, exported_at, format (csv/pdf)

### Relationships
- Expense → one Tag (optional)
- Expense → optionally one attachment (stored as data in iCloud)

### Derived vs Persisted
- **Persisted**: All entities above. Expenses are the source of truth.
- **Derived**: Monthly totals, tag breakdowns, export counts (computed from records).
- Never store monthly totals separately.

### Data Storage — iCloud Only

All user data is stored in the user's iCloud via CloudKit:
- SwiftData models sync automatically via CloudKit container.
- Attachments (receipt images) stored as CKAsset in CloudKit.
- No proprietary server. No S3. No external object storage.
- Tally is NOT a data custodian — the user owns their data.

**Privacy and compliance benefits:**
- No GDPR data controller obligations for user content.
- No server-side storage cost scaling.
- No security surface for user data.
- Perceived as safer by privacy-conscious users.

**Messaging:** "Securely stored in your iCloud" (not "cloud sync").

### iCloud Unavailable Handling
- If iCloud is unavailable: data persists locally in SwiftData (SQLite).
- Show subtle indicator: "iCloud unavailable — data saved locally."
- Sync resumes automatically when iCloud reconnects.
- App is fully functional offline.

## 6) Key Calculations / Business Logic

### Monthly Total
```
sum(expenses.amount_cents) WHERE user_id = X AND date BETWEEN month_start AND month_end AND deleted_at IS NULL
```
Display in user's default currency. No FX conversion.

### CSV Export Count (Free Tier Gate)
```
count(ExportRecord) WHERE format = csv AND exported_at >= current_month_start
```
Free users: 1 CSV export per calendar month. Counter resets on the 1st.
Tracked locally via ExportRecord entity.

### Export Generation
- CSV: All matching expenses, sorted by date ascending.
- PDF (Pro): Formatted expense report with summary.

### Sync (iCloud / CloudKit)
- CloudKit handles conflict resolution automatically.
- SwiftData + CloudKit integration manages merge policies.
- Soft deletes propagate via CloudKit sync.

## 7) Visual Identity

### Design Principles
- White or soft neutral backgrounds
- One primary green
- Strong typography
- Minimal visual noise
- No gradients
- No shadows
- No decorative UI
- Use white space intentionally
- Every screen must feel breathable

The brand should feel engineered, not illustrated.

### Color System

| Token | Hex | Usage |
|---|---|---|
| `bg` | #F6F5F3 | Main background. Warm neutral canvas. |
| `surface` | #FFFFFF | Card backgrounds, elevated content. |
| `brandPrimary` | #346049 | Primary green. Actions, FAB, primary buttons, logo, icon. |
| `brandAccent` | #4A7D62 | Mid green. Active states, focused fields. |
| `brandTint` | #E8EFE9 | Very subtle green wash. Selected states, active chips. |
| `brandPressed` | #2A4E3B | Pressed/hover darkened state. |
| `border` | #E3E8E5 | Borders, dividers. |
| `text` | #111417 | Primary text. |
| `text2` | #6B7280 | Secondary text. |
| `textMuted` | #9CA3AF | Meta text, timestamps. |
| `danger` | #C84646 | Destructive actions, errors. |
| `success` | #2E7D5B | Positive feedback. |

### Green Usage Rules
- Green is for: primary actions, icons, active states.
- Green is NOT for: large backgrounds, headers, card fills, amounts.
- Do not overuse green. UI is mostly neutral canvas with green as highlight.
- Amount text is always dark charcoal, never green.

### Typography
- Primary UI font: Inter (Web), SF Pro (iOS).
- Weights: Regular, Medium, Semibold. Avoid heavy bold for large blocks.
- Monospace for amounts: JetBrains Mono (Web), SF Mono (iOS).
- Use hierarchy through spacing, not decoration.

### Motion
- Hover fade: 150ms ease.
- Button press: slight darken, no scale bounce.
- Modal: slide up, fade in.
- Keep it adult.

### UI Principles
- Minimal iconography.
- Rounded corners but subtle.
- No gradients. No drop shadows. No glossy effects. Flat only.
- Every screen must feel breathable.
- Do not overuse green.

### Logo System
- Wordmark: "Tally" with integrated tally mark in the double-l characters.
- Diagonal stroke thinner than vertical strokes.
- Diagonal must remain inside vertical bounds.
- Vertical spacing must not change.
- Green: #346049. Must also work in black and white.
- No outline effects.

### App Icon
- Canvas: 1024 x 1024.
- Background: #F6F5F3.
- Tally mark color: #346049.
- Four evenly spaced vertical bars, one diagonal bar crossing.
- Spacing between vertical bars must remain consistent.
- Minimal negative space but not touching edges.
- Corner radius consistent with iOS standards.
- Flat. Clean. Balanced.

## 8) State Management Approach

### iOS
- `@Observable` app state object injected via environment.
- Local persistence: SwiftData (SQLite under the hood).
- Cloud sync: SwiftData + CloudKit container (automatic).
- Subscription status: StoreKit 2 (local receipt validation).

### Core Patterns
- Single source of truth: expenses in SwiftData, synced via CloudKit.
- Derived state computed on read (monthly totals, export counts).
- Optimistic writes: save locally first, CloudKit syncs async.
- No custom sync engine — Apple handles it.

## 9) Mode-Specific Behavior Mapping

| Action | Free Behavior | Pro Behavior |
|---|---|---|
| Add expense (manual) | Allowed, unlimited | Allowed, unlimited |
| Add expense (camera/upload) | Allowed, unlimited | Allowed, unlimited |
| View expense list | Full access + banner ad | Full access, no ad |
| Edit expense | Full access | Full access |
| Delete expense | Allowed | Allowed |
| Bulk delete | Allowed | Allowed |
| CSV export | 1 per calendar month | Unlimited |
| CSV export (at limit) | Show export limit sheet | N/A |
| PDF export | Blocked, show upsell | Allowed |
| OCR scanning (at limit) | Show scan limit sheet; manual entry still allowed | Unlimited |
| iCloud sync | Yes | Yes |
| Manage tags | Full access, unlimited | Full access, unlimited |
| Settings | Shows "Go Pro" option | Shows subscription management |

## 10) Edge Cases to Handle Explicitly

| Case | Handling |
|---|---|
| Zero expenses | Designed empty state: "No expenses yet. Tap + to add your first." |
| Single expense | Layout works correctly (not just optimized for many). |
| Long merchant/description | Truncate with ellipsis. |
| Large amounts (999,999.99) | Formatted correctly, no overflow. |
| Amount of 0 | Allowed (e.g., free item receipt). |
| Missing attachment | Show placeholder, never crash. |
| CSV export at limit (free) | Show export limit sheet with calm upsell. |
| Offline / iCloud unavailable | Save locally in SwiftData. Show "iCloud unavailable — data saved locally." Sync resumes automatically. |
| Sync conflict | CloudKit handles merge. No user-facing conflict UI for MVP. |
| Expired subscription | Revert to free tier behavior. Existing data preserved. |
| 1000+ expenses export | Must complete without crash. Progress indicator. |
| Deleted tag on expense | Show "Untagged" fallback. |
| Currency with no decimals (JPY) | Format correctly per locale. |
| PDF attachment | Store original, generate preview thumbnail if possible. |
| 20MB+ file upload | Reject with clear message: "File too large (max 20MB)." |

## 11) Copy, Disclaimers, and Tone

### Voice
Concise, professional, calm. Slightly human, never corporate.

### Key Copy Strings
- Onboarding 1: "Track expenses in seconds."
- Onboarding 2: "Export anytime."
- Onboarding 3: "Sign in or Continue without account"
- Empty home: "No expenses yet. Tap + to add your first."
- Export limit: "Free plan includes 1 CSV export per month. Upgrade to Pro for unlimited exports and PDF reports."
- Export CTA: "Export your expenses"
- Pro upsell: "Go Pro"
- iCloud sync: "Securely stored in your iCloud"
- iCloud unavailable: "iCloud unavailable — data saved locally."

### Tone Rules
- Actions as verbs: "Export your expenses", not "Export".
- Invitations, not commands: "Go Pro", not "Upgrade Now".
- No accounting jargon. "Tag", not "Chart of Account" or "Cost Center".
- No countdown timers, no urgency tactics, no "limited time" language.

## 12) Acceptance Criteria

- [ ] New user can add an expense in under 60 seconds.
- [ ] Free tier shows banner ads but is fully functional for manual entry + 1 CSV export/month.
- [ ] Pro tier removes ads immediately upon subscription.
- [ ] Expenses and receipts sync across devices via iCloud.
- [ ] App is fully functional when iCloud is unavailable (local persistence).
- [ ] Offline expenses save locally and sync when iCloud reconnects.
- [ ] Tags are editable with system defaults preloaded.
- [ ] Unlimited custom tags supported.
- [ ] Attachment thumbnails load lazily.
- [ ] Export of 1000 items completes without crash.
- [ ] No accounting terminology exposed anywhere.
- [ ] Every screen has back/dismiss navigation.
- [ ] Every empty state has a CTA.

## 13) Implementation Plan

### Phase 1 — Foundation + Core Flow — DONE
Built and tested: SwiftUI + SwiftData, design system, data model, expense CRUD,
tag management, monthly totals, core screens (Home, Add Expense, Expense Detail,
Settings), CSV export (1/month free, unlimited Pro), AdMob banners, and
subscriptions on StoreKit 2 (via RevenueCat).

One launch-blocker sits outside the feature work and is tracked in **Open items**
below: the Pro subscription product does not yet exist in App Store Connect, so
Pro is not purchasable. (CloudKit sync is now enabled; verify iCloud entitlements
on device.)

### Phase 2 — Feature Depth
1. Camera capture + receipt upload flow. — DONE
2. PDF export (Pro). — DONE
3. OCR auto-fill via Vision framework (metered on free). — DONE
4. Usage analytics. — Not started.

### Phase 3 — Growth (future)
1. Direct accounting software export (Xero, QuickBooks).
2. Multi-user / family sharing support.
3. Web app via CloudKit JS (if demand warrants).

---

## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| iOS | SwiftUI + SwiftData | Native performance, modern declarative UI, built-in persistence. |
| Cloud sync | CloudKit (via SwiftData) | Zero-cost sync, Apple-managed, user-owned data. |
| Attachment storage | CloudKit CKAsset | Receipts stored in user's iCloud. No server storage. |
| Auth | Apple ID (implicit via iCloud) | No custom auth needed. iCloud identity is the user identity. |
| Subscriptions | StoreKit 2 | Apple requirement for in-app purchases. Local receipt validation. |
| Ads | Google AdMob | Mature SDK, Apple-compliant. Banner only. |
| OCR | Apple Vision framework | On-device text recognition. No API cost. |

### What was removed
| Layer | Removed | Reason |
|---|---|---|
| Backend | Node.js + Express + PostgreSQL | No proprietary server needed. iCloud handles storage + sync. |
| Object storage | AWS S3 / Cloudflare R2 | Receipts stored as CKAsset in user's iCloud. |
| Web app | Next.js + React | Deprioritised. iCloud-native iOS is the focus. |
| Web subscriptions | Stripe | No web app in scope. |
| Custom auth | JWT + OAuth | iCloud identity replaces custom auth. |
| Hosting | Vercel + Railway | No server infrastructure to host. |

# Monetisation

This part is the source of truth for Tally's monetisation model. Where it conflicts with the product sections above, this part wins.

---

## Philosophy

**Free:** Fully usable. No artificial pain. Ad-supported.

**Pro:** Time-saving. Automation. Cleaner experience. No ads.

This is sustainable, clean monetisation. Free users never feel punished. Pro users get genuine value.

---

## Tier Comparison

| Capability | Free | Pro ($4.99/mo) |
|---|---|---|
| Manual expense entry | Unlimited | Unlimited |
| Receipt uploads | Unlimited | Unlimited |
| Custom tags | Unlimited | Unlimited |
| View / edit / delete expenses | Unlimited | Unlimited |
| Bulk delete | Yes | Yes |
| iCloud sync | Yes | Yes |
| CSV export | 1 per calendar month | Unlimited |
| PDF export | No | Yes |
| Import from statement (PDF) | No | Yes |
| OCR receipt scanning | 10 successful scans per calendar month | Unlimited |
| Ads | Banner ads | None |

---

## Export Rules

### CSV (Free: 1/month, Pro: Unlimited)

- Free users get 1 CSV export per calendar month. Counter resets on the 1st.
- If a free user attempts a second export in the same month, show a bottom sheet:

```
Title: Export limit reached

Body: Free plan includes 1 CSV export per month.
      Upgrade to Pro for unlimited exports and PDF reports.

Buttons:
  [Upgrade to Pro]
  [Not now]
```

- No aggressive styling. No red. Calm tone.
- Pro users export unlimited CSV with no friction.

### PDF (Pro only)

- PDF export available only for Pro users.
- Free users who attempt PDF see the standard upgrade sheet.

### Export copy

- Use "Export as CSV" and "Export as PDF".
- Do NOT use "Export to Accountant", "accountant-ready", or any accountant framing.
- Keep tone simple and professional.

---

## Ad Placement Rules

### Where ads appear

Free users see ads on every full screen. Revised 2026-07-20 to the MyFitnessPal
model, which replaced the earlier "no inline sponsored rows" rule.

| Location | Ad Type | Notes |
|---|---|---|
| Home | Banner beneath the pinned tags | Fixed in the header, above the list. Moved here 2026-08-25 — the old bottom-docked banner sat under the FAB (+) overhang and covered the button no matter the padding. |
| Home expense list | Inline banner | After every 10th expense, counted continuously across the list (not per day group). |
| Reports | Inline banner | `InlineUpgradeAd` above the content. |
| Tags | None yet | The shared bottom-docked banner (which covered Home/Reports/Tags) was removed 2026-08-25 when the Home banner moved up. The Tags tab has no ad slot as a result — see Open items. |
| Add Expense screen | Banner (bottom) | Below Notes, above safe area. See keyboard rules below. |
| Expense Detail | Banner | Below the delete button |

### Where ads do NOT appear

- Tag bottom sheet
- Export bottom sheet
- Settings screen
- Confirmation states
- Any modal/sheet overlay

Sheets are deliberately excluded: they're opened for one deliberate action and
are low-dwell, so they earn very little while doing the most damage to how the
app feels.

### Ad types

- **Banner ads only.** Bottom-docked or inline in the expense list.
- **No interstitial ads.** Considered and rejected 2026-07-20 — the core pitch
  is logging an expense in five seconds, and an interstitial in that loop
  attacks the one thing that makes Tally worth using. MyFitnessPal, the
  reference for this model, does not run them either.
- **No rewarded ads.**

### Inline list ad cadence

The "every 10th expense" count is **continuous across the whole list**, not per
day group — otherwise a run of single-expense days stacks ads back to back.

### Add Expense banner behavior

**Position:** Below Notes field, above safe area. Does not push Save off-screen.

**Keyboard rules:**
- When user taps into Amount, Notes, or any text field: hide banner smoothly.
- When keyboard dismisses: fade banner back in.
- Banner does NOT reflow content while typing.
- Banner does NOT animate in/out aggressively.

**First impression rule:**
- Do not show banner on Add Expense until user has added at least 3 expenses total.
- This prevents first interactions from feeling monetised.
- Home screen banner appears from the start (it's less intrusive in a list context).

---

## OCR Receipt Scanning (metered, not gated)

**Free: 10 successful scans per calendar month. Pro: unlimited.**

Superseded the old "OCR is Pro-only" model on 2026-07-20. Blanking individual
fields for free users read as a broken scanner rather than a paid tier: constant
low-grade friction, almost no demonstrated value, weak conversion. A volume
quota instead lets every user experience the feature working completely, and
puts the wall in front of exactly the heavy users who convert.

### Quota rules

- **10 scans per calendar month**, reset on the 1st.
- **All entry points count against the same pool**: camera capture, photo
  library, file/PDF upload, the share extension, and bulk import (importing 5
  receipts consumes 5 scans).
- **10 usable scans; the 11th is blocked.** Not gate-on-the-10th.
- **Only successful scans are charged.** A scan is successful if it extracted
  an **amount**. Amount is the whole reason to scan — if the user still has to
  open the keypad and type the number, we did nothing for them, and charging
  for it would make the allowance feel like a scam. Merchant or date alone do
  not consume a scan.
- Free users get the **full** extraction on those 10 — amount, date, merchant,
  notes. No field-level gating.

### Limit reached

```
Title: Scan limit reached

Body: Free plan includes 10 receipt scans per month.
      You can still add this expense manually.
      Upgrade to Pro for unlimited scanning.

Buttons:
  [Upgrade to Pro]
  [Enter manually]
```

Manual entry must remain fully available — the gate never blocks logging an
expense, only the automatic extraction.

### Implementation

- **On-device only.** Apple Vision (`VNRecognizeTextRequest`). No third-party
  API, no cloud dependency, no per-scan cost.
- Flow: capture receipt, Vision extracts text, parse for amount + merchant,
  auto-fill form fields.
- User always reviews and confirms before saving.

---

## Upgrade Prompts

### Trigger points

| Trigger | Context |
|---|---|
| Second CSV export in a month | Export limit bottom sheet |
| Tap PDF export (free user) | Standard upgrade sheet |
| 11th receipt scan in a month | Scan limit sheet (see OCR section) |
| Home header "Go Pro" pill | Subscription view |
| Settings "Go Pro" row | Subscription view |
| First open of the day, every 3 days | Subscription view |
| 3rd, 6th, and 9th expense saved in a month (free user) | Pro benefits card |

### Go Pro pill (Home header)

Persistent affordance for free users, immediately left of the Settings gear.
White pill, brand-green text, `crown.fill` icon, label "Go Pro". Hidden for Pro.

### Daily upgrade prompt

- Shown on **first open of the day, at most once every 3 days**.
- **Never in the user's first 3 days** — a prompt before the app has proved
  itself converts badly and taints the first impression.
- Suppressed while any other sheet is already presented, so prompts never stack.
- Dismissible. Same calm tone rules as every other prompt.

### Pro benefits card

The only proactive prompt (every other trigger is reactive — the user tapped a locked thing). Rules:

- Shown after a free user saves their 3rd, 6th, or 9th expense of the calendar month.
- Maximum 3 showings per calendar month. Counter resets on the 1st.
- Never shown mid-batch during bulk import — one prompt per save moment, never stacked.
- Lists real Pro benefits only: unlimited receipt scanning, unlimited CSV exports, PDF reports, no ads. Never claim a benefit the free tier also has, and never a feature that isn't built.
- Same tone rules as all prompts: [Upgrade to Pro] / [Not now]. No urgency.

### Tone rules

- Calm, not aggressive.
- No countdown timers.
- No urgency tactics.
- No "limited time" language.
- CTA text: "Upgrade to Pro" in sheets, "Go Pro" in settings.
- Dismiss text: "Not now" (not "No thanks", not "Maybe later").

### Standard upgrade sheet

Used for genuinely Pro-locked items. PDF export is the only one left — CSV and
OCR are metered allowances, not locks, and get their own copy (above).

```
Title: Pro Feature

Body: [Feature name] is available with Tally Pro.
      Unlock unlimited receipt scanning, unlimited exports,
      PDF reports, and no ads.

Buttons:
  [Upgrade to Pro]
  [Not now]
```

**Never say "Pro feature" to a user who has simply spent a monthly allowance** —
it tells them something is locked when it isn't. `ProFeatureSheet` takes a
`limitReached` flag that switches to the export-limit copy for that case.

---

## Subscription Management

- iOS: StoreKit 2 via RevenueCat. Product id `com.asimplelife.tally.pro.monthly`
  (not yet created in App Store Connect — see Open items); entitlement
  "A Simple Life - Tally Pro".
- Subscription status stored locally and validated via App Store receipt.
- No proprietary backend for subscription validation.
- On expiry/cancellation: revert to free tier. All data preserved. Export limits re-apply.

---

## What NOT to do

These are explicit prohibitions. Never implement any of these:

- Interstitial ad after Save
- Rewarded ad to unlock uploads
- Full-screen ad on export
- Mid-scroll ads in expense list
- Ads during keyboard input
- Ads in any sheet or modal
- Upload caps or upload gating
- Storage caps (storage is user-owned via iCloud)
- Countdown timers or urgency language
- "Accountant" framing anywhere

---

## Monetisation Changelog

| Date | Change |
|---|---|
| 2026-02-28 | Initial brief: CSV 1/month, PDF Pro, no interstitials, banner only |
| 2026-02-28 | Upload caps removed (unlimited for all). iCloud-only storage. Monthly auto-export confirmed as Pro. Bulk delete ungated. Add Expense ad strategy refined (keyboard hiding, 3-expense threshold). Storage caps removed (user-owned iCloud). No Stripe/web subscription for now. |
| 2026-07-12 | 15/month free expense cap removed from app (violated this brief; brief confirmed as source of truth). Pro benefits card documented: proactive prompt on 3rd/6th/9th expense per month, max 3/month, never mid-batch. |
| 2026-07-20 | **Audit of code vs. brief found six divergences; resolved as follows.** (1) CSV free allowance was 2 in one place and 0 in four others — now 1 everywhere, enforced via `canExportCSV` on all six export paths. (2) OCR changed from Pro-only field gating to a **10 successful scans/month** quota with full extraction for everyone. (3) **"Advanced filters" deleted** — the label was never a real feature and no code ever gated it; it was a false paywall claim. (4) **Monthly auto-export deleted** from code, docs and paywall — never built, and it overcomplicates the app. (5) Ads extended to every full screen incl. Expense Detail and inline in the expense list; the old "no inline sponsored rows" rule is superseded. (6) Interstitials reconsidered and again rejected. Added: Go Pro pill in the Home header, and a daily upgrade prompt (every 3 days, 3-day grace). |
| 2026-08-25 | **Home banner moved out of the tab bar** to beneath the pinned tags (it overhung the FAB and covered the + button). The shared bottom-docked banner that covered Home/Reports/Tags is gone; Reports keeps its own inline ad, but the **Tags tab now has no ad** — open item. |


---

# Engineering & Session State

*Folded in from the former `SESSION_HANDOVER.md` (2026-08-25). This is the
how-it's-built, what's-shipped, and what's-open half of the doc. **Every session
is responsible for keeping this document current** — pick it up, read it, and
before the session ends, log what you changed and any decision made. Precedence
when sources disagree: **the code wins**, then this brief's Monetisation part for
money, then the canonical reference `Tally/Tally - Everything You Need To Know.md`
(quote that filename, it has spaces). Fix a contradiction in the same session you
find it.*

## Product & design decisions log (self-updating — keep this current)

**This log is the memory of *why*.** Whenever Josh makes or confirms a product,
design, or UX decision — or reverses one — append a dated entry here with the
reasoning, newest first, so any later session can reason over the intent instead
of guessing or relitigating. Record the *why*, not just the *what*: a decision
without its reason gets re-argued. Keep each entry tight. This is distinct from
the Monetisation Changelog above (money mechanics) and from shipped code
(**Current state** below) — this is the rationale record.

**Do-not-relitigate shortlist** (the settled calls; the entries below carry the
reasoning): FAB opens the entry menu • single-tag rule (standalone / group /
group+sub-tag) • Home gradient is the bottom-most layer • no interstitial ads
(rejected twice) • OCR metered by volume, never crippled by field • a failed scan
is never charged • the paywall only lists built features the free tier lacks •
totals are single-currency, never mixed across currencies.

| Date | Decision | Why |
|---|---|---|
| 2026-09-23 | **Real fix for the tag-picker freeze (add + edit + multi-receipt):** `SharedTagPickerSheet` now sweeps the expense history at most once per open, and only when sorted by Recent. `recency` was a computed property (`tagRecency(from: expenses)` over the full `@Query` of every non-deleted expense), so it re-ran on every read — once for standalone tags, once for groups, and once per group for its children (2+G full sweeps per render, on the main thread). It's now computed once in `body` and threaded into the sort helpers; alphabetical sorts skip it entirely. | Josh captured the paused backtrace on-device and it landed exactly on the `recency`/`sortedForDisplay` block — the first hard evidence, after the `presentSheetAfterTouch` deferral (below) failed. The freeze was never about presentation timing; it was repeated whole-history sweeps with SwiftData faulting each record in from the CloudKit-backed store, which is why it hit only on his real device and never on the ~5-expense sim. Compiles; the sweep count drops from 2+G to 1 (or 0 for A–Z/Z–A). |
| 2026-09-22 | **Edit screen's sheet controls now defer the present past the keyboard**, matching the add screen. Tag, Date, Currency (both), and Replace on `ExpenseDetailView` route through a local `presentSheetAfterTouch` (clear `focusedField`, present on the next runloop) instead of `focusedField = nil; showingX = true` synchronously. | Tapping Tag on the edit screen while the keyboard was up (e.g. straight from the Note field) froze the app on device — the same synchronous-present-over-live-keyboard gesture-gate deadlock the add screen already fixed with `presentSheetAfterTouch`. The edit screen simply never got that fix. Verified on the sim the sheets still open; the device freeze itself isn't reproducible on the sim. |
| 2026-09-23 | **The post-pick "confirm receipt" screen was removed entirely, and the add-photo flow restored to exactly how it shipped before** (photo picker: `loadObject` then `dismiss` inside the completion; on pick → scan → the add form shows the receipt hero). Do NOT re-attempt the confirm screen without a way to reproduce Josh's device behaviour first. | Every version broke the core add flow on Josh's phone (iOS 26.6.2) while passing on the sim: `.fullScreenCover` and `.overlay`-during-dismiss froze the picker's X/Tick; dismissing the picker before `loadObject` (to dodge an iCloud-download hang) dropped the image hand-off so the photo never loaded. It was unverifiable on the sim and repeatedly destabilised the app's most important screen, so it's out until it can actually be tested on-device. The general lessons (suspect your own change first; don't ship blind device-only fixes) are in CLAUDE.md. |
| 2026-09-22 | **Scan no longer auto-fills the note.** `applyOCRResult` and the multi-receipt review stopped applying `result.notes`; the note field stays empty unless the user types. The OCR still computes it (unused) so its tests stay green. | The auto-note only ever pulled raw receipt line-item text (cryptic codes like "LS PAD KEE MAO CHICK*"), which reads as noise, not a useful note. Josh's call: better empty than junk. |
| 2026-09-17 | **Attendees on an expense.** New `ExpenseModel.attendees: [String]?` (additive, nil-safe). An inline attendees field sits directly after the Tag row on both the add and edit screens — above the Recurring card on add (edit has no recurring), matching Josh's placement. It's a pills-plus-typing field: added people show as removable capsule pills (`WrapLayout` wraps them), and an "Add attendee..." text field recalls past attendees as autocomplete chips (merchant-style, from a `knownAttendees` list built once on open). Cap 20; a name typed but not turned into a pill is flushed into the list on save. | Josh asked for this in Tally Working 1 (never recorded — doc miss). He wanted it treated like tags (pills) but with merchant-style recall as you type, so it's a token field: pills for the chosen people, inline autocomplete for adding. Inline (not a sheet) because "auto-recommends as you type" implies typing on the form, and there's no hierarchy to justify a picker sheet. |
| 2026-09-17 | The edit-save feedback (coin sound, haptic, celebration) now fires **only when something actually changed** — `saveEdits` returns early via `hasUnsavedChanges` before saving or posting `.expenseLogged`. | Opening an expense and closing it without edits shouldn't reward you with a celebration or bump `updatedAt`; the animation is for a real edit. |
| 2026-09-16 | **Reports period window is now calendar-month-aligned, not a rolling date.** `filteredExpenses` (and the previous-period comparison) run from the first day of the earliest month the chart shows (`periodStart`), so the headline total always equals the sum of the visible monthly bars. Also, the top-category card subtitle now names the period ("$X · last 6 months") instead of the selected chart month. | The old rolling window (`date >= now − 6 months`) let a late-in-the-month expense count in the total while appearing in no bar — the "$9 total, empty chart" bug. And the top-category card labelled the period-wide total with whatever month bar was tapped ("$9 in Sep", "$9 in Aug"), implying money was spent in an empty month. Calendar alignment makes "LAST 6 MONTHS" mean the six months drawn, and the subtitle now tells the truth. |
| 2026-09-16 | Saving an **edited** expense now fires the same save feedback as a new add — coin sound, success haptic, row-landing animation and the celebration overlay — by posting `.expenseLogged` from `ExpenseDetailView.saveEdits` (before dismiss, matching the add path). Verified via the audio log (the coin MP3 plays on Done). | Editing gave no confirmation it saved, which felt dead; Josh wanted the same tactile/visual payoff as logging a new one. Reuses HomeView's existing `.expenseLogged` pipeline with a single notification post, so add and edit feedback can't drift apart. |
| 2026-09-16 | **Reverted the edit screen from the native grouped `List` back to the receipt-object layout** (restored `ExpenseDetailView` from `1585dbd`). The prior session's List rebuild is undone. Verified on the iPhone 17 Pro simulator that the receipt layout does **not** crash on double-tap-select or field switching. | The List rebuild threw away the receipt design on the theory that one big custom view "starved the keyboard input service" and caused the double-tap crash. That was wrong: the crash's actual root cause was the app-wide window keyboard-gesture, already removed in `1585dbd`/`bfc1dfb`, so the design and the crash fix were independent. The stale current-state note claimed Josh *chose* native ("that should have been your approach from the get go"); on seeing it he called it "horrible and barren" and asked for the receipt view back. Design intent + crash fix now both hold. |
| 2026-09-16 | The add-expense receipt now matches the edit screen: tag pill riding the top edge (`receiptTagPill`), animated tag-colour frame, and the fields are **edit-style rows** (tinted icon square + label-above-value + dashed dividers) on the white receipt body, not cards. Recurring stays a card inside the receipt (add-only; edit has no equivalent) so the torn edge sits below it. The rows are replicated on the add screen (bound to add's own state/pickers) rather than shared with edit, because a cross-file shared component with `@FocusState` bridging is too risky to land blind — flagged for later extraction to remove the duplication. `receiptAmountCard`/`receiptDateRow` are now dead (unused) and should be deleted in a cleanup. | Josh, after seeing the wrapped receipt, wanted the add fields to match the edit format. Replicating the edit rows (vs sharing) trades §9's no-duplication for rule 2's "prefer the version least likely to misbehave" given no local compiler — the row look is now identical and can be unified once stable. |
| 2026-09-16 | The add-expense receipt now wraps the **whole** form: the photo is framed in the tag colour on top, the existing field cards sit on the white receipt body, and the torn edge is below the last field — one receipt. Fields (the cards) are unchanged, just inset on the paper. Supersedes the 2026-09-15 scoped version (torn edge under just the image), which Josh said was wrong. Josh picked "keep the cards, wrap them" over turning the fields into rows. | Josh wanted the receipt to read as one object extending to the bottom of the fields with the torn edge beneath them, while keeping the familiar field cards. Mirrors the edit screen's receipt structure (frame + white body + torn bottom) but with cards as the body instead of rows. Cards read on the white paper via their existing borders; if it looks washed out, tint the paper or the cards (don't change the fields). |
| 2026-09-16 | **Real fix for the ~55s "Change" freeze:** the app-wide keyboard-dismiss tap recogniser (`KeyboardDismissGesture`, on the key window) left `delaysTouchesEnded` at its default `true`, so it held every tap's touchesEnded until it resolved; inside a scroll view that made the scroll recogniser wait, and presenting a sheet mid-wait deadlocked the system gesture gate. Set `delaysTouchesEnded = false` (and `delaysTouchesBegan = false`). | The earlier `presentSheetAfterTouch` deferral (below) did **not** fix it — the tell was that the edit screen opens the same sheet synchronously without freezing, so timing of the present wasn't the cause. The window recogniser delaying touch delivery was. The deferral is harmless and kept as belt-and-suspenders, but this recogniser change is the actual fix. |
| 2026-09-16 | On the add-expense screen, sheet-opening controls route through `presentSheetAfterTouch` (clears focus, defers the present one runloop). Kept as defence in depth, but the freeze's real cause was the window tap recogniser (entry above), not synchronous presentation — this deferral alone did not fix it. | The "Change"/tag button froze the app for ~55s (not a crash — a gesture deadlock; the gesture-gate log showed `_UISystemGestureGateGestureRecognizer … blocking its subgraph` with the scroll view's touch recognisers stuck). First theory was "resign focus first" (the keyboard — wrong, auto-focus is suppressed when a receipt is attached); second was "defer the present" (this entry — also not the cause). The actual cause is the window recogniser's `delaysTouchesEnded`; see the entry above. |
| 2026-09-15 | The add-expense receipt hero now frames the receipt image in the tag colour on a receipt-paper backdrop with a torn bottom edge (reusing the edit screen's `ReceiptShape`/`ReceiptTexture`, now internal not private), **without** changing the fields below. Scoped adoption of the receipt look, not the full row redesign (which stays parked). Josh asked for it with an explicit rollback option if he doesn't like it. | Josh wanted the add screen to start feeling like the receipt design without the risk of the full form unification. Contained to `receiptHeroView`; easy to revert to the plain rounded image if rejected. | 
| 2026-09-15 | Every control on the add/edit expense screens that presents a sheet (tag picker, currency picker, date picker) must clear `focusedField = nil` **before** setting the sheet flag. The add screen's tag "Add a tag"/"Change" and currency buttons didn't, and presenting a sheet while a text field held keyboard focus crashed the app (the same keyboard-snapshot crash fixed earlier on the edit screen's tag button). | Presenting a sheet over a live keyboard makes UIKit snapshot the keyboard mid-teardown and crash. It's a recurring class of bug on these screens — treat "resign focus first" as the standing rule for any sheet-presenting control here. |
| 2026-09-15 | Export "by tag/folder" picker rows now use the shared `TagIconBadge` (colour swatch + emoji) with a trailing selection circle, and "Groups" is relabelled "Folders" — matching the Tags & Groups page. The pinned-tag scroll bar is driven by a UIKit KVO observer on the scroll view (the preference approach never fired). Add screen's Done button is now plain green text like the edit screen (was a filled capsule + checkmark). Recurring chips are equal-width segments so "Fortnightly" no longer wraps. | The export picker's tiny colour dots read as an old, separate design; reusing `TagIconBadge` makes it look like the rest of the tag UI. Preferences from inside a `ScrollView` proved unreliable (same reason the list uses KVO). The two Done buttons should match. Four fixed-padding chips overflowed the row. |
| 2026-09-14 | The pinned home-tag row shows a small green scroll-position bar beneath it that moves as you swipe, and only appears when the row overflows. Day-divider text opacity dropped 15% (`.opacity(0.85)`). | With more pinned tags than fit, nothing signalled the row scrolls; a moving green thumb is a quiet "swipe for more" that stays out of the way when everything fits. The divider text read a touch strong against the list, so it's eased back. |
| 2026-09-12 | Home day dividers now show the date on the left, a hairline across, and **that day's total on the right** (aggregated over the day's expenses, scoped to the active currency), matching Josh's reference. Grey `#8E8E93`, uppercase tracked date, top-biased padding (20 above / 6 below) so the divider heads the expenses beneath it. Supersedes the plain left-aligned `#636367` date label. | A running per-day total at a glance is more useful than a bare date, and the reference (rule between date and total) reads as a finished ledger. The lighter grey and rule match the reference; single-currency scoping keeps it consistent with every other total (no mixing). Top-biased spacing makes it unambiguous which day's expenses it caps. |
| 2026-09-12 | Delete shred: the **drop/fade runs at half speed** (receipt 1.8s, strips 2.3s, sparks 1.6s; overlay held 2.8s) while the **shake is unchanged** (0.13s × 6, same speed and count). | Josh couldn't follow what happens on delete — it dropped and faded too fast. Slowing only the drop makes it legible; he explicitly wanted the shake left alone, so its speed and count are untouched and driven separately from the fall. |
| 2026-09-12 | Banner ad sizing fixed: the `GADBannerView` no longer disables its autoresizing mask, and `BannerAdView` sizes its frame to the ad's real delivered height; the Reports ad is full-width (no side padding). | `translatesAutoresizingMaskIntoConstraints = false` with no constraints made the banner ignore its SwiftUI frame and fall back to the ad's intrinsic size — the clipped banner on Home and the blown-up ("zoomed") Reports layout on free tier (the ad is the only free-vs-Pro difference on Reports). Letting SwiftUI own the size and matching the container to the delivered height fixes both. **Unverified here — AdMob can't render on Windows; check on device.** |
| 2026-09-09 | Tag icon picker keeps the **system emoji keyboard** (`EmojiInput` in `TagCreationView.swift`), not a custom in-app grid. | The first-open lag and the `GenerativeModelsAvailability` / `WebContent` / `Reporter disconnected` log noise are the iOS 26 emoji keyboard warming a web process for emoji-search/Genmoji — an OS cost, not a Tally bug, and the keyboard is genuinely native. Josh chose native over a faster custom grid that would lose "pick any emoji". Do not replace it to chase the lag. |
| 2026-09-05 | Drag-to-select reworked to track row frames in a plain `RowFrameStore` class (written per visible cell via onAppear/onChange in **global** coordinates), not a `PreferenceKey`; hit-test is by the finger's y-band in global space. A row toggles when the finger *enters* it (tracked by `dragLastRowId`), and each tick toggles **every row between the last sample and the current one** so a fast drag can't skip rows; dragging back over already-selected rows within the same drag **deselects** them, while lingering on one row doesn't flicker. Selection bottom bar lowered further (top 12 / bottom 6, was 18 / 22) to sit just above the home indicator. Shred delete animation slowed (~1.9s of visible action, was ~1.3s) and its hold extended to 2.2s. | The first drag-select cut used a PreferenceKey from inside List cells, which this codebase already knew don't propagate reliably (ListScrollDetector uses UIKit KVO for the same reason) — so it read stale/sparse frames and selected the wrong rows and wouldn't track across the list. A frame store written from cell lifecycle callbacks, matched in global coordinates, removes both the propagation and the coordinate-space ambiguity. The enter-a-new-row toggle (vs a once-ever visited set) is what lets a reverse drag undo, which Josh asked for. Bar was still too high; shred read as vanishing too fast. **Known limit:** the drag selects the on-screen rows (scroll is frozen during the drag) — auto-scroll past a screenful is a follow-up if one screen isn't enough. |
| 2026-09-04 | Home multi-select gains Photos-style drag-to-select: a drag beginning in the leading checkmark column (x < 60) toggles each expense it crosses (haptic per row); the list stops scrolling while that drag is live. Tap-to-toggle and long-press-to-enter are unchanged; a drag starting anywhere else still scrolls. | Selecting a run of expenses one tap at a time is tedious; dragging is the native iOS Photos gesture Josh asked for. Anchoring the select-drag to the checkmark column disambiguates it from a scroll, so the list still scrolls normally in and out of selection mode. (Reworked 2026-09-05 — see above — after the first frame-tracking approach mis-mapped rows.) |
| 2026-09-04 | Exporting a home multi-selection skips the "Pick a period" step and exports exactly the selected expenses (straight to the format step; the leading control is Close, not Back). Period-detail export still auto-detects a period. | Josh selected specific expenses, so defaulting to "last month" and making him re-pick a period was wrong — the selection *is* the scope. Gated behind a `directSelection` flag so only the home flow skips the picker; the period-detail path (which exports a whole period's list) keeps its auto-detect. |
| 2026-09-04 | Boot splash progress bar fills up green (empty → full, repeating) instead of a segment sliding across. | The sliding segment read as "reversed" to Josh. A fill-up is the conventional "loading" motion and reads as forward progress. |
| 2026-09-04 | Year markers on the Home list mirror the receipt "DETAILS" divider: a small grey (`#636367`) label with a hairline rule on each side, centred, with balanced vertical padding. Was a large dark serif year with top-heavy padding. | The big serif year sat in an awkwardly large, top-heavy space and didn't read as a divider. Matching the DETAILS treatment makes it a quiet separator that sits centred between the year's groups, consistent with the date labels' grey. |
| 2026-09-04 | CloudKit sync events are handled off the main thread (a serial utility `OperationQueue`), the `lastSyncDate` refresh is throttled to at most once per minute, and the "cloudkit export ok" info log is DEBUG-only. `AdManager.shouldShowBannerAd` now defaults to **false** (was true). | Scrolling stuttered and the log spammed "cloudkit 2 ok" because every sync event did main-thread work; sync must never touch the main thread outside a throttled UI refresh. The ad default flipped because banners were network-loading on the first frame (before `configure` ran) even for Pro users — starting hidden means nothing loads until `configure` decides. Note: SwiftData's own post-import view-context merge still re-runs `@Query` and has no public throttle knob, so residual merge cost is mitigated only by keeping per-refresh work in `HomeView` cheap. |
| 2026-09-03 | The expense detail screen is one "dynamic receipt" object (tag-tinted frame, DETAILS tear line, dot-textured paper, torn bottom, shadow); detail rows use a tinted icon square + label-above-left-aligned-value; no-receipt expenses frame a hero amount in the tag colour; untagged defaults to Tally green; Delete is a full-width filled red button. | Adds character and makes the screen feel like a physical receipt (Josh liked a reference build). Label-above-value maximises width so long merchant names aren't cramped. Tint tying the whole object to the tag colour makes each expense feel categorised at a glance. |
| 2026-09-03 | Tally Suggests learns from history: it suggests the tag used on a previous expense from the same merchant (keyword engine is the fallback), and still disappears the moment the user sets their own tag. | Suggesting from the user's own past tagging is more accurate than keywords alone; hiding once they tag keeps it from nagging. Josh confirmed the hide-when-tagged behaviour is correct (not a bug). |
| 2026-08-27 | Review rows are a balanced two-column layout: amount + merchant stacked left, date pinned right, chevron far right; tighter card padding and a plain-green Cancel with no nav divider. | The first cut had a big amount top-left with "merchant · date" cramped beneath and the whole right half empty, so cards read tall, sparse and unfinished. Pinning the date right fills the width and matches the reference density. Standing lesson recorded in CLAUDE.md: build lists/sheets to occupy the screen like a finished app. |
| 2026-08-27 | Multi-expense review cleanup (shared by photo + statement flows): unticking dims the card's content only (card stays solid white); the red swipe-Delete exists only during an active swipe; statement rows drop the PDF tile (tick + details only, photo rows keep their thumbnail); a "N found · review and add the ones you want to keep" banner tops the list. | The unticked card was 50% opaque, so the red Delete panel behind it bled through and the bin dragged down as the row expanded — looked broken. The PDF tile cluttered statement rows; removing it lets the details fill the width and the page feel finished. The banner frames the task and fills the top. All via the one shared view, so both flows improve together. |
| 2026-08-27 | Home list: bigger gap above each date label, small gap below, so the date heads the expense beneath it. | The date sat 2pt under the previous expense and read as belonging to the wrong one. |
| 2026-08-27 | An OCR scan counts against the free allowance only when the expense is **saved (Done)**, never at scan time — in both the single-add and bulk-review flows. Scanning and backing out (or removing the receipt) before saving costs nothing. | Josh's call (chosen over charging at scan time). It's the fairer model: you're charged for scans you actually keep. The bulk review already charged at save; the single flow was charging in `applyOCRResult` at scan time, now deferred to `saveExpense` (guarded on a positive-amount scan + receipt still attached). Accepts that a user could scan-and-abandon without being charged. |
| 2026-08-27 | The **live** export display (hero card + period cells + count + CSV) is scoped to `activeCurrency` at the source (`expenses(for:)`). Extends the 2026-08-26 export entry, which had fixed a dead `totalCents`; the real "huge sum" was `selectedHeroCard` summing `amountCents` across currencies with a hardcoded `$`. | No FX → a mixed export total is meaningless. Scoping at the source keeps every number on the sheet and in the file on one currency; switch the currency filter to export another. |
| 2026-08-27 | Two inline metric cells (Reports: Monthly avg + Top category) are always equal height. | The monthly-avg cell has a conditional third line, so it rendered shorter than the top-category cell beside it — inline siblings of different sizes look broken. Both now stretch to the taller. |
| 2026-08-27 | Free tier gets a banner under the New-Expense entry picker and under the recurring card on the receipt-scan add page — narrowing the "no ads in any sheet" rule (the entry picker is a sheet). | Josh's call to add inventory on two high-traffic add surfaces. The receipt add page's persistent bottom banner is suppressed while a receipt is attached, so the ad sits under the recurring card there; it still hides during text entry. |
| 2026-08-26 | Add "Import from statement": upload one PDF, extract each transaction into a draft expense, review, save. It **replaces** "Import from notes" (archived, not deleted) in the same Add-menu tile. | A statement is the fastest way to log a month of spending. It's the existing upload → OCR → review → save pattern with a statement source, so it stays inside the non-goals (no bank *sync*/reconciliation, no stored statement). Notes-paste import earned its slot less. |
| 2026-08-26 | Import from statement is **Pro-only** (gold crown on the tile; free tap → upsell; listed on the paywall). | Adds real Pro value, and closes the loophole where a free user could bypass the 10-scan/month cap by importing dozens of expenses from one PDF. Pro-gating at entry also means no OCR-quota accounting for it. |
| 2026-08-26 | Statement import brings in **debits only**; the PDF is **never stored** (read in memory, discarded); each expense gets a note "Generated from PDF statement" and a green PDF tile, no attachment. | Tally is an expense tracker, so money-in is filtered (user can still drop rows in review). A bank statement is sensitive; storing it would make Tally a custodian of exactly the data it avoids holding. The tile/note make PDF-sourced expenses recognisable without keeping the file. |
| 2026-08-26 | The statement review IS the multi-receipt review — one parameterised view (`ReviewConfig`), not a look-alike. Removal (swipe + in-row Delete) was added to the shared view. | Josh is tired of near-identical pages drifting apart. A design change to the review must update both flows at once; the only differences are data-driven (image vs PDF tile, attachment vs none, charge vs none, source string). |
| 2026-08-26 | A scan is charged only when OCR extracted a **positive** amount. A 0.00/no-amount read (e.g. a photo that isn't a receipt, even if a stray "merchant" was picked up) is never charged, on both the single and bulk paths. | A free user photographed a car dashboard, got $0.00 + a garbage merchant ("NFC"), and it consumed a scan. Per the monetisation rule the scan's whole value is the amount; a zero isn't a real extraction. Merchant-alone never charges (existing rule), so requiring a positive amount covers the bogus case without giving away amount-only successes. |
| 2026-08-26 | Export totals (both export sheets) are single-currency, scoped to `activeCurrency`, like the rest of the app; the CSV lists every expense but formats each amount by its own currency's minor-unit rule. | The export summary summed `amountCents` across currencies and formatted as one currency, so an IDR 610,248 receipt showed as ~$610,248. No FX means a mixed sum is meaningless. The CSV `/100` was also wrong for no-minor-unit currencies. |
| 2026-08-26 | Toggles (pin/unpin a tag) mutate the model only; they don't call `modelContext.save()` per tap. Persistence rides on SwiftData autosave, with a single explicit flush on the pin sheet's dismiss. | The `@Query` reacts to the in-memory change, so the UI is instant without a save. Each explicit `save()` forced a synchronous disk write and an iCloud export — on rapid toggling that's needless churn (and the source of the repeated CloudKit export scheduling). Autosave (on by default, flushes on backgrounding) coalesces it; the sheet-dismiss flush guarantees durability at a natural boundary. Placement principle: save at deliberate boundaries, not on every interaction. |
| 2026-08-26 | Pinned tags on the Home bar are ordered alphabetically (A–Z by name), not by stored `sortOrder`. | Predictable, scannable order; the pinned row is a lookup surface, so alphabetical beats an arbitrary insertion order. |
| 2026-08-26 | The hero header keeps its size but the green area gets a subtle curved bottom wave, a calendar icon on the period pill, and a larger top-category icon. | Josh's redesign: the flat card read as "a giant card sitting above the app". The soft curve at the bottom makes the header feel integrated and gives the expense list more visual priority, without changing functionality or footprint. |
| 2026-08-26 | `HomeToggle` fills brand green (white thumb) when on, mirroring a native iOS switch, instead of a grey track with a green thumb. | The grey-track/green-thumb read as unselected at a glance; a green-filled track makes an active tag obvious and the toggle feel responsive. |
| 2026-08-26 | Tapping anywhere off a text field — empty space or another button — dismisses the keyboard app-wide (window-level tap recogniser). | Mirrors native iOS. A per-screen approach kept missing spots; one window recogniser covers the whole app and doesn't swallow the underlying tap. |
| 2026-08-26 | The `updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.*` log is a benign CloudKit background-scheduling message, not a bug — fixed by declaring the `processing` background mode. | It fires on any SwiftData save (the container tries to schedule a background export) because the app only declared `remote-notification`, so BGTaskScheduler rejected the export task. Sync still worked foreground; the log was noise. It was NOT the toggle lag (that was a per-render expense rescan). |
| 2026-08-26 | The tag/group icon is one shared `TagIconBadge` (34pt circular colour swatch + emoji) used by the Tags tab, the pin-to-home sheet and the filter sheet. | Those three lists had drifted — the pin sheet showed a 12pt bare dot, the filter sheet 10/8pt dots and a folder glyph, none matching the Tags tab's emoji badge. A single component means they can't diverge again. Filter sheet's nested child tags keep a smaller (26pt) badge + indent to stay visually subordinate. |
| 2026-08-26 | Holding a pinned tag on Home does a subtle shake + haptic before the editor opens. | Borrows the iOS "hold an app icon to edit" idiom so the long-press reads as "you can edit this", not a dead hold. The editor still opens (0.4s later) so the shake is seen first. |
| 2026-08-26 | The edit-tag screen shows a live circular colour+emoji icon preview centred above the name. | Same pattern as editing an iOS contact's photo: users see the tag's appearance update as they change colour/emoji, before returning to the home page, instead of guessing. Matches the home card's circular colour-filled icon. |
| 2026-08-26 | The pin-to-home toggle lives on the edit-tag screen (with subtext "Pin this tag to your home page for quick filtering"), not only in the separate home-bar sheet. | Pinning is a property of the tag, so it belongs where you edit the tag. The explanatory line stops the toggle being a mystery switch. Groups can't be pinned, so it's tag-only. |
| 2026-08-26 | The "More" card in the Home pinned-tags row is relabelled "Add tag". | "More" was vague; the card's job is to add a tag to the pinned row. |
| 2026-08-26 | The Home persistent header (search + pinned tags) has an opaque background, painted with the Rise gradient sampled at the header's own screen position (via a GeometryReader), not a flat fill. | The collapsing/expanding hero card ghosted behind the transparent header. A flat `F0EDE6` fill hid it but left a visible seam where its bottom edge met the greener gradient below; reproducing the actual canvas gradient at that position makes the bottom edge match exactly — opaque, no line. |
| 2026-08-25 | The Tags tab header matches the Reports page: an eyebrow label over a 30pt serif title, pinned at the top. | The bare title buried low in a list didn't read as part of the platform. Reusing the Reports header shape makes the tabs feel like one app. Eyebrow copy "ORGANISE" is a placeholder Josh can reword. |
| 2026-08-25 | The monthly report (period detail opened from the Home hero) pages between months by swiping left/right on the By Week chart. | Reviewing one month at a time is the natural motion; swiping the chart keeps navigation where the eye already is, without a separate month picker. Capped at the current month (no future). |
| 2026-08-25 | Expanding a category slides its rows out from *behind* the header, never over it. | The rows ghosting across the heading during the open/close read as a rendering bug. The drop-down motion stays; the header+progress bar became an opaque block the rows pass behind, and the cell clips so nothing paints above it. |
| 2026-08-25 | All circular header/nav icon buttons are one size: 36×36 with an `EDEAE4` fill. | The period-view share button was 34pt with a white fill and border — a visible outlier next to the 36pt Home gear and Reports arrow. Buttons of the same role should read as the same control everywhere. |
| 2026-08-25 | A selected pinned tag gets a dark Tally green (`2F402E`) 2.5pt edge, not a light-green one (and not a filled box). | The light-green border was too subtle to tell active from inactive at a glance. A dark green edge makes it obvious while keeping the card white — a full fill was too heavy. |
| 2026-08-25 | The period label in the report header is enlarged and darkened. | The month / "ALL TIME" label was small grey-green and easy to miss; it anchors the whole screen (and now changes as you swipe months), so it earns prominence. |
| 2026-08-25 | Totals are always single-currency, scoped to `activeCurrency`; foreign-currency expenses show as rows but are never summed into the headline. | The app stores a currency per expense and has **no FX** (a deliberate non-goal). Adding amounts across currencies produces a meaningless number — a ₹608,600 receipt was reading as $608,600 in the period view. One rule everywhere means reports, sheets and exports agree, which Josh values as reliable data with no loose ends. |
| 2026-08-25 | Free-tier banner moved from the bottom tab bar to beneath the pinned tags on Home. | The docked banner sat under the FAB overhang and covered the + button no matter the padding — a hard no. It can't go lower (it's already at the safe-area bottom), so it moved up into the header where it's clear of every control. |
| 2026-08-25 | Tags & Groups rows use an enlarged circular colour swatch with the tag's emoji inside. | Matches the home row's icon treatment (recognisable), but circular; the 12pt dot was too small to carry an icon and read only as a colour. |
| 2026-08-25 | Logs never contain user data in clear; only errors persist in release. | Diagnostics must not leak amounts, merchants, notes, receipt text or IDs (privacy + data-sovereignty stance). `privacy: .private` redacts them in release and any sysdiagnose; `.debug` isn't persisted so release stays quiet. |
| 2026-07-20 | Ads follow the MyFitnessPal model (every full screen + inline in the list), superseding "no inline sponsored rows". | Inline list ads earn materially more and MFP proves users tolerate them in a list; the earlier rule left too much revenue unclaimed. Sheets stay ad-free (below). |
| 2026-07-20 | No ads in any sheet or modal. | Sheets are opened for one deliberate, low-dwell action — they earn little while doing the most damage to how the app feels. |
| 2026-07-20 | No interstitial ads (re-confirmed). | The core pitch is logging an expense in ~5 seconds; an interstitial in that loop attacks the one thing that makes Tally worth using. MFP, the reference model, runs none either. |
| 2026-07-20 | OCR metered by volume (10 successful scans/month), not gated by field; a scan counts only if it extracted an amount. | Blanking fields for free users read as a broken scanner, not a paid tier — constant low-grade friction, weak conversion. A volume quota lets everyone feel the feature work fully and puts the wall in front of heavy users who convert. Charging for a scan that didn't get the amount would feel like a scam. |
| 2026-07-20 | The paywall may only list built features the free tier lacks. | It had advertised "Advanced filters" (never built, never gated) and "Monthly auto-export" (never built) — false claims that erode trust. Both deleted. |
| Ongoing | Resist feature creep toward accounting/dashboard/budgeting. | Tally wins by staying a capture → tag → export tool. The biggest risk is becoming Expensify-lite. Restraint is the product. |

## Environment & repo reality

- **Working dir** `E:\Projects\ASimpleLife` (Windows). Mirrors to
  **github.com/joshmalosh/Tally.git** via the `tally` remote. **Always push to
  `tally` `dev`.** Never `origin` (that's the website repo), never `main`/`master`
  without explicit instruction. Josh's Mac clone names the remote `origin`, so on his
  machine the push is plain `git push`.
- **No Swift/Xcode toolchain on Windows.** You cannot compile, run, or test. Josh
  pulls `dev` in Xcode, runs on a physical iPhone, and reports back with
  screenshots and device logs. Don't append "still uncompiled" to every message.
- **A new `.swift` file only compiles once registered in
  `Tally.xcodeproj/project.pbxproj`** — four entries per file: `PBXBuildFile`,
  `PBXFileReference`, the group's `children`, and the target's `Sources` build
  phase. Dropping a file on disk is not enough; the build fails on the Mac even
  after a pull (this bit us on 2026-08-25 with `ExpenseModelTotals.swift`).
  **Default to putting new types/extensions/helpers in an existing file that
  already compiles.** Only create a standalone file when it earns one, and
  register it in the pbxproj in the same commit. Test files too. You *can* edit
  `project.pbxproj` from here; mirror an existing entry, unique ~24-char id,
  sanity-check with `grep -c` (expect 4 hits) and a brace balance — a malformed
  pbxproj fails loudly in Xcode, so it's safe to attempt blind.
- **Targets:** `Tally` (`com.asimplelife.tally`), `TallyShare` (share extension,
  `com.asimplelife.tally.share`), `TallyTests`. Both app and extension declare
  App Group `group.com.asimplelife.tally`. URL scheme `tally://` (share handoff).
- ⚠️ **Josh runs Pro. Settled — do not question it.** When he reports a bug he is a
  Pro user, so never explain a problem away as "the free-tier gate working as
  designed." Free-tier behaviour (ads, Go Pro pill, scan quota, CSV limit) is not
  visible in his build unless he flips Force Pro in Settings → Debug.
- **Tests** run on the Mac with **⌘U**. ⌘6 opens the Test navigator.

## Architecture & key files

- **Entry** `Tally/TallyApp.swift`. **Models** `Tally/Models/` (SwiftData `@Model`;
  soft delete via `deletedAt`; `ExpenseModel.swift` also holds the currency-safe
  aggregation helpers `inCurrency` / `totalCents(in:)`). **Domain** `Tally/Domain/`
  (parsing, calculations). **Theme** `Tally/Theme/` (tokens, shared components,
  `CurrencyFormatter`).
- **`Tally/AppState/AppState.swift` owns every free-tier limit** and the currency
  state — `activeCurrency` (= `filterCurrency ?? defaultCurrency`), `canExportCSV`,
  `canUseOCR`/`ocrScansRemaining`, `isPro`, plus the central `Log` enum. **Change a
  limit here, never at a call site.** Pinned by `TallyTests/MonetisationGatingTests.swift`.
- **OCR** `Tally/Services/ReceiptOCRService.swift` (+ corpus
  `TallyTests/ReceiptOCRServiceTests.swift`). See OCR regression testing below.
- **Home** `Tally/Views/Home/HomeView.swift` — list, Rise gradient (bottom-most
  layer, never put UI translucency over it), shred host, filters, inline ads,
  Go Pro pill. Also the **shell for Reports and Tags tabs** (opacity-switched).
  `PeriodDetailView.swift` is the drill-down; `HeroSpendingCard.swift` the hero.
- **Add/edit** `AddExpenseView.swift`; `MultiReceiptReviewView.swift` is the
  **shared multi-expense review** (photo receipts and PDF statements, driven by
  `ReviewConfig` — never copy it). `StatementImportView.swift` orchestrates the
  statement flow (PDF → text → `StatementParser` (in `BulkExpenseParser.swift`) →
  drafts → shared review). Adding a source = new config, not a new page.
  **Detail** `ExpenseDetailView.swift`.
- **Export** `Views/Export/GlobalExportSheet.swift` — six CSV/PDF call sites that
  must agree on the limit; `ProFeatureSheet`/`ScanLimitSheet` in `ExportView.swift`.
  Ad plumbing `Services/AdManager.swift`, `Services/RevenueCatConfig.swift`.
- **Share extension** `TallyShare/` + `Services/SharedInboxService.swift`.

**Currency is single-currency by design (no FX).** Every aggregate is scoped to
`appState.activeCurrency`: filter to it, total only those, format via
`CurrencyFormatter`. Use `ExpenseModel.inCurrency` / `totalCents(in:)` for any new
total so they can't drift.

**Unified logging** (`Log` enum in `AppState.swift`): `os.Logger`, subsystem
`com.asimplelife.tally`, categories app/sync/data/ocr/subscription/ads/attachments.
User data is `privacy: .private`; only non-identifying diagnostics `.public`.
DEBUG-only in-app viewer at Settings → Debug → View logs. Filter in Xcode/Console
by the subsystem. No `print()`.

**SwiftUI gotchas already paid for:** `.rotationEffect` after `.position()` rotates
around the *parent's* centre; two independently-animated values in one `.offset`
bleed into each other; GeometryReader re-measures on parent re-renders (caused the
shred drift). The bottom tab bar is an `alignment: .bottom` overlay and the FAB
overhangs it, so anything docked below the bar collides with the + button (why the
free-tier banner moved into the Home header, 2026-08-25). **`.clipped()` does not
clip hit-testing:** a `.background` built from a `GeometryReader` whose child was
screen-height and `.offset` upward overflowed its bounds and, though visually
clipped, swallowed every tap over the app bar and hero above it (dead settings /
Go Pro / Export buttons, 2026-08-26). Keep backgrounds bounded and mark any
non-trivial background `.allowsHitTesting(false)`.

## Current state — what's shipped (newest first)

- **Edit screen reverted to the receipt layout** (2026-09-16): the native-`List`
  rebuild (below, now undone) had thrown away the receipt design to chase a
  double-tap crash it blamed on the monolithic view "starving the keyboard's input
  service". That theory did not hold: the crash's real root cause was the app-wide
  window keyboard-gesture, already removed one commit earlier (`1585dbd` /
  `bfc1dfb`). Restored `ExpenseDetailView` from `1585dbd` (the state right before the
  rebuild) — the receipt object is back: tag-tinted frame, tag pill riding the top
  edge, textured white paper body with dashed row dividers, torn bottom edge, date as
  a graphical sheet. Josh's call: the grouped form "looks horrible and barren"; the
  receipt view is the intended look.

- **Edit-screen keyboard freeze fixed with a debounce, receipt design kept**
  (2026-09-16): after the revert, the field still froze for a few seconds on fast
  input (Josh's device logs: `Result accumulator timeout: 0.250000, exceeded` /
  `Reporter disconnected` / `Could not find cached accumulator`). Reproduced by
  streaming the simulator log while typing — the keyboard's autocorrection
  accumulator (a 0.25s-budgeted step that lands on the main thread) timed out because
  **`updateTagSuggestion()` ran synchronously on every keystroke** (scan all
  expenses + keyword engine + `withAnimation`), starving the main thread. Fix:
  debounce it — `.onChange` now schedules a cancellable `Task` that waits 350ms after
  the last edit, so the heavy work runs once on pause, off the typing hot path
  (`scheduleTagSuggestion`, `suggestionTask`). After the fix, a 35-char typing burst
  logged only `didTimeout: NO`, no timeouts. The receipt layout is untouched — the
  bottleneck was the per-keystroke computation, not the view. **Note:** the exact
  sub-300ms double-tap gesture can't be fired from the simulator harness (taps are
  seconds apart), so that specific gesture is **UNVERIFIED on device** — Josh to
  confirm the double-tap on a physical device with this build; if it persists, the
  next lever is isolating the text fields into child views.

- **Edit-screen freezes killed at the root; AUTO-SCANNED off edit** (2026-09-16):
  the recurring ~55s gesture-gate freezes (Change button, and double-tapping /
  tapping fields on the edit screen) all traced to one cause: the app-wide
  tap-to-dismiss-keyboard recogniser (`KeyboardDismissGesture`) installed on the
  key window for the app's whole life. It sat over every screen, so whenever a tap
  coincided with presenting a sheet or a text field's own double-tap-to-select,
  iOS's gesture gate deadlocked. Removed it entirely (`ContentView.onAppear` no
  longer calls `.install()`; the class in `UIApplication+ResignFirstResponder.swift`
  is now unused dead code, left in place to avoid pbxproj surgery). Keyboard
  dismissal is now purely native: `.scrollDismissesKeyboard(.interactively)` (already
  on Home, add, multi-receipt; added to the edit `ScrollView`). This supersedes the
  earlier `delaysTouchesEnded` patch, which only softened one path. On the **edit**
  screen also: removed the two `.onTapGesture { focusedField = .amount }` overlays
  that fought the amount field's native double-tap selection (the "reporter
  disconnected" freeze); dropped the manual `ScrollViewReader`/`scrollTo(anchor:.center)`
  in favour of the scroll view's own keyboard avoidance; and removed the
  AUTO-SCANNED badge (Josh: it belongs on add expense after a scan, not on edit).
  The tag/date/currency pickers stay as sheets — with the window recogniser gone,
  sheet-on-sheet is safe, and rebuilding the shared tag/currency pickers into pushed
  pages was the larger unverifiable change (touches the add screen) we chose not to
  make. **Verify on device:** edit is bulletproof — double-tap any field, tap the
  tag row, no freeze; and the add-screen Change button no longer freezes either.

- **Tag scroll bar, export badges, Done button, Fortnightly, edit field-centring**
  (2026-09-15): the pinned-tag green scroll bar is now driven by a UIKit KVO
  observer (`HorizontalScrollObserver`) on the underlying `UIScrollView`; the
  export by-tag/folder picker uses `TagIconBadge` rows + a selection circle; the
  add screen's Done is plain green text like edit; the recurring chips are
  equal-width so "Fortnightly" fits. On the **edit** expense screen, the tapped
  field now scrolls to centre above the keyboard (`ScrollViewReader` +
  `scrollTo(field, anchor: .center)` on focus), fixing "the keyboard covers the
  field" in the sheet. **Pending** (see Open items): the add screen adopting the
  edit screen's full receipt-object design, and swapping edit's amount field to
  `NumericFieldWithDone` for the residual keyboard lag — a large shared-form
  refactor deferred so it can be built and verified cleanly.

- **Day-total dividers, banner sizing, slower shred** (2026-09-12): Home day
  dividers show `DATE — hairline — day total` (active-currency sum of that day's
  expenses), grey `#8E8E93`, top-biased padding. The delete shred drop/fade runs at
  half speed (shake unchanged). The banner ad no longer disables its autoresizing
  mask and sizes to the delivered ad height, and the Reports ad is full-width — this
  fixes the clipped Home banner and the zoomed free-tier Reports page (banner is the
  only free-vs-Pro difference on Reports). Banner changes are **unverified** (AdMob
  can't render on Windows).

- **Home multi-select drag, export-skip-period, sync/ad perf, loading + year markers** (2026-09-04):
  Home multi-select now supports Photos-style **drag-to-select** — a `DragGesture`
  in **global** coordinates that, when it begins in the leading checkmark column
  (x < 60), toggles each expense whose global frame the finger's y crosses. Frames
  live in a plain `RowFrameStore` class, written per visible cell via
  onAppear/onChange/onDisappear while selecting (not a `PreferenceKey` — those
  don't propagate reliably from List cells). The list is `scrollDisabled` for the
  duration of the drag (so it selects the on-screen rows), and the gesture is
  masked out (`including: .subviews`) unless selecting, so normal scrolling is
  untouched.
  Sharing a multi-selection opens `GlobalExportSheet(directSelection: true)`, which
  **skips the period picker** and exports exactly the selected expenses (Close, not
  Back; period-detail export keeps auto-detect). The selection **bottom bar** sits
  just above the home indicator (top 12 / bottom 6) and the floating **X** is larger
  (40pt, 17pt glyph) with a stronger shadow (0.3). The shred **delete animation**
  was slowed to read over ~1.9s (held 2.2s). The boot **loading bar fills up green**
  (was a sliding segment). **Year markers** on the list mirror the DETAILS divider
  (grey `#636367`, a hairline each side, centred, balanced padding). **CloudKit**
  sync events are handled off-main on a serial utility `OperationQueue`, the
  `lastSyncDate` refresh is throttled to ≤1/min, and the "ok" log is DEBUG-only;
  `AdManager.shouldShowBannerAd` defaults to **false** so no banner loads on the
  first frame (Pro users saw banners network-load at launch before `configure` ran).

- **Functional boot splash (async store load)** (2026-09-03): `TallyApp` no longer
  creates the `ModelContainer` synchronously in `init` (which blocked the first
  frame, so the OS showed a static launch image during the real DB/CloudKit
  setup). It now builds the container on a background `Task.detached` behind an
  animated `BootSplashView` (logo + a genuine indeterminate progress bar + rotating
  taglines), swapping to `ContentView` when ready. ContentView's old after-boot
  cosmetic splash was removed. `configureRevenueCat` still runs in `init` (fast).
  Also removed the "DETAILS" tear line on the expense detail (saved height).

- **Expense detail as a "dynamic receipt"** (2026-09-03): the detail screen is now
  one cohesive receipt object — a tag-tinted frame around the photo (or a hero
  amount, framed in the tag colour, when there's no receipt), a perforated
  "DETAILS" tear line, a dot-textured white paper body, a torn zig-zag bottom
  edge, and a soft shadow. Frame/row-icon colours come from the expense's tag
  (`primaryColor`/`tintColor`), defaulting to Tally green when untagged. Rows were
  re-laid to the reference: a tinted rounded-square icon with the label stacked
  **above** a left-aligned value (maximises width for long merchants), dashed
  dividers. Delete is now a full-width filled red button. Tally Suggests also
  learns from history — it suggests the tag used on a previous expense from the
  **same merchant** (falling back to the keyword engine), and still hides once the
  user sets their own tag. New private helpers/shapes in `ExpenseDetailView`
  (`receiptObject`, `tintedIconSquare`, `ReceiptShape`, `ReceiptTexture`).

- **Native multi-select + no-snap fields** (2026-09-02): long-press multi-select had
  no visible actions (its toolbar rendered behind the tab bar). Rebuilt native:
  share (green) + delete (red) circles above the FAB, "N selected" + an X (cancel)
  in the app bar, instant selection (no per-tap animation), deselect-all stays in
  select mode. Also removed the manual merchant scroll-snap on Add expense so
  SwiftUI's own keyboard avoidance handles it (Contacts/Notes-style). **Standing
  bar: every screen must feel native and responsive — push back on anything that
  isn't, and never block the main thread (no sync-reactions or heavy work mid-edit).**

- **Expense-detail stability + edit autocomplete** (2026-09-02): the single-expense
  screen froze/lagged and could blank its receipt. Cause: `loadAttachment` re-fired
  on every CloudKit `updatedAt` bump and rendered the PDF page **synchronously on
  the main thread** (the `PDF … [-59]` log spam), and `syncFromExpense` overwrote
  fields the user was mid-editing on the same bump. Fixes: attachment decode/render
  moved off the main thread and made PDF-aware (no failed `UIImage(data:)` on a PDF
  key), a transient miss no longer blanks a shown receipt, and `syncFromExpense` is
  skipped while there are unsaved edits. Also added the past-merchant autocomplete
  chips to the edit screen (parity with Add expense).

- **Undo (toast + Recently Deleted bin)** (2026-09-01): a transient bottom "Undo"
  toast after any add (quick-add or statement/photo batch) or delete, reversing by
  toggling `deletedAt` on the recorded ids (`AppState.pendingUndo`, HomeView
  `performUndo`). Soft-delete now keeps the receipt attachment (freed only on a
  permanent delete). New **Recently Deleted** screen (Settings → Recently deleted,
  `RecentlyDeletedView`) restores or permanently removes soft-deleted expenses.

- **Invoice OCR for file/PDF uploads** (2026-09-01): uploads (the `uploadFile`
  path) now run a document scanner instead of the receipt one — camera/library
  stay on receipts. Invoice mode prefers the letterhead vendor (rejecting the
  customer's billing name), a labelled Grand Total / Amount Due over line prices,
  and a concise order/invoice number instead of a line-item dump. Heuristic v1,
  test-driven (`ReceiptOCRServiceTests.testInvoice_scorptec…`); shares the block
  pipeline + `parseAmount`/`extractDate`/`detectCurrency` with the receipt path.
  Standing rule added to CLAUDE.md: no OCR left behind (revise one, check the other).

- **Review polish** (2026-09-01): tag chips on the review list (dot + name in the
  tag colour, matching home); tag picker restyled to match the Tags & Groups screen
  (eyebrow + serif header, shared `TagIconBadge`); FAB "+" glyph 20% larger.

- **Statement review open speed + loading state** (2026-08-27): the review list is
  now a `LazyVStack`, so a 60+ row statement only builds the visible cards instead
  of all of them (the open lag). Plus a brief dimmed "Combobulating expenses"
  spinner overlay when a large list (>12 rows) first appears.

- **File upload behaves like a photo; notes double-tap** (2026-08-27): a picked PDF
  was stored as a raw file, but every display path only renders images, so the file
  page used a separate "file card" and the saved expense showed no receipt when
  opened. Now a PDF upload renders its first page to an image at pick time
  (`AttachmentService.firstPageImage`, a shared helper replacing three copies of the
  rasteriser), so it flows through the exact photo path everywhere (hero, list
  thumbnail, Expense Detail) and OCR runs on it. A PDF→image fallback in the detail
  and edit loaders fixes already-saved PDF expenses too. Also: the global
  tap-to-dismiss-keyboard gesture now skips taps anywhere inside a text input (not
  just its direct view), so double-tap-to-select works in multi-line fields.

- **Statement review: select-all, date fix, bottom bar** (2026-08-27): a
  Select all / Deselect all control in the nav bar; the in-row "Delete expense"
  button removed (unticking is how you exclude a row — swipe-to-delete stays for
  removing one outright); the Add button pinned lower via the container ignoring
  the bottom safe area (`.overlay(.bottom)` + `.ignoresSafeArea(.container,
  edges: .bottom)`, 18pt lift). **Parser date bug:** `DateFormatter` defaults a
  year-less date ("22 AUG") to the year 2000, and the old `< 1970` guard never
  caught it, so every statement date came in as 2000 — now year-less formats are
  handled separately and stamped with the current year (pinned by
  `StatementParserTests.testTextualDate`).
- **Statement review matches the target** (2026-08-27): the Add button floated
  because `safeAreaInset(edge: .bottom)` auto-reserves the home-indicator area and
  any manual padding stacks on top of it, so the button could never get to the
  bottom. Fixed by pinning the bar with `.overlay(alignment: .bottom)` +
  `.ignoresSafeArea(edges: .bottom)` and a fixed 20pt lift, with the list given
  100pt bottom padding to scroll up to meet it. Banner is a neutral grey bubble
  (`E2E6E4`); top fade trimmed 36→20. `StatementImportView` presents the review
  directly (not wrapped in a `ZStack`). Chevron stays pointing down.
- **Multi-expense review polish + home date spacing** (2026-08-27): the shared
  review (`MultiReceiptReviewView`) got an untick that dims content only (fixing
  the red-Delete bleed-through), a swipe-Delete that only renders while swiping,
  no PDF tile on image-less (statement) rows, and a "N found" summary banner —
  all shared, so the photo flow gains them too. The home list date labels now sit
  closer to the expense they head.
- **Import from statement (Pro)** (2026-08-26): a new Add-menu entry (replacing
  "Import from notes", now archived in `Deprecated/`) lets a Pro user upload one
  PDF bank statement. `StatementImportView` reads the transactions in memory
  (`PDFDocument.string`, with a rasterize+Vision fallback for scanned PDFs),
  `StatementParser` turns each debit line into a draft, and they go into the
  **shared** multi-expense review (`MultiReceiptReviewView`, now parameterised by
  `ReviewConfig`) — no image, no attachment, no scan charge, `source:
  "statement_import"`, note "Generated from PDF statement". The PDF is never
  stored. Statement rows show a green PDF tile (`PDFSourceTile`) on the home list.
  The review gained swipe-to-delete + in-row Delete (both flows). Pro-gated at the
  tile (gold crown for free users → upsell); listed on the paywall. Parser has
  `StatementParserTests`; the Pro/privacy invariants are pinned in
  `MonetisationGatingTests`.
- **Scan-charge, export currency, keyboard, symbol fixes** (2026-08-26): (1) OCR no
  longer charges a free scan for a bogus receipt — the single path only charges on a
  positive amount (a 0.00 read is free and no longer auto-fills the field), and the
  bulk path charges only receipts whose OCR actually got an amount (`wasAutoScanned`),
  not one per kept receipt. (2) Export totals are scoped to `activeCurrency` in both
  `GlobalExportSheet` and `TagExportPickerSheet` (a foreign IDR expense no longer
  sums into an AUD total), and the CSV amount column is currency-aware (no `/100` for
  no-minor-unit currencies). (3) The app-wide tap-to-dismiss-keyboard gesture now
  installs from `ContentView.onAppear` — the AppDelegate hook it used never fires
  under SwiftUI's scene lifecycle, so it had never worked. (4) The hero's top-category
  icon no longer passes an emoji tag icon into `systemName` (was logging "no symbol
  found"); it renders the emoji as text.
- **Header polish + interaction batch** (2026-08-26): the hero card gained a
  calendar icon on the period pill, a larger (44pt) top-category icon, and a subtle
  curved bottom wave (`HeroBottomWave`, a lighter-green curve washing the lower
  third) so it reads as part of the app, not a flat card. `HomeToggle` now fills
  brand green when on (white thumb) like a native iOS switch. The pin-to-home sheet
  heading was pulled up (dropped its empty `NavigationStack` bar for an inline
  Done) and its toggle lag fixed (only rescans expenses for the `.recent` sort).
  Pinned-tag hold-to-edit shake is faster (0.1s press). The Home header seam is
  fixed with a soft vertical blend. Added a global tap-to-dismiss-keyboard
  recogniser (`KeyboardDismissGesture`, installed from `AppDelegate`). Enabled the
  `processing` background mode so NSPersistentCloudKitContainer stops logging
  `updateTaskRequest failed` and can finish exporting in the background.
- **Consistent tag rows** (2026-08-26): extracted `TagIconBadge` (in
  `Components.swift`) and pointed the Tags tab, the pin-to-home sheet
  (`AddToHomeBarSheet`) and the filter sheet (`FilterSheet`) at it, so all three
  tag/group lists show the same circular colour+emoji badge, font and spacing. The
  pin sheet's bare dot and the filter sheet's dots/folder glyph are gone.
- **Pinned-tag + edit-tag polish** (2026-08-26): holding a pinned tag on Home now
  shakes + buzzes (keyframe wiggle in `HomeTagBar`) then opens the editor — tuned
  fast (0.22s press, 0.28s to open) so it doesn't feel laggy; the "More" pinned
  card is relabelled "Add tag"; the edit-tag screen (`TagCreationView`) gained a
  live 144pt circular colour+emoji icon preview above the name, a "Show on home"
  toggle with explanatory subtext (persists `showOnHome`), and the colour pill is
  height-matched to the icon pill (both `minHeight: 56`); the Home persistent
  header (search + pinned tags) is now opaque (Rise gradient sampled at its screen
  position, so no seam) so the collapsing hero can't ghost behind it. No new files.
- **Tags tab header + dead-code cull** (2026-08-25): the Tags & Groups header now
  mirrors the Reports page (eyebrow "ORGANISE" + 30pt serif title) and sits at the
  top instead of buried low in the list. Deleted the ponytail-audit dead code:
  `HeroSpendingCard`/`HeroPeriodPage`, five unused `ExpenseCalculations` helpers
  plus the `MonthlyTotal` struct, and `APIService.swift` (with its pbxproj entries).
- **Home hero shows the active currency** (2026-08-25): the big "Total spent" total
  used a hardcoded `$` and Western digit grouping, so a filtered INR total read as
  `$608,600` instead of `₹6,08,600`. Now uses the active currency's symbol, decimals
  and locale grouping via a shared `CurrencyFormatter.groupedWhole` helper (the
  period-detail total routes through it too). The export sheet's total still does
  this — folded into open item 4.
- **Monthly report polish** (2026-08-25): the period detail (opened from the Home
  hero) now pages months by swiping the By Week chart; category rows slide out from
  behind the header instead of ghosting over it; the period title is more
  prominent; the share button and the two sheet close buttons are normalised to the
  36pt icon-button standard; the selected pinned tag on Home fills dark Tally green.
- **Currency consolidation + SKAdNetwork** (`5e0a115`, `b939b15`, 2026-08-25):
  `PeriodDetailView` summed `amountCents` across currencies (₹608,600 read as
  $608,600). Now scoped to `activeCurrency` via `ExpenseModel.inCurrency` /
  `totalCents(in:)` (in `ExpenseModel.swift`), formatted through `CurrencyFormatter`.
  Added the 8 SKAdNetwork identifiers Google flagged as missing.
- **Home banner relocation + circular tag icons** (`dcc24e7`, `d8d4597`,
  2026-08-25): banner moved from the tab bar to beneath the pinned tags; Tags rows
  show a 34pt circular colour swatch with the tag's emoji.
- **Unified logging** (`36ff57e`, 2026-08-25): see Architecture. `PrivacyInfo.xcprivacy`
  created at `Tally/PrivacyInfo.xcprivacy` (strict no-tracking) but **not yet added
  to the Xcode target** — see Open items.
- Everything through the OCR/merchant/monetisation batch is built and green on the
  Mac (124 tests at last full run).
- **Share-extension activation** (`6c1b08e`): needs a **clean install** to
  re-register. **OCR accuracy, many passes** — see the corpus below (a blank
  merchant is a parser bug, not the Pro gate). Plus Rise gradient, recurring
  filter, share-to-Tally auto-open, shred animation, receipt viewer + lazy
  thumbnails, tag sort, merchant→tag auto-apply, Go Pro pill + daily prompt.

## Open items (prioritised)

1. **Pro is not purchasable.** `com.asimplelife.tally.pro.monthly` doesn't exist in
   App Store Connect, so RevenueCat offerings come back empty every launch and
   subscription revenue is **$0**. Biggest open item. The "offerings empty" log
   error is this, not a bug. Josh will want step-by-step help.
2. **`PrivacyInfo.xcprivacy` not in the target.** Josh must add
   `Tally/PrivacyInfo.xcprivacy` to the Tally target in Xcode (or register in
   pbxproj). Apple requires it for AdMob + RevenueCat at submission.
3. **Regional compliance / ad consent (GDPR).** No Google UMP consent flow;
   `banner.load(GADRequest())` defaults to personalised ads. Strict path: UMP
   consent + non-personalised fallback (no IDFA, `NSPrivacyTracking` false, no ATT).
   Needs the GoogleUserMessagingPlatform SPM package (Josh, in Xcode) then a short
   consent call at launch. App Store privacy labels also owed. Data sovereignty is
   otherwise strong by design (on-device + user's private iCloud, no Tally backend).
4. **Export.** RESOLVED (2026-08-26): export totals are now scoped to `activeCurrency`
   in both `GlobalExportSheet` and `TagExportPickerSheet` (option (a)), and the CSV
   amount column is currency-aware (no `/100` for no-minor-unit currencies). The CSV
   already includes a populated `tags` column. **Still open:** the "Export as PDF"
   action is a `showToast("PDF export coming soon")` stub — the multi-expense PDF
   report is not built. The single-expense share PDF/image (`ExpenseExportService`)
   is real and already includes tags.
5. **Tags tab has no ad** after the 2026-08-25 banner move. Decide whether it needs
   one (e.g. below the Add tag / Add folder buttons) or stays ad-free.
6. **CloudKit** is enabled (`TallyApp.cloudKitEnabled = true`). No store-version
   mechanism — SwiftData does automatic lightweight migration. A failed migration
   throws → `fatalError` → crash; recovery is delete + reinstall. Anything riskier
   than a defaulted property needs a real `VersionedSchema`/`MigrationPlan`.
7. **TestFlight**: needs a privacy-policy URL and export-compliance answer
   (`ITSAppUsesNonExemptEncryption = NO`). AdMob is already test units in DEBUG.
9. **Sheet "already presenting" storm — partially fixed.** The concrete user-facing
   symptom (2026-08-27, Josh: a tag on the Tags & Groups page opens then instantly
   dismisses on the *first* tap, works on the second) is fixed: the tag/group sheet
   was attached to a recycling List row inside `TagsAndGroupsManagementRows`; it now
   lives on the stable List container in `TagsTabView` (state lifted, `TagSheet`
   enum moved to file scope). **Still watch:** the log also shows the storm after an
   OCR scan (the UIKit `reviewHostingController` full-screen present colliding with a
   SwiftUI sheet) — likely a proactive prompt presenting while the review is up.
   Reproduce that path before declaring it closed.
8. **Deferred debt:** bulk-import `TagLinkPickerSheet` restyle; ~538 hardcoded
   `Color(hex:)` literals with tokens in `DesignSystem.swift`. (The 2026-08-25
   ponytail audit's dead code — `HeroSpendingCard`/`HeroPeriodPage`, the unused
   `ExpenseCalculations` helpers, `APIService.swift` — has been deleted;
   `ExportExpenseSheet`/`ExportView` no longer exist and were never real.)

## OCR regression testing (read before touching the scanner)

OCR is **metered** — 10 successful scans/month free, a scan counts only if it
extracted an **amount**. A wrong amount fails the user; an empty one silently
refunds their scan. **A reported blank merchant is a parser bug, not the Pro gate.**
The `ocr-regression` skill drives this workflow.

### The loop (ongoing and accumulating, by design)

1. Josh scans a receipt and it's wrong — he sends the photo + a screenshot of what
   Tally produced (+ the `OCR|` console dump for merchant misses).
2. Diagnose from the pair: which line the parser latched onto and why.
3. **Pin it as a test *before* fixing.**
4. Fix with a **general heuristic** for a class of receipts, never a one-off hack;
   re-check the existing corpus by hand.
5. Add a row to the corpus below **and** in the skill file.
6. Josh builds and re-scans on the Mac to confirm. Never call an OCR fix verified
   until he confirms a green run.

### Hard rules

- **Never change `ReceiptOCRService.swift` without adding/updating a test for the
  receipt that motivated it.**
- **A passing synthetic test does not mean the receipt works.** `blk()` gives every
  block the same height; real geometry hides bugs. Reproduce the **real** geometry
  (explicit `CGRect`s when heights matter) and add a **degraded** variant with only
  the lines that plausibly survived OCR.
- **Returning `nil` beats a confident wrong answer.**

### The corpus (add a row per reported receipt)

| Receipt | Trap it guards against | Correct |
|---|---|---|
| Hendry's | tax line "$0.54" misread as "$54"; total restated on card line | $5.89 |
| Sushia | "Sale Staff: Melissa" as merchant; tax line; tilted photo | $30.90 |
| Paris | French "MONTANT DU" / TVA / HT; euro currency | €81.50 |
| Bunnings | "GST included in the total"; date misread as future (2028) | $38.80 |
| Monos | "TOTAL SAVINGS"; "Total (GST incl.)" is the real total | $300.00 |
| KFC | item name "15 Wicked Wings $10" repeats the value 10 | $26.55 |
| Woolworths | savings + per-kg rates ("@ $33.00/kg") outrank the small-print TOTAL; label and amount are separate blocks | $49.49 |
| Woolworths (header) | large wordmark + swirl logo, script tagline, address/ABN beneath; a stray `@` from the logo tripped the email pattern | merchant `Woolworths` |
| Liquorland | letter-spaced wordmark OCR'd low-confidence, so "TOTAL (Inc GST)" was taken as merchant. Total/structural labels now rejected as merchant | merchant not a total line |
| Cherry Beans | receipt floats mid-frame; wordmark fell below the image-relative top gate. largestHeaderText now uses the receipt-relative top | merchant `Cherry Beans Kellyvil` |
| Deus (Bali, IDR) | grouped thousands "655,000" truncated by the cents regex; stylised logo OCR'd as `€`; currency now falls back to the country in the letterhead | $4,640,000 IDR, `PT. Deus Ex Machina Indonesia` |
| Woolworths (store line) | `WOOLWORTHS 1659 KELLYVILLE NSW` — name+store-number block rejected for a digit, so the suburb won | merchant `WOOLWORTHS` |
| Berry General Store | wordmark split across stacked lines; a lone "NSW" won. Reconstruct stacked all-caps header lines; a recurring 2+ word phrase beats a one-word token | merchant `BERRY GENERAL STORE`; note `Ricotta Hotcakes ×2` |
| Maw Maw (Kellyville) | bold "MAW MAW" OCR-garbled to "MAH MAN"; two address lines out-ranked it. Fixes: (1) a street/centre-suffix phrase (GROVE/COURT/ROAD…) gets no recurring boost (suffix only — a suburb test would break Berry); (2) `dropTrailingStoreNumber` no longer strips a postcode after a state ("KELLYVILLE NSW 2154" stayed disqualified instead of becoming the recurring "KELLYVILLE NSW"); plus `stackedWordmark` no longer glues a 4+-word slogan onto the name ("LIQUORLAND"+"SAY NO TO PLASTIC BAGS"). Header ("MAH MAN") then unusable, so the name is recovered from the footer return-address "Maw Maw Kellyville" (suburb stripped) via `footerBusinessName`, which fires only when a "<suburb> STATE postcode" line exists and is ranked below the wordmark passes (a clear header always wins). | merchant `Maw Maw` ($46.70) |

### Recurring trap families

- **Non-total lines that look total-ish**: tax/GST, savings, specials, change,
  rounding, tips. Excluded by pattern.
- **Coincidental repeats** can fake cross-confirmation — the subtotal floor guards
  it (a total is always ≥ the subtotal).
- **Legibility bias**: large promo print OCRs more reliably than the small monospace
  total on a long, angled receipt.
- **Unit rates, not amounts**: "@ $33.00/kg", "Qty 2 @ $7.00 each".
- **Locale/label variance**: French (MONTANT DU, TTC, TVA, HT), AU/UK phrasing.
- **Exclusion is a property of the LINE, not the block** — use `isExcluded(_:in:)`.
- **"Same line" is not one test.** `sameLine` (÷ the *shorter* box) for amounts;
  `sharesPrintedLine` (÷ the *taller* box, ≤2× height ratio, horizontally disjoint)
  for merchant pairing.

### Adding a new receipt

1. `func test<Merchant>_<trap>()` in `ReceiptOCRServiceTests.swift`.
2. Lay out with `blk(_:x:y:)` — label and right-aligned amount as **separate blocks**
   sharing a `y`. Vision `y` is normalised, **increases upward** (top ≈ 0.9). Explicit
   `CGRect`s when relative text size is part of the bug.
3. Assert the amount via `amount(_:from:)`; assert merchant/currency/date where used.
4. Add a corpus row here **and** in the skill file.
5. Fix generally; note the class in a code comment. Re-check the corpus by hand.
   Never call it verified until Josh confirms a green run.

## Smoke-test flows (manual QA on device)

Repeatable flows Josh runs on the iPhone after pulling `dev`, then relays pass/fail
by number. Kept current here as features change. Each flow is steps → **expected**.
The **Core** set is the after-every-change smoke test; the rest run when their area
was touched.

### Core (run after every change)

1. **Quick add** — FAB → Quick add. Type an amount, leave vendor blank →
   **Save is disabled.** Add a vendor → **Save enables.** Tap into notes, then tap
   away → **focus stays put; the keypad does not jump back to amount.** Save →
   **expense appears at the top of the home list with the right amount and vendor.**
2. **Edit an expense** — tap an expense → change amount, vendor, date → Save →
   **the row reflects every change; totals update.**
3. **Delete (swipe)** — swipe a home row left → **deep-red cell, white bin only** →
   release → **row deletes, shred animation plays, totals update.**
4. **Home layout** — scroll the list → **hero collapses smoothly; date headers are
   the darker grey; a year boundary shows a centred year; spacing looks even.**
5. **Filter** — tap a pinned tag in the home bar, then a period → **list and hero
   total scope to that tag/period; currency symbol and grouping are correct.**

### Capture

6. **Snap a receipt** — FAB → Snap a receipt → photograph one → **OCR fills amount,
   vendor, date; wrong guesses fixable; Save writes it with the receipt viewable in
   detail.** (Report a wrong scan with photo + screenshot → OCR corpus.)
7. **Photo library (multi)** — FAB → From library → pick 2–3 → **review list builds
   quickly; each row editable; tick/untick; swipe-to-delete; Save adds only ticked.**
8. **Upload a file** — FAB → Upload file → pick a PDF → **it becomes a receipt image
   (page 1); Save writes an expense whose detail shows that image, not a file card.**

### Statement import (Pro)

9. **Gate** — Force Pro OFF, FAB → Import from statement → **gold crown; tapping
   shows the Pro upsell, does not open the flow.**
10. **Import** — Force Pro ON → pick a text-layer bank PDF → **"Tallying everything
    up for you" loader on a big list, then debit rows only (credits excluded), each
    with its own date.** Add a tag to a row → **the tag picker opens (not a blank
    white sheet).** Swipe-delete a row; Save → **expenses created with the green PDF
    tile on the home list and no stored PDF.**

### Tags, currency, export, Pro

11. **Tagging** — on any expense, Add tag → pick one; Change → pick another;
    Add tag / Add folder → create one → **selection applies and persists.**
12. **Currency** — Settings → change default currency → **home hero and lists show
    the new symbol and grouping; no mixed-currency totals.**
13. **Export** — filtered export (CSV) from a scoped list → **file contains only the
    scoped rows.** Global export (Pro, PDF) → **PDF generates; gated for free users.**
14. **Pro paywall** — open the paywall → **lists the built features incl. PDF export
    and Import from statement; Force Pro toggle flips entitlement in debug.**

### First run & sync

15. **Onboarding** — fresh install → **onboarding + currency setup complete cleanly
    into an empty home.**
16. **Sync** — add an expense on one device → **it appears on a second signed-in
    device (CloudKit) within a short delay.**
