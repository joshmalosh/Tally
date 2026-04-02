import Foundation
import SwiftData

enum InvoiceStatus: String, Codable, CaseIterable {
    case draft    = "Draft"
    case sent     = "Sent"
    case paid     = "Paid"
    case overdue  = "Overdue"
}

@Model
final class Invoice {
    var id: UUID
    var invoiceNumber: String
    var reference: String
    var issueDate: Date
    var dueDate: Date
    var status: InvoiceStatus
    var notes: String          // payment instructions shown on PDF
    var taxRate: Double        // snapshot of company tax rate at time of creation
    var createdAt: Date
    var sentAt: Date?
    var paidAt: Date?

    var company: Company?
    var client: Client?

    @Relationship(deleteRule: .cascade, inverse: \LineItem.invoice) var lineItems: [LineItem]
    @Relationship(deleteRule: .cascade, inverse: \InvoiceFee.invoice) var fees: [InvoiceFee]

    init(
        invoiceNumber: String,
        reference: String = "",
        issueDate: Date = Date(),
        dueDate: Date,
        taxRate: Double = 0.0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.invoiceNumber = invoiceNumber
        self.reference = reference
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.status = .draft
        self.notes = notes
        self.taxRate = taxRate
        self.createdAt = Date()
        self.sentAt = nil
        self.paidAt = nil
        self.lineItems = []
        self.fees = []
    }

    // MARK: - Computed totals

    var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    var feesTotal: Double {
        fees.reduce(0) { total, fee in
            let amount = fee.isPercentage
                ? subtotal * fee.value
                : fee.value
            return fee.isDiscount ? total - amount : total + amount
        }
    }

    var taxAmount: Double {
        (subtotal + feesTotal) * taxRate
    }

    var grandTotal: Double {
        subtotal + feesTotal + taxAmount
    }

    /// Returns true if this invoice should count against the free monthly limit.
    static func invoiceCountThisMonth(in context: ModelContext) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.createdAt >= start }
        )
        return (try? context.fetch(descriptor))?.count ?? 0
    }
}
