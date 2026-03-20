# Tally — Project Brief

## 0) One-Paragraph Summary

Tally is a modern, minimal, premium expense tracking app for individuals and small businesses. Users snap receipts, upload invoices, log manual expenses, tag them with unlimited custom tags, and export clean CSV and PDF files. It runs on iOS (SwiftUI) with data stored entirely in the user's iCloud via CloudKit — no proprietary backend, no server-side user data. Free users get unlimited expenses, unlimited uploads, unlimited tags, and 1 CSV export per month with banner ads; Pro ($4.99/month) removes ads and unlocks unlimited CSV exports, PDF export, monthly auto-export, OCR auto-fill, and advanced filters. It is NOT accounting software, NOT a reimbursement workflow, and NOT a finance dashboard — it is a capture + tag + export system.

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
- OCR auto-fill from receipts (Pro)
- Simple search
- Advanced filtering (Pro)

### User Modes

| Capability | Free | Pro ($4.99/mo) |
|---|---|---|
| Manual expense entry | Unlimited | Unlimited |
| Receipt uploads | Unlimited | Unlimited |
| Custom tags | Unlimited | Unlimited |
| Viewing / editing / deleting | Unlimited | Unlimited |
| Bulk delete | Yes | Yes |
| iCloud sync | Yes | Yes |
| CSV export | 1 per calendar month | Unlimited |
| PDF export | No (upsell) | Yes |
| Monthly auto-export | No | Yes |
| OCR auto-fill | No (upsell) | Yes |
| Advanced filters | No (upsell) | Yes |
| Ads | Banner only | None |

See `MONETISATION_BRIEF.md` for full monetisation rules, ad placement, and upgrade prompt behavior.

### Ad Rules
- Banner ad at bottom of Home screen and Add Expense screen.
- Add Expense: hide banner while keyboard is visible, re-show on dismiss.
- NO ads in: tag sheet, export sheet, settings, confirmation states.
- No interstitial ads. No rewarded ads. No inline sponsored rows.
- Pro users: zero ads, receipt-verified via StoreKit 2.

### Upgrade Prompt Rules
- Trigger on: second CSV export in a month, PDF/OCR/Advanced Filters tap (free user), settings.
- Tone: calm, not aggressive. No countdown timers. No urgency.
- CTA: "Upgrade to Pro" in sheets, "Go Pro" in settings.
- Dismiss: "Not now".

Pro removes friction. It does not unlock complexity.

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
| OCR auto-fill | Blocked, show upsell | Allowed |
| Advanced filters | Blocked, show upsell | Allowed |
| Monthly auto-export | Not available | Automatic |
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

### Phase 1 — Foundation + Core Flow (Current)
1. Project setup: iOS (SwiftUI + SwiftData + CloudKit).
2. Design system: colors, typography, spacing, core components.
3. Data model: SwiftData models with CloudKit sync.
4. Domain logic: expense CRUD, tag management, monthly totals.
5. Core screens: Home, Add Expense (manual), Expense Detail, Settings.
6. iCloud sync: SwiftData + CloudKit container.
7. CSV export (1/month free, unlimited Pro).
8. Ad integration (AdMob banner).
9. Subscription: StoreKit 2.

### Phase 2 — Feature Depth
1. Camera capture + receipt upload flow.
2. PDF export (Pro).
3. OCR auto-fill via Vision framework (Pro).
4. Advanced filters (Pro).
5. Monthly auto-export (Pro).
6. Usage analytics.

### Phase 3 — Growth
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
| OCR (Phase 2) | Apple Vision framework | On-device text recognition. No API cost. |

### What was removed
| Layer | Removed | Reason |
|---|---|---|
| Backend | Node.js + Express + PostgreSQL | No proprietary server needed. iCloud handles storage + sync. |
| Object storage | AWS S3 / Cloudflare R2 | Receipts stored as CKAsset in user's iCloud. |
| Web app | Next.js + React | Deprioritised. iCloud-native iOS is the focus. |
| Web subscriptions | Stripe | No web app in scope. |
| Custom auth | JWT + OAuth | iCloud identity replaces custom auth. |
| Hosting | Vercel + Railway | No server infrastructure to host. |
