import Foundation
import SwiftData

@Model
final class InvoiceFee {
    var id: UUID
    var name: String           // e.g. "Credit card surcharge", "Early payment discount"
    var isPercentage: Bool     // true = value is a rate (e.g. 0.035), false = fixed amount
    var value: Double          // percentage as decimal (0.035) or fixed dollar amount
    var isDiscount: Bool       // true = subtracted, false = added
    var sortOrder: Int

    var invoice: Invoice?

    init(
        name: String,
        isPercentage: Bool = true,
        value: Double = 0.0,
        isDiscount: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.isPercentage = isPercentage
        self.value = value
        self.isDiscount = isDiscount
        self.sortOrder = sortOrder
    }

    /// Calculated dollar amount given a subtotal.
    func amount(for subtotal: Double) -> Double {
        isPercentage ? subtotal * value : value
    }

    /// Formatted display string for the fee value, e.g. "3.5%" or "$100.00"
    var displayValue: String {
        if isPercentage {
            return String(format: "%.1f%%", value * 100)
        } else {
            return String(format: "$%.2f", value)
        }
    }
}
