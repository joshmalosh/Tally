import SwiftUI
import SwiftData

struct ProfilePanelView: View {
    @EnvironmentObject var invoicingState: InvoicingState
    @Environment(AppState.self) private var appState
    @Query(sort: \Company.createdAt) private var companies: [Company]

    @State private var expandedCompanyID: UUID? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            // Dimmed background — tapping closes panel
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        invoicingState.isProfilePanelOpen = false
                    }
                }

            // Panel
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("Your companies")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .padding(.horizontal, 18)
                    .padding(.top, 56)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(companies, id: \.id) { company in
                            CompanyPanelRow(
                                company: company,
                                isActive: invoicingState.activeCompany?.id == company.id,
                                isExpanded: expandedCompanyID == company.id,
                                onSelect: {
                                    invoicingState.activeCompany = company
                                    expandedCompanyID = company.id
                                },
                                onToggleExpand: {
                                    expandedCompanyID = expandedCompanyID == company.id ? nil : company.id
                                }
                            )
                        }

                        // Add company
                        Button {
                            // TODO Sprint 5: open company setup sheet
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: "F0F4F1"))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: "2F402E"))
                                }
                                Text("Add company")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "2F402E"))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, 18)

                // Settings link
                Button {
                    invoicingState.isProfilePanelOpen = false
                    appState.showingSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "8F9E94"))
                        Text("Settings")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .padding(.bottom, 16)
            }
            .frame(width: 250)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }
}

struct CompanyPanelRow: View {
    let company: Company
    let isActive: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Company row
            HStack(spacing: 10) {
                CompanyAvatarView(company: company, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color(hex: isActive ? "1C1C1E" : "4A5E50"))
                    if isActive {
                        Text("Active")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                }
                Spacer()

                if isActive {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "2F402E"))
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isActive ? Color(hex: "F0F4F1") : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            // Expanded sub-rows
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Clients
                    Button {
                        onToggleExpand()
                        // TODO Sprint 5: show client list for this company
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.2")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .frame(width: 20)
                            Text("Clients")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "4A5E50"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "C4BFB9"))
                        }
                        .padding(.leading, 46)
                        .padding(.trailing, 18)
                        .padding(.vertical, 10)
                    }

                    // Edit company
                    Button {
                        onToggleExpand()
                        // TODO Sprint 5: open company edit sheet
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .frame(width: 20)
                            Text("Edit \(company.name)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "4A5E50"))
                            Spacer()
                        }
                        .padding(.leading, 46)
                        .padding(.trailing, 18)
                        .padding(.vertical, 10)
                    }
                }
                .background(Color(hex: "F8F6F3"))
            }

            Divider()
                .padding(.horizontal, 18)
        }
    }
}
