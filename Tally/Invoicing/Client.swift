import Foundation
import SwiftData

@Model
final class Client {
    var id: UUID
    var name: String
    var companyName: String
    var email: String
    var addressLine1: String
    var addressLine2: String
    var city: String
    var stateOrRegion: String
    var postcode: String
    var country: String
    var notes: String
    var createdAt: Date

    var company: Company?

    init(
        name: String,
        companyName: String = "",
        email: String = "",
        addressLine1: String = "",
        addressLine2: String = "",
        city: String = "",
        stateOrRegion: String = "",
        postcode: String = "",
        country: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.companyName = companyName
        self.email = email
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.stateOrRegion = stateOrRegion
        self.postcode = postcode
        self.country = country
        self.notes = notes
        self.createdAt = Date()
    }

    /// Single-line address string for invoice PDF display.
    var formattedAddress: String {
        [addressLine1, addressLine2, city, stateOrRegion, postcode, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
