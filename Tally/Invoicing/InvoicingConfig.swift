import Foundation

enum InvoicingConfig {
    /// Maximum number of invoices a free user can create per calendar month.
    /// Change this single value to adjust the free tier limit globally.
    static let freeInvoiceLimit: Int = 2
}
