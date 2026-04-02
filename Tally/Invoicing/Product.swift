import Foundation
import SwiftData

enum PricingType: String, Codable, CaseIterable {
    case flatRate    = "Flat rate"
    case perPerson   = "Per person"
    case perHour     = "Per hour"
    case perDay      = "Per day"

    var unitLabel: String {
        switch self {
        case .flatRate:  return ""
        case .perPerson: return "person"
        case .perHour:   return "hr"
        case .perDay:    return "day"
        }
    }
}

@Model
final class Product {
    var id: UUID
    var name: String
    var productDescription: String
    var pricingType: PricingType
    var rate: Double       // price per unit (per person, per hour, per day, or flat)
    var createdAt: Date

    var company: Company?

    init(
        name: String,
        productDescription: String = "",
        pricingType: PricingType = .flatRate,
        rate: Double = 0.0
    ) {
        self.id = UUID()
        self.name = name
        self.productDescription = productDescription
        self.pricingType = pricingType
        self.rate = rate
        self.createdAt = Date()
    }
}
