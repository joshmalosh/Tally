import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var startDate: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var endDate: Date = Date()
    @State private var selectedFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var showingProUpsell = false
    @State private var proFeatureName = "Export"

    private var filteredExpenses: [ExpenseModel] {
        activeExpenses.filter { $0.date >= startDate && $0.date <= endDate }
    }

    private var expenseCount: Int { filteredExpenses.count }

    private var totalCents: Int {
        filteredExpenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        dateRangeSection
                        formatSection
                        summarySection
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                }
                .background(Color.surface)

                exportButton
            }
            .navigationTitle("Export your expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingProUpsell) {
                ProFeatureSheet(featureName: proFeatureName)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Date range")
                .font(Fonts.headline(16))
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("From")
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Color.brandPrimary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("To")
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Color.brandPrimary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Format")
                .font(Fonts.headline(16))
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: Spacing.sm) {
                formatOption(
                    format: .csv,
                    title: "CSV",
                    subtitle: "Spreadsheet-compatible data file",
                    proOnly: true
                )
                formatOption(
                    format: .pdf,
                    title: "PDF",
                    subtitle: "Coming soon",
                    proOnly: true
                )
            }
        }
        .padding(Spacing.md)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func formatOption(format: ExportFormat, title: String, subtitle: String, proOnly: Bool) -> some View {
        Button {
            if proOnly && !appState.isPro {
                proFeatureName = format == .csv ? "CSV export" : "PDF export"
                showingProUpsell = true
            } else {
                selectedFormat = format
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selectedFormat == format ? Color.brandPrimary : Color.textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(title)
                            .font(Fonts.body(15))
                            .foregroundStyle(Color.textPrimary)
                        if proOnly && !appState.isPro {
                            Text("PRO")
                                .font(Fonts.caption(10))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.brandPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.brandPrimary, lineWidth: 1)
                                )
                        }
                    }
                    Text(subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(Spacing.md)
            .background(selectedFormat == format ? Color.brandTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Summary")
                .font(Fonts.headline(16))
                .foregroundStyle(Color.textPrimary)

            HStack {
                summaryItem(label: "Expenses", value: "\(expenseCount)")
                Spacer()
                summaryItem(label: "Total", value: CurrencyFormatter.shared.format(cents: totalCents, currencyCode: appState.defaultCurrency))
            }
        }
        .padding(Spacing.md)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(Fonts.headline(18))
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        VStack(spacing: 0) {
            Divider()
            if expenseCount == 0 {
                VStack(spacing: Spacing.sm) {
                    Text("No expenses in this date range")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                    Text("Adjust the dates above or add an expense first.")
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
            } else {
                PrimaryButton(
                    title: isExporting ? "Exporting..." : "Export \(expenseCount) expenses",
                    action: { performExport() },
                    isLoading: isExporting
                )
                .disabled(isExporting)
                .padding(Spacing.md)
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Export Logic

    private func performExport() {
        guard expenseCount > 0 else { return }

        switch selectedFormat {
        case .csv:
            guard appState.isPro else {
                showingProUpsell = true
                return
            }
            executeCSVExport()
        case .pdf:
            guard appState.isPro else {
                showingProUpsell = true
                return
            }
            executePDFExport()
        }
    }

    private func executeCSVExport() {
        isExporting = true

        let domainTags: [Tag] = tags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let prefix = "expenses_\(dateFormatter.string(from: startDate))_to_\(dateFormatter.string(from: endDate))"

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: filteredExpenses,
            tags: domainTags,
            filenamePrefix: prefix
        ) else {
            isExporting = false
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    private func executePDFExport() {
        isExporting = false
    }

}


enum ExportFormat {
    case csv, pdf
}

// MARK: - Export Limit Sheet

struct ExportLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text("You've used your free exports")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Free accounts can export up to 2 times per month. Upgrade to Pro for unlimited exports.")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }
}

// MARK: - Pro Benefits Card (every 3rd expense upsell)

struct ProBenefitsCard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Get more from Tally")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    benefitRow(icon: "infinity", text: "Unlimited expenses per month")
                    benefitRow(icon: "doc.text.viewfinder", text: "Full OCR auto-fill on receipts")
                    benefitRow(icon: "square.and.arrow.up", text: "Unlimited exports")
                    benefitRow(icon: "nosign", text: "No ads")
                }
                .padding(.horizontal, Spacing.sm)
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.xl)
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.smd) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Pro Feature Sheet

struct ProFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    let featureName: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text("Pro Feature")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(featureName) is available with Tally Pro.\nUnlock unlimited exports, PDF reports, OCR auto-fill, and advanced filters.")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }
}
