import SwiftUI
import SwiftData

struct GlobalExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseModel.date, order: .reverse) private var allExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    @State private var periodFilter: PeriodFilter = .allTime
    @State private var isExporting = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingExportLimit = false
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""
    @State private var showingTagExportPicker = false

    private var activeExpenses: [ExpenseModel] {
        allExpenses.filter { $0.deletedAt == nil }
    }

    private var periodExpenses: [ExpenseModel] {
        switch periodFilter {
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
        case .allTime:
            if let earliest = activeExpenses.last?.date {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMM yyyy"
                return "Since \(fmt.string(from: earliest))"
            }
            return "All expenses"
        case .thisYear:
            let year = Calendar.current.component(.year, from: Date())
            return "Jan – Dec \(year)"
        case .thisMonth:
            let now = Date()
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        }
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
                                subtitle: "\(expenseCount) expenses \u{2022} \(periodFilter.label)",
                                proOnly: false
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
            .background(Color.bgPrimary)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingExportLimit) {
                ExportLimitSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingProUpsell) {
                ProFeatureSheet(featureName: proFeatureName)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
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

    private var periodMenu: some View {
        Menu {
            ForEach([PeriodFilter.allTime, .thisYear, .thisMonth], id: \.label) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { periodFilter = filter }
                } label: {
                    Label(filter.label, systemImage: periodFilter == filter ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(periodFilter.label)
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
        guard appState.canExportCSV else {
            showingExportLimit = true
            return
        }

        isExporting = true

        let domainExpenses: [Expense] = expenses.map { model in
            Expense(
                id: model.id,
                userId: model.userId,
                amountCents: model.amountCents,
                currency: model.currency,
                date: model.date,
                description: model.expenseDescription,
                merchant: model.merchant,
                tagIds: model.resolvedTagIds,
                notes: model.notes,
                attachmentKey: model.attachmentKey,
                source: ExpenseSource(rawValue: model.source) ?? .manual,
                createdAt: model.createdAt,
                updatedAt: model.updatedAt,
                deletedAt: nil
            )
        }

        let domainTags: [Tag] = allTags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        let csv = ExpenseCalculations.generateCSV(
            expenses: domainExpenses,
            tags: domainTags
        )

        let tempDir = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "tally_expenses_\(dateFormatter.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            appState.recordCSVExport()
            isExporting = false
            presentShareSheet(items: [fileURL])
        } catch {
            isExporting = false
            showToast("Export failed")
        }
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
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        if !standaloneTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Tags")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                FlowLayout(spacing: Spacing.sm) {
                                    ForEach(standaloneTags) { tag in
                                        selectableChip(
                                            name: tag.name,
                                            color: tag.tagColor,
                                            isSelected: selectedIds.contains(tag.id)
                                        ) {
                                            toggleSelection(tag.id)
                                        }
                                    }
                                }
                            }
                        }

                        if !groupTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Groups")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                FlowLayout(spacing: Spacing.sm) {
                                    ForEach(groupTags) { group in
                                        selectableChip(
                                            name: group.name,
                                            color: group.tagColor,
                                            isSelected: selectedIds.contains(group.id),
                                            isGroup: true
                                        ) {
                                            toggleSelection(group.id)
                                        }
                                    }
                                }
                            }
                        }

                        if !selectedIds.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Divider()
                                    .foregroundStyle(Color.borderColor)

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

    private func selectableChip(
        name: String,
        color: TagColor,
        isSelected: Bool,
        isGroup: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isGroup {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white : color.primaryColor)
                } else {
                    Circle()
                        .fill(isSelected ? .white : color.primaryColor)
                        .frame(width: 8, height: 8)
                }

                Text(name)
                    .font(Fonts.label(14))
                    .foregroundStyle(isSelected ? .white : Color.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, Spacing.smd)
            .padding(.vertical, 7)
            .background(isSelected ? color.primaryColor : Color.chipInactiveBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func exportFiltered() {
        guard !matchingExpenses.isEmpty else { return }
        guard appState.canExportCSV else { return }

        isExporting = true

        let domainExpenses: [Expense] = matchingExpenses.map { model in
            Expense(
                id: model.id,
                userId: model.userId,
                amountCents: model.amountCents,
                currency: model.currency,
                date: model.date,
                description: model.expenseDescription,
                merchant: model.merchant,
                tagIds: model.resolvedTagIds,
                notes: model.notes,
                attachmentKey: model.attachmentKey,
                source: ExpenseSource(rawValue: model.source) ?? .manual,
                createdAt: model.createdAt,
                updatedAt: model.updatedAt,
                deletedAt: nil
            )
        }

        let domainTags: [Tag] = tags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        let csv = ExpenseCalculations.generateCSV(
            expenses: domainExpenses,
            tags: domainTags
        )

        let tempDir = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let selectedNames = selectedIds.compactMap { id in tags.first { $0.id == id }?.name }
        let tagSuffix = selectedNames.prefix(3).joined(separator: "_").replacingOccurrences(of: " ", with: "-")
        let filename = "tally_\(tagSuffix)_\(dateFormatter.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            appState.recordCSVExport()
            isExporting = false
            presentShareSheet(items: [fileURL])
        } catch {
            isExporting = false
        }
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
