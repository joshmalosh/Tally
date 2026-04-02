import Foundation
import SwiftData

@Model
final class Company {
    var id: UUID
    var name: String
    var logoData: Data?
    var abn: String
    var taxRate: Double        // e.g. 0.10 for 10% GST, 0.0 if not registered
    var bankDetails: String    // free-text payment instructions, pre-fills invoice notes
    var invoiceCounter: Int    // auto-increments per invoice created under this company
    var defaultFeeEnabled: Bool
    var defaultFeeName: String     // e.g. "Credit card surcharge"
    var defaultFeePercent: Double  // e.g. 0.035 for 3.5%
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Client.company) var clients: [Client]
    @Relationship(deleteRule: .cascade, inverse: \Product.company) var products: [Product]
    @Relationship(deleteRule: .cascade, inverse: \Invoice.company) var invoices: [Invoice]

    init(
        name: String,
        abn: String = "",
        taxRate: Double = 0.10,
        bankDetails: String = "",
        defaultFeeEnabled: Bool = false,
        defaultFeeName: String = "Credit card surcharge",
        defaultFeePercent: Double = 0.035
    ) {
        self.id = UUID()
        self.name = name
        self.logoData = nil
        self.abn = abn
        self.taxRate = taxRate
        self.bankDetails = bankDetails
        self.invoiceCounter = 0
        self.defaultFeeEnabled = defaultFeeEnabled
        self.defaultFeeName = defaultFeeName
        self.defaultFeePercent = defaultFeePercent
        self.createdAt = Date()
        self.clients = []
        self.products = []
        self.invoices = []
    }

    /// Returns the next formatted invoice number and increments the counter.
    func nextInvoiceNumber() -> String {
        invoiceCounter += 1
        return String(format: "INV-%04d", invoiceCounter)
    }
}
