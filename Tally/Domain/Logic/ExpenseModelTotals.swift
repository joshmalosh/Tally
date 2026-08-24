import Foundation

/// Currency-safe aggregation for the persisted expense model.
///
/// The app has no FX, so a total across mixed currencies is meaningless. Every
/// total, chart and summary is scoped to a single currency — usually
/// `appState.activeCurrency`. Use these instead of a raw `reduce` so the whole
/// app agrees on the same number: reports, the home hero, period detail and any
/// on-screen summary all consolidate the same way.
extension Sequence where Element == ExpenseModel {
    /// The subset in one currency.
    func inCurrency(_ currency: String) -> [ExpenseModel] {
        filter { $0.currency == currency }
    }

    /// Sum of minor units in one currency; expenses in other currencies
    /// contribute nothing, never silently added at face value.
    func totalCents(in currency: String) -> Int {
        reduce(0) { $0 + ($1.currency == currency ? $1.amountCents : 0) }
    }
}
