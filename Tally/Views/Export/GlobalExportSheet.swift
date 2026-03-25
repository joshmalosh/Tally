import SwiftUI
import SwiftData

struct GlobalExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date, order: .reverse) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    /// When present, shows "Selected" as first option in time range picker and defaults to it.
    var initialSelection: [ExpenseModel]? = nil

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    @State private var periodFilter: PeriodFilter = .allTime

    private var hasSelection: Bool {
        guard let sel = initialSelection, !sel.isEmpty else { return false }
        return true
    }

    @State private var isExporting = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""
    @State private var showingTagExportPicker = false

    private var periodExpenses: [ExpenseModel] {
        switch periodFilter {
        case .selected:
            return initialSelection ?? []
        case .allTime:
            return activeExpenses
        case .thisYear:
            let cal = Calendar.current
            let now = Date()
            return activeExpenses.filter { cal.isDate($0.date, equalTo: now, toGranularity: .year) }
        case .thisMonth:
            let cal = Calendar.current
            let now = Date()
            return activeExpenses.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        }
    }

    private var expenseCount: Int { periodExpenses.count }

    private var totalCents: Int {
        periodExpenses.reduce(0) { $0 + $1.amountCents }
    }

    private var periodSubtitle: String {
        switch periodFilter {
        case .selected:
            let n = initialSelection?.count ?? 0
            return n == 1 ? "1 selected" : "\(n) selected"
        case .allTime:
            if let earliest = activeExpenses.last?.date {
                return "Since \(Self.monthYearFormatter.string(from: earliest))"
            }
            return "All expenses"
        case .thisYear:
            let year = Calendar.current.component(.year, from: Date())
            return "Jan – Dec \(year)"
        case .thisMonth:
            let now = Date()
            let cal = Calendar.current
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                  let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)
            else { return "This month" }
            return "\(Self.monthDayFormatter.string(from: start)) – \(Self.monthDayFormatter.string(from: end))"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if activeExpenses.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            summaryHeader
                                .padding(.bottom, Spacing.lg)

                            VStack(spacing: Spacing.xs) {
                                exportOption(
                                    icon: "tablecells",
                                    title: "Export as CSV",
                                    subtitle: "\(expenseCount) expenses \u{2022} \(periodFilter.label)",
                                    proOnly: true
                                ) {
                                    exportCSV(expenses: periodExpenses)
                                }

                                exportOption(
                                    icon: "doc.richtext",
                                    title: "Export as PDF",
                                    subtitle: "Formatted report with summary",
                                    proOnly: true
                                ) {
                                    exportPDFSummary()
                                }

                                exportOption(
                                    icon: "tag",
                                    title: "Export by tag/group",
                                    subtitle: "Filter by category, then export",
                                    proOnly: true
                                ) {
                                    showingTagExportPicker = true
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                    }
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export")
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
            .onAppear {
                if hasSelection { periodFilter = .selected }
            }
            .sheet(isPresented: $showingTagExportPicker) {
                TagExportPickerSheet(
                    expenses: periodExpenses,
                    tags: Array(allTags),
                    periodLabel: periodFilter.label
                )
            }
            .overlay(alignment: .bottom) {
                if showingToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text("Nothing to export")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)

                Text("Add your first expense, then come back here to export.")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text(CurrencyFormatter.shared.format(cents: totalCents, currencyCode: appState.defaultCurrency))
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expenses")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(expenseCount)")
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }
            }

            HStack {
                periodMenu

                Spacer()

                Text(periodSubtitle)
                    .font(Fonts.caption(11))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Spacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }

    private func periodLabel(for filter: PeriodFilter) -> String {
        if filter == .selected && hasSelection {
            let n = initialSelection?.count ?? 0
            return "Selected (\(n))"
        }
        return filter.label
    }

    private var periodMenu: some View {
        Menu {
            let filters: [PeriodFilter] = hasSelection
                ? [.selected, .allTime, .thisYear, .thisMonth]
                : [.allTime, .thisYear, .thisMonth]
            ForEach(filters, id: \.label) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { periodFilter = filter }
                } label: {
                    Label(periodLabel(for: filter), systemImage: periodFilter == filter ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(periodLabel(for: periodFilter))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textBody)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.smd)
            .padding(.vertical, 6)
            .background(Color.chipInactiveBg)
            .clipShape(Capsule())
        }
    }

    // MARK: - Option Row

    private func exportOption(
        icon: String,
        title: String,
        subtitle: String,
        proOnly: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let locked = proOnly && !appState.isPro

        return Button {
            if locked {
                proFeatureName = title
                showingProUpsell = true
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: Spacing.smd) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(locked ? Color.textMuted : Color.brandPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Fonts.body(16))
                            .foregroundStyle(locked ? Color.textMuted : Color.textPrimary)

                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    Text(locked ? "Pro feature" : subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.6 : 1)
    }

    // MARK: - Export Actions

    private func exportCSV(expenses: [ExpenseModel]) {
        guard appState.isPro else {
            proFeatureName = "CSV export"
            showingProUpsell = true
            return
        }

        isExporting = true

        let domainTags: [Tag] = allTags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: expenses,
            tags: domainTags,
            filenamePrefix: "tally_expenses"
        ) else {
            isExporting = false
            showToast("Export failed")
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    private func exportPDFSummary() {
        guard appState.isPro else {
            proFeatureName = "PDF export"
            showingProUpsell = true
            return
        }
        showToast("PDF export coming soon")
    }

    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topVC.present(vc, animated: true)
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingToast = false
            }
        }
    }

    private var toastView: some View {
        Text(toastMessage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.smd)
            .background(Color.textPrimary.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
    }
}

// MARK: - Selected Export Sheet

struct SelectedExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    let expenses: [ExpenseModel]
    var filterLabel: String = "Selected"

    @State private var isExporting = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""

    private var expenseCount: Int { expenses.count }

    private var totalCents: Int {
        expenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        summaryHeader
                            .padding(.bottom, Spacing.lg)

                        VStack(spacing: Spacing.xs) {
                            exportOption(
                                icon: "tablecells",
                                title: "Export as CSV",
                                subtitle: "\(expenseCount) expense\(expenseCount == 1 ? "" : "s") \u{2022} \(filterLabel)",
                                proOnly: true
                            ) {
                                exportCSV()
                            }

                            exportOption(
                                icon: "doc.richtext",
                                title: "Export as PDF",
                                subtitle: "Formatted report with summary",
                                proOnly: true
                            ) {
                                exportPDF()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export")
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
            .overlay(alignment: .bottom) {
                if showingToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text(CurrencyFormatter.shared.format(cents: totalCents, currencyCode: appState.defaultCurrency))
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expenses")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(expenseCount)")
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }
            }

            HStack {
                Text(filterLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .padding(.horizontal, Spacing.smd)
                    .padding(.vertical, 6)
                    .background(Color.chipInactiveBg)
                    .clipShape(Capsule())

                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }

    // MARK: - Option Row

    private func exportOption(
        icon: String,
        title: String,
        subtitle: String,
        proOnly: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let locked = proOnly && !appState.isPro

        return Button {
            if locked {
                proFeatureName = title
                showingProUpsell = true
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: Spacing.smd) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(locked ? Color.textMuted : Color.brandPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Fonts.body(16))
                            .foregroundStyle(locked ? Color.textMuted : Color.textPrimary)

                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    Text(locked ? "Pro feature" : subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.6 : 1)
    }

    // MARK: - Export Actions

    private func exportCSV() {
        guard appState.isPro else {
            proFeatureName = "CSV export"
            showingProUpsell = true
            return
        }

        isExporting = true

        let domainTags: [Tag] = allTags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: expenses,
            tags: domainTags,
            filenamePrefix: "tally_selected"
        ) else {
            isExporting = false
            showToast("Export failed")
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    private func exportPDF() {
        guard appState.isPro else {
            proFeatureName = "PDF export"
            showingProUpsell = true
            return
        }
        showToast("PDF export coming soon")
    }

    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topVC.present(vc, animated: true)
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingToast = false
            }
        }
    }

    private var toastView: some View {
        Text(toastMessage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.smd)
            .background(Color.textPrimary.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
    }
}

// MARK: - Tag/Group Export Picker

struct TagExportPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let expenses: [ExpenseModel]
    let tags: [TagModel]
    let periodLabel: String

    @State private var selectedIds: Set<String> = []
    @State private var isExporting = false

    private var standaloneTags: [TagModel] {
        tags.filter { $0.parentId == nil && !$0.isGroup }
    }

    private var groupTags: [TagModel] {
        tags.filter { $0.isGroup }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var matchingExpenses: [ExpenseModel] {
        guard !selectedIds.isEmpty else { return [] }

        let selectedGroupIds = selectedIds.filter { id in groupTags.contains { $0.id == id } }
        let selectedTagIds = selectedIds.subtracting(selectedGroupIds)

        var expandedTagIds = selectedTagIds
        for groupId in selectedGroupIds {
            if let group = groupTags.first(where: { $0.id == groupId }) {
                let childIds = childrenOf(group).map(\.id)
                expandedTagIds.formUnion(childIds)
            }
        }

        return expenses.filter { expense in
            !expense.resolvedTagIds.filter({ expandedTagIds.contains($0) }).isEmpty
        }
    }

    private var matchingTotal: Int {
        matchingExpenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if standaloneTags.isEmpty && groupTags.isEmpty {
                    VStack(spacing: Spacing.lg) {
                        Spacer()

                        Image(systemName: "tag")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textMuted)

                        VStack(spacing: Spacing.sm) {
                            Text("No tags yet")
                                .font(Fonts.headline(20))
                                .foregroundStyle(Color.textPrimary)

                            Text("Create tags in Settings to filter and export expenses by category.")
                                .font(Fonts.body(15))
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, Spacing.xl)

                        Spacer()
                    }
                } else {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        if !standaloneTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Tags")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                VStack(spacing: 0) {
                                    ForEach(standaloneTags) { tag in
                                        let isSelected = selectedIds.contains(tag.id)
                                        Button {
                                            toggleSelection(tag.id)
                                        } label: {
                                            HStack(spacing: Spacing.smd) {
                                                Circle()
                                                    .fill(tag.tagColor.primaryColor)
                                                    .frame(width: 12, height: 12)
                                                Text(tag.name)
                                                    .font(Fonts.body(15))
                                                    .foregroundStyle(Color.textPrimary)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(Color.brandPrimary)
                                                }
                                            }
                                            .padding(.horizontal, Spacing.md)
                                            .frame(height: 48)
                                            .background(isSelected ? Color.brandTint : Color.surface)
                                        }
                                        .buttonStyle(.plain)

                                        if tag.id != standaloneTags.last?.id {
                                            Divider().padding(.leading, Spacing.md)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(Color.borderColor, lineWidth: 1)
                                )
                            }
                        }

                        if !groupTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Groups")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                VStack(spacing: 0) {
                                    ForEach(groupTags) { group in
                                        let isSelected = selectedIds.contains(group.id)
                                        Button {
                                            toggleSelection(group.id)
                                        } label: {
                                            HStack(spacing: Spacing.smd) {
                                                Image(systemName: "folder.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(group.tagColor.primaryColor)
                                                Text(group.name)
                                                    .font(Fonts.body(15))
                                                    .foregroundStyle(Color.textPrimary)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(Color.brandPrimary)
                                                }
                                            }
                                            .padding(.horizontal, Spacing.md)
                                            .frame(height: 48)
                                            .background(isSelected ? Color.brandTint : Color.surface)
                                        }
                                        .buttonStyle(.plain)

                                        if group.id != groupTags.last?.id {
                                            Divider().padding(.leading, Spacing.md)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(Color.borderColor, lineWidth: 1)
                                )
                            }
                        }

                        if !selectedIds.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Divider().foregroundStyle(Color.borderColor)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(matchingExpenses.count) expense\(matchingExpenses.count == 1 ? "" : "s")")
                                            .font(Fonts.label(14))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(CurrencyFormatter.shared.format(cents: matchingTotal, currencyCode: appState.defaultCurrency))
                                            .font(Fonts.caption(13))
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    Text(periodLabel)
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .padding(.top, Spacing.sm)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }

                VStack(spacing: 0) {
                    Divider()
                    PrimaryButton(
                        title: selectedIds.isEmpty
                            ? "Select tags or groups"
                            : "Export \(matchingExpenses.count) expenses",
                        action: { exportFiltered() },
                        isLoading: isExporting
                    )
                    .disabled(selectedIds.isEmpty || matchingExpenses.isEmpty)
                    .padding(Spacing.md)
                }
                .background(Color.bgPrimary)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export by tag/group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }

                if !selectedIds.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedIds.removeAll()
                            }
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedIds)
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func exportFiltered() {
        guard !matchingExpenses.isEmpty else { return }
        guard appState.canExportCSV else { return }

        isExporting = true

        let domainTags: [Tag] = tags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        let selectedNames = selectedIds.compactMap { id in tags.first { $0.id == id }?.name }
        let tagSuffix = selectedNames.prefix(3).joined(separator: "_").replacingOccurrences(of: " ", with: "-")

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: matchingExpenses,
            tags: domainTags,
            filenamePrefix: "tally_\(tagSuffix)"
        ) else {
            isExporting = false
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topVC.present(vc, animated: true)
    }
}
