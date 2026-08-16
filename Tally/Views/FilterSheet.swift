import SwiftUI
import SwiftData

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var periodFilter: PeriodFilter
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil })
    private var expenses: [ExpenseModel]

    @State private var searchText = ""
    @State private var showingCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    // MARK: - Palette
    private let ink = Color(hex: "1C1C1E")
    private let dark = Color(hex: "2F402E")
    private let muted = Color(hex: "8F9E94")
    private let border = Color(hex: "DEDAD2")

    // MARK: - Data

    /// Only the currencies the user has actually logged.
    private var usedCurrencies: [String] {
        Array(Set(expenses.map(\.currency))).sorted()
    }

    private var standaloneTags: [TagModel] {
        tags.filter { !$0.isGroup && $0.parentId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var groups: [TagModel] {
        tags.filter { $0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func childTags(of group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func matches(_ tag: TagModel) -> Bool {
        searchText.isEmpty || tag.name.localizedCaseInsensitiveContains(searchText)
    }
    private var visibleStandalone: [TagModel] { standaloneTags.filter(matches) }
    private func visibleGroups() -> [TagModel] {
        groups.filter { matches($0) || childTags(of: $0).contains(where: matches) }
    }

    private let periodOptions: [(PeriodFilter, String)] = [
        (.allTime, "All time"),
        (.thisFinancialYear, "Financial year"),
        (.thisYear, "This year"),
        (.thisMonth, "This month"),
        (.lastMonth, "Last month"),
    ]

    private var filterCount: Int {
        (periodFilter != .allTime ? 1 : 0)
            + appState.activeFilterIds.count
            + (appState.filterRecurringOnly ? 1 : 0)
            + (appState.filterCurrency != nil ? 1 : 0)
    }
    private var summaryText: String {
        filterCount == 0 ? "No filters applied" : "\(filterCount) filter\(filterCount == 1 ? "" : "s") applied"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    periodSection
                    if !usedCurrencies.isEmpty { currencySection }
                    typeSection
                    if !tags.isEmpty { tagsSection }
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingCustomRange) { customRangeSheet }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Filter")
                    .font(.system(size: 22, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(ink)
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            HStack {
                Button("Reset") {
                    appState.clearFilters()
                    periodFilter = .allTime
                }
                .font(.system(size: 15))
                .foregroundStyle(filterCount == 0 ? muted.opacity(0.5) : muted)
                .disabled(filterCount == 0)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(dark)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(muted)
            .padding(.horizontal, 20)
    }

    // MARK: - Time period

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Time period")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(periodOptions, id: \.0.label) { option in
                    periodPill(label: option.1, isSelected: periodFilter == option.0) {
                        periodFilter = option.0
                    }
                }
                periodPill(label: "Custom", isSelected: periodFilter.isCustom) {
                    showingCustomRange = true
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func periodPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? dark : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Currency

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Currency")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(usedCurrencies, id: \.self) { code in
                    currencyChip(code: code, isSelected: appState.filterCurrency == code) {
                        appState.filterCurrency = appState.filterCurrency == code ? nil : code
                    }
                }
            }
            .padding(.horizontal, 16)

            Text(appState.filterCurrency == nil ? "Showing all currencies" : "Showing \(appState.filterCurrency!) only")
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .padding(.horizontal, 20)
        }
    }

    private func currencyChip(code: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color(hex: "E8F0EA"))
                        .frame(width: 28, height: 28)
                    Text(CurrencyFormatter.shared.symbol(for: code))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : dark)
                }
                Text(code)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : ink)
            }
            .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? dark : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Type")
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "E8F0EA")).frame(width: 30, height: 30)
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 13))
                        .foregroundStyle(dark)
                }
                Text("Recurring only")
                    .font(.system(size: 16))
                    .foregroundStyle(ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.filterRecurringOnly },
                    set: { appState.filterRecurringOnly = $0 }
                ))
                .labelsHidden()
                .tint(dark)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tags & groups

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Tags & groups")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(muted)
                TextField("Search tags…", text: $searchText)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                let vs = visibleStandalone
                let vg = visibleGroups()
                ForEach(Array(vs.enumerated()), id: \.element.id) { index, tag in
                    tagFilterRow(tag: tag)
                    if index < vs.count - 1 || !vg.isEmpty {
                        Divider().padding(.horizontal, 20)
                    }
                }
                ForEach(Array(vg.enumerated()), id: \.element.id) { gIndex, group in
                    FilterRow(
                        title: group.name,
                        isSelected: appState.activeFilterIds.contains(group.id),
                        leading: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(group.tagColor.primaryColor)
                        }
                    ) {
                        appState.toggleFilter(id: group.id, isGroup: true)
                    }
                    ForEach(childTags(of: group), id: \.id) { child in
                        Divider().padding(.horizontal, 20)
                        FilterRow(
                            title: child.name,
                            titleFont: .system(size: 15),
                            titleColor: Color(hex: "4A5E50"),
                            isSelected: appState.activeFilterIds.contains(child.id),
                            checkmarkFont: .system(size: 13, weight: .semibold),
                            verticalPadding: 11,
                            leading: {
                                Circle().fill(child.tagColor.primaryColor)
                                    .frame(width: 8, height: 8).padding(.leading, 16)
                            }
                        ) {
                            appState.toggleFilter(id: child.id, isGroup: false)
                        }
                    }
                    if gIndex < vg.count - 1 {
                        Divider().padding(.horizontal, 20)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    private func tagFilterRow(tag: TagModel) -> some View {
        FilterRow(
            title: tag.name,
            isSelected: appState.activeFilterIds.contains(tag.id),
            leading: {
                Circle().fill(tag.tagColor.primaryColor).frame(width: 10, height: 10)
            }
        ) {
            appState.toggleFilter(id: tag.id, isGroup: false)
        }
    }

    // MARK: - Custom range sheet

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let lo = min(customStart, customEnd)
                        let hi = max(customStart, customEnd)
                        periodFilter = .custom(start: lo, end: hi)
                        showingCustomRange = false
                    }
                    .foregroundStyle(dark)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
