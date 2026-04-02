import SwiftUI

enum HomeMode: Hashable {
    case expenses
    case invoices
}

enum InvoiceTotalsMode: Hashable {
    case invoiced
    case received
}

enum InvoiceStatusFilter: String, CaseIterable {
    case all      = "All"
    case draft    = "Draft"
    case sent     = "Sent"
    case paid     = "Paid"
    case overdue  = "Overdue"
}

@MainActor
class InvoicingState: ObservableObject {
    @Published var homeMode: HomeMode = .expenses
    @Published var totalsMode: InvoiceTotalsMode = .invoiced
    @Published var activeCompany: Company? = nil
    @Published var statusFilter: InvoiceStatusFilter = .all
    @Published var isProfilePanelOpen: Bool = false

    /// Returns true if the user has at least one company set up.
    /// The mode toggle only appears when this is true.
    var hasCompany: Bool {
        activeCompany != nil
    }
}
