import Foundation
import SwiftData

@Model
final class LineItem {
    var id: UUID
    var itemDescription: String
    var pricingType: PricingType
    var quantity: Double       // number of units (people, hours, days) or 1 for flat rate
    var rate: Double           // price per unit
    var sortOrder: Int

    var invoice: Invoice?

    init(
        itemDescription: String = "",
        pricingType: PricingType = .flatRate,
        quantity: Double = 1,
        rate: Double = 0.0,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.itemDescription = itemDescription
        self.pricingType = pricingType
        self.quantity = quantity
        self.rate = rate
        self.sortOrder = sortOrder
    }

    var lineTotal: Double {
        quantity * rate
    }

    /// Display string for quantity label, e.g. "25 people", "3 hrs", "1"
    var quantityLabel: String {
        switch pricingType {
        case .flatRate:  return quantity == 1 ? "1" : String(format: "%.0f", quantity)
        case .perPerson: return String(format: "%.0f %@", quantity, quantity == 1 ? "person" : "people")
        case .perHour:   return String(format: "%.1f %@", quantity, quantity == 1 ? "hr" : "hrs")
        case .perDay:    return String(format: "%.0f %@", quantity, quantity == 1 ? "day" : "days")
        }
    }
}
