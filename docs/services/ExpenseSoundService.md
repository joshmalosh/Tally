## Purpose

Plays the "coin drop" sound and success haptic when an expense is logged, and defines the `expenseLogged` / `expenseDeleted` notification names used to drive related UI (e.g. shred animation on Home).

## Public surface

- `NSNotification.Name.expenseLogged` (`Tally/Services/ExpenseSoundService.swift:9`) — posted when an expense is saved; `userInfo: ["expenseId": String]`.
- `NSNotification.Name.expenseDeleted` (`:13`) — posted when an expense is deleted.
- `final class ExpenseSoundService`, singleton `static let shared` (`:18-19`).
- `func playExpenseLogged()` (`:42`) — rewinds and plays the bundled coin sound, fires a `.success` haptic, re-primes the haptic engine for next use.

## Depends on

`AVFoundation` (`AVAudioPlayer`, `AVAudioSession`), `UIKit` (`UINotificationFeedbackGenerator`). Bundled resource: `Coin_Expense_Logged.mp3`.

## Used by

- `Tally/Views/AddExpense/AddExpenseView.swift`, `Tally/Views/ExpenseDetail/ExpenseDetailView.swift`, `Tally/Views/AddMultipleExpenses/AddMultipleExpensesView.swift`.

## Gotchas

- Audio session category is `.ambient` with `.mixWithOthers` — deliberately respects the ringer/mute switch and never interrupts music/podcasts (`:26-27`).
- If the bundled MP3 resource is missing, `player` stays `nil` and `playExpenseLogged()` silently skips playback but still fires the haptic.
- Haptic generator is pre-warmed in `init()` and re-armed after each play to keep latency low.
