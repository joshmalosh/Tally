# Tally — Monetisation Brief

This is the single source of truth for Tally's monetisation model. If anything in `PROJECT_BRIEF.md` or other documents conflicts with this file, this file wins.

Last updated: 2026-07-12

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
| Home / Reports / Tags | Banner (bottom, above tab bar) | Always visible for free users |
| Home expense list | Inline banner | One below the pinned tags above the first expense, then one after every 10th expense |
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
- User always reviews and confirms before saving.

### Implementation approach (when built)

- **On-device only.** Apple Vision framework (`VNRecognizeTextRequest`).
- No third-party API. No cloud dependency. No per-scan cost.
- Flow: capture receipt → Vision extracts text → parse for amount + merchant → auto-fill form fields.
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

Used for feature-locked items (PDF, OCR, Advanced Filters):

```
Title: Pro Feature

Body: [Feature name] is available with Tally Pro.
      Unlock unlimited exports, PDF reports, OCR auto-fill,
      and advanced filters.

Buttons:
  [Upgrade to Pro]
  [Not now]
```

---

## Subscription Management

- iOS: StoreKit 2 (`com.tally.pro.monthly`).
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

## Changelog

| Date | Change |
|---|---|
| 2026-02-28 | Initial brief: CSV 1/month, PDF Pro, no interstitials, banner only |
| 2026-02-28 | Upload caps removed (unlimited for all). iCloud-only storage. Monthly auto-export confirmed as Pro. Bulk delete ungated. Add Expense ad strategy refined (keyboard hiding, 3-expense threshold). Storage caps removed (user-owned iCloud). No Stripe/web subscription for now. |
| 2026-07-12 | 15/month free expense cap removed from app (violated this brief; brief confirmed as source of truth). Pro benefits card documented: proactive prompt on 3rd/6th/9th expense per month, max 3/month, never mid-batch. |
| 2026-07-20 | **Audit of code vs. brief found six divergences; resolved as follows.** (1) CSV free allowance was 2 in one place and 0 in four others — now 1 everywhere, enforced via `canExportCSV` on all six export paths. (2) OCR changed from Pro-only field gating to a **10 successful scans/month** quota with full extraction for everyone. (3) **"Advanced filters" deleted** — the label was never a real feature and no code ever gated it; it was a false paywall claim. (4) **Monthly auto-export deleted** from code, docs and paywall — never built, and it overcomplicates the app. (5) Ads extended to every full screen incl. Expense Detail and inline in the expense list; the old "no inline sponsored rows" rule is superseded. (6) Interstitials reconsidered and again rejected. Added: Go Pro pill in the Home header, and a daily upgrade prompt (every 3 days, 3-day grace). |
