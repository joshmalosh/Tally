import SwiftUI
import SwiftData

struct InvoicesListView: View {
    @EnvironmentObject var invoicingState: InvoicingState

    private var filteredInvoices: [Invoice] {
        guard let company = invoicingState.activeCompany else { return [] }
        let all = company.invoices.sorted { $0.createdAt > $1.createdAt }
        switch invoicingState.statusFilter {
        case .all:     return all
        case .draft:   return all.filter { $0.status == .draft }
        case .sent:    return all.filter { $0.status == .sent }
        case .paid:    return all.filter { $0.status == .paid }
        case .overdue: return all.filter { $0.status == .overdue }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status filter tabs
            HStack(spacing: 0) {
                ForEach(InvoiceStatusFilter.allCases, id: \.self) { filter in
                    Button {
                        invoicingState.statusFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                invoicingState.statusFilter == filter
                                ? Color(hex: "2F402E")
                                : Color.clear
                            )
                            .foregroundStyle(
                                invoicingState.statusFilter == filter
                                ? Color.white
                                : Color(hex: "8F9E94")
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Divider shadow
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 3)

            if filteredInvoices.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                    Text("No invoices")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredInvoices, id: \.id) { invoice in
                        InvoiceRowView(invoice: invoice)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InvoiceRowView: View {
    let invoice: Invoice

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(invoice.status == .draft
                          ? Color(hex: "F0EDEA")
                          : Color(hex: "EBF2EE"))
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundStyle(invoice.status == .draft
                                     ? Color(hex: "8F9E94")
                                     : Color(hex: "2C4A35"))
            }
            .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.client?.name ?? "Unknown client")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                HStack(spacing: 4) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8F9E94"))
                    Text("·")
                        .foregroundStyle(Color(hex: "C4BFB9"))
                    Text(invoice.status == .paid
                         ? "Paid \(invoice.paidAt?.formatted(date: .abbreviated, time: .omitted) ?? "")"
                         : "Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }

            Spacer()

            // Amount + status
            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.grandTotal, format: .currency(code: "AUD").presentation(.narrow))
                    .font(.system(size: 15, weight: .semibold).monospaced())
                    .foregroundStyle(Color(hex: "1C1C1E"))
                InvoiceStatusPill(status: invoice.status)
            }
        }
        .padding(.vertical, 9)
    }
}

struct InvoiceStatusPill: View {
    let status: InvoiceStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .clipShape(Capsule())
    }

    private var pillBackground: Color {
        switch status {
        case .draft:   return Color(hex: "F0EDEA")
        case .sent:    return Color(hex: "E8F0EA")
        case .paid:    return Color(hex: "DDF2E6")
        case .overdue: return Color(hex: "FEF0F0")
        }
    }

    private var pillForeground: Color {
        switch status {
        case .draft:   return Color(hex: "8F9E94")
        case .sent:    return Color(hex: "2C4A35")
        case .paid:    return Color(hex: "1A6B3A")
        case .overdue: return Color(hex: "C0392B")
        }
    }
}
