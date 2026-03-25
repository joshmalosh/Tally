# Tally — Monetisation Brief

This is the single source of truth for Tally's monetisation model. If anything in `PROJECT_BRIEF.md` or other documents conflicts with this file, this file wins.

Last updated: 2026-02-28

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
| Monthly auto-export | No | Yes |
| OCR auto-fill (receipt scan) | No | Yes |
| Advanced filters | No | Yes |
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

### Monthly Auto-Export (Pro only)

- Automatically generates and saves a CSV/PDF of the current month's expenses.
- Delivered to user's Files/iCloud on the 1st of each month.
- Phase 2 feature.

### Export copy

- Use "Export as CSV" and "Export as PDF".
- Do NOT use "Export to Accountant", "accountant-ready", or any accountant framing.
- Keep tone simple and professional.

---

## Ad Placement Rules

### Where ads appear

| Location | Ad Type | Notes |
|---|---|---|
| Home screen | Banner (bottom) | Always visible for free users |
| Add Expense screen | Banner (bottom) | Below Notes, above safe area. See keyboard rules below. |

### Where ads do NOT appear

- Tag bottom sheet
- Export bottom sheet
- Settings screen
- Confirmation states
- Any modal/sheet overlay
- Expense list (no inline sponsored rows)

### Ad types

- **Banner ads only.** Fixed position at screen bottom.
- **No interstitial ads.**
- **No rewarded ads.**
- **No inline sponsored rows** in the expense list.

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

## OCR Auto-Fill (Pro Feature)

### Current state: Placeholder

OCR is a Pro-only feature. Phase 1 is the monetisation gate only — full implementation follows.

### Settings UI

Add a toggle row in Settings under a "Pro Features" section:

```
Receipt auto-fill (OCR)
Automatically extract amount and merchant from receipts.
```

- If Pro: toggle is functional (once implemented).
- If Free: show lock icon. Tapping shows the standard upgrade sheet.

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
| Tap OCR toggle (free user) | Standard upgrade sheet |
| Tap Advanced Filters (free user) | Standard upgrade sheet |
| Settings "Go Pro" row | Subscription view |

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
