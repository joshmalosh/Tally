import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseModel.date, order: .reverse) private var allExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var searchText = ""
    @State private var showingEntryPicker = false
    @State private var selectedEntryMode: AddEntryMode?
    @State private var thumbnailCache: [String: UIImage] = [:]
    @State private var periodFilter: PeriodFilter = .allTime
    @State private var showingTagCreation = false
    @State private var exportingExpense: ExpenseModel?
    @State private var showingGlobalExport = false
    @FocusState private var isSearchFocused: Bool

    private var showsBannerAd: Bool { !appState.isPro }

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

    private var filteredExpenses: [ExpenseModel] {
        var result = periodExpenses
        if let tagId = appState.selectedTagFilter {
            if appState.isGroupFilter {
                let childIds = Set(tags.filter { $0.parentId == tagId }.map(\.id))
                result = result.filter { expense in
                    !expense.resolvedTagIds.filter({ childIds.contains($0) }).isEmpty
                }
            } else {
                result = result.filter { $0.resolvedTagIds.contains(tagId) }
            }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { expense in
                (expense.expenseDescription?.lowercased().contains(query) ?? false)
                || (expense.merchant?.lowercased().contains(query) ?? false)
                || (expense.notes?.lowercased().contains(query) ?? false)
                || expense.resolvedTagIds.contains { id in
                    tags.first { $0.id == id }?.name.lowercased().contains(query) ?? false
                }
            }
        }
        return result
    }

    private var displayTotalCents: Int {
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

    private func tagsFor(_ expense: ExpenseModel) -> [TagModel] {
        expense.resolvedTagIds.compactMap { id in tags.first { $0.id == id } }
    }

    private func primaryTag(for expense: ExpenseModel) -> TagModel? {
        tagsFor(expense).first
    }

    private func displayTagName(for expense: ExpenseModel) -> String {
        let resolved = tagsFor(expense)
        guard let first = resolved.first else { return "Untagged" }
        if resolved.count == 1 {
            if let parentId = first.parentId,
               let group = tags.first(where: { $0.id == parentId }) {
                return "\(group.name) › \(first.name)"
            }
            return first.name
        }
        return "\(first.name) +\(resolved.count - 1)"
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                appBar
                headerSection
                searchBar
                tagRow
                    .padding(.top, Spacing.smd)
                divider

                if filteredExpenses.isEmpty {
                    emptyState
                } else {
                    expenseList
                }
            }

            FABButton { showingEntryPicker = true }
                .padding(.trailing, Spacing.md)
                .padding(.bottom, showsBannerAd ? Spacing.xl : Spacing.lg)
                .animation(.easeInOut(duration: 0.3), value: showsBannerAd)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingEntryPicker) {
            AddEntryPicker { mode in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedEntryMode = mode
                }
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(item: $selectedEntryMode) { mode in
            AddExpenseView(initialMode: mode)
        }
        .sheet(item: $appState.selectedExpenseId) { id in
            ExpenseDetailView(expenseId: id)
        }
        .sheet(isPresented: $showingGlobalExport) {
            GlobalExportSheet()
        }
        .sheet(item: $exportingExpense) { expense in
            ExportExpenseSheet(expense: expense, tags: tagsFor(expense))
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTagCreation) {
            TagCreationView()
        }
    }

    // MARK: - App Bar

    private var appBar: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Image("TallyLogo")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)

                if !syncEngine.isOnline {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
            }

            Spacer()

            HStack(spacing: Spacing.md) {
                if appState.isOffline {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.danger)
                }

                Button { showingGlobalExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                Button { appState.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    private var monthlyExpenseCount: Int {
        let cal = Calendar.current
        let now = Date()
        return activeExpenses.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.count
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CurrencyFormatter.shared.format(cents: displayTotalCents, currencyCode: appState.defaultCurrency))
                    .font(Fonts.brand(38))
                    .foregroundStyle(Color.textPrimary)

                Text("\(monthlyExpenseCount) expense\(monthlyExpenseCount == 1 ? "" : "s") this month")
                    .font(Fonts.caption(13))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                periodToggle

                Text(periodSubtitle)
                    .font(Fonts.caption(11))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.smd)
    }

    private var periodToggle: some View {
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

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.textMuted)

            TextField("Search expenses...", text: $searchText)
                .font(Fonts.body(14))
                .foregroundStyle(Color.textPrimary)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 40)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(isSearchFocused ? Color.brandPrimary : Color.borderColor.opacity(0.7), lineWidth: isSearchFocused ? 1 : 0.5)
        )
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Tag Row

    private var homeVisibleTags: [TagModel] {
        tags.filter { $0.showOnHome && $0.parentId == nil }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }
    }

    private func selectTag(_ id: String, isGroup: Bool) {
        if appState.selectedTagFilter == id {
            appState.selectedTagFilter = nil
            appState.isGroupFilter = false
        } else {
            appState.selectedTagFilter = id
            appState.isGroupFilter = isGroup
        }
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.selectedTagFilter = nil
                    appState.isGroupFilter = false
                } label: {
                    TagPill(
                        name: "All",
                        tagColor: TagColors.forId("primaryGreen"),
                        isActive: appState.selectedTagFilter == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(homeVisibleTags) { tag in
                    if tag.isGroup {
                        Menu {
                            Button {
                                selectTag(tag.id, isGroup: true)
                            } label: {
                                Label("All \(tag.name)", systemImage: "folder")
                            }
                            Divider()
                            ForEach(childrenOf(tag)) { child in
                                Button {
                                    selectTag(child.id, isGroup: false)
                                } label: {
                                    Text(child.name)
                                }
                            }
                        } label: {
                            TagPill(
                                name: tag.name,
                                tagColor: tag.tagColor,
                                isActive: appState.selectedTagFilter == tag.id && appState.isGroupFilter,
                                isGroup: true
                            )
                        }
                    } else {
                        Button { selectTag(tag.id, isGroup: false) } label: {
                            TagPill(
                                name: tag.name,
                                tagColor: tag.tagColor,
                                isActive: appState.selectedTagFilter == tag.id && !appState.isGroupFilter
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { showingTagCreation = true } label: {
                    AddTagPill()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.borderColor)
            .frame(height: 1)
    }

    // MARK: - Empty State

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || appState.selectedTagFilter != nil
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            if hasActiveFilters {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No matching expenses",
                    message: "Try adjusting your search or filters."
                )
                .padding(.horizontal, Spacing.xl)
            } else {
                EmptyStateView(
                    icon: "receipt",
                    title: "No expenses yet",
                    message: "Tap + to add your first expense\nand get started."
                )
                .padding(.horizontal, Spacing.xl)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expense List

    private var expenseList: some View {
        List {
            ForEach(filteredExpenses, id: \.id) { expense in
                let tag = primaryTag(for: expense)
                Button {
                    appState.selectedExpenseId = expense.id
                } label: {
                    ExpenseCard(
                        thumbnailImage: thumbnailImage(for: expense),
                        description: expense.expenseDescription ?? "Expense",
                        merchant: expense.merchant,
                        amountCents: expense.amountCents,
                        currency: expense.currency,
                        date: expense.date,
                        tagName: displayTagName(for: expense),
                        tagColor: tag?.tagColor ?? TagColors.forId("warmGrey")
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteExpense(expense)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        exportingExpense = expense
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(Color.brandPrimary)
                }
                .task {
                    await loadThumbnail(for: expense)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Thumbnails

    private func thumbnailImage(for expense: ExpenseModel) -> Image? {
        let cacheKey = expense.attachmentKey ?? expense.id
        guard let uiImage = thumbnailCache[cacheKey] else { return nil }
        return Image(uiImage: uiImage)
    }

    private func deleteExpense(_ expense: ExpenseModel) {
        expense.deletedAt = Date()
        expense.updatedAt = Date()
        if let key = expense.attachmentKey {
            Task { await AttachmentService.shared.deleteAttachment(key: key) }
        }
        do {
            try modelContext.save()
        } catch {
            print("[Tally] ERROR deleting expense: \(error)")
        }
    }

    private func loadThumbnail(for expense: ExpenseModel) async {
        let cacheKey = expense.attachmentKey ?? expense.id
        guard thumbnailCache[cacheKey] == nil else { return }

        if let key = expense.attachmentKey,
           let thumb = await AttachmentService.shared.loadThumbnail(key: key) {
            thumbnailCache[cacheKey] = thumb
            return
        }

        // Fallback: CloudKit-synced attachment data (no local file yet)
        if let data = expense.attachmentData, let image = UIImage(data: data) {
            thumbnailCache[cacheKey] = image
        }
    }
}

// MARK: - Period Filter

enum PeriodFilter {
    case allTime
    case thisYear
    case thisMonth

    var label: String {
        switch self {
        case .allTime: "All Time"
        case .thisYear: "This Year"
        case .thisMonth: "This Month"
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
