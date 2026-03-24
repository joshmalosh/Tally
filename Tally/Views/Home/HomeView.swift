import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date, order: .reverse) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var searchText = ""
    @State private var showingEntryPicker = false
    @State private var selectedEntryMode: AddEntryMode?
    @State private var thumbnailCache: [String: UIImage] = [:]
    @State private var periodFilter: PeriodFilter = .allTime
    @State private var showingTagCreation = false
    @State private var showingGroupCreation = false
    @State private var showingAddTagOrGroupPicker = false
    @State private var showingGlobalExport = false
    @State private var showingFilteredExport = false
    @State private var isSelecting = false
    @State private var selectedExpenseIds: Set<String> = []
    @State private var exportWithSelectionItem: ExportWithSelectionItem?
    @State private var expandedGroupId: String?
    @State private var expenseToDelete: ExpenseModel?
    @FocusState private var isSearchFocused: Bool

    private var showsBannerAd: Bool { !appState.isPro }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private var periodExpenses: [ExpenseModel] {
        switch periodFilter {
        case .selected:
            return activeExpenses.filter { selectedExpenseIds.contains($0.id) }
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
        if appState.hasTagFilters {
            result = result.filter { expense in
                for filterId in appState.activeFilterIds {
                    if appState.groupFilterIds.contains(filterId) {
                        let childIds = tags.filter { $0.parentId == filterId }.map(\.id)
                        if !expense.resolvedTagIds.contains(where: { childIds.contains($0) }) {
                            return false
                        }
                    } else {
                        if !expense.resolvedTagIds.contains(filterId) {
                            return false
                        }
                    }
                }
                return true
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
        case .selected:
            return "Selected"
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
                    .allowsHitTesting(!isSelecting)

                searchBar
                tagRow
                    .padding(.top, Spacing.smd)

                divider

                if filteredExpenses.isEmpty && !isSelecting {
                    emptyState
                } else {
                    expenseList
                }

                if isSelecting && !selectedExpenseIds.isEmpty {
                    selectionBottomToolbar
                        .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: selectedExpenseIds.count) { _, count in
                if isSelecting && count == 0 {
                    exitSelectionMode()
                }
            }

            if !isSelecting {
                FABButton { showingEntryPicker = true }
                    .padding(.trailing, Spacing.lg)
                    .padding(.bottom, showsBannerAd ? (Spacing.xl + 4) : (Spacing.lg + 4))
                    .animation(.easeInOut(duration: 0.3), value: showsBannerAd)
            }
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingEntryPicker) {
            AddEntryPicker { mode in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedEntryMode = mode
                }
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(item: $selectedEntryMode) { mode in
            if mode == .bulkImport {
                AddMultipleExpensesView()
            } else {
                AddExpenseView(initialMode: mode)
            }
        }
        .sheet(item: $appState.selectedExpenseId) { id in
            ExpenseDetailView(expenseId: id)
        }
        .sheet(isPresented: $showingGlobalExport) {
            GlobalExportSheet()
        }
        .sheet(isPresented: $showingFilteredExport) {
            SelectedExportSheet(
                expenses: filteredExpenses,
                filterLabel: activeFilterLabel
            )
        }
        .sheet(isPresented: $showingTagCreation) {
            TagCreationView()
        }
        .sheet(isPresented: $showingGroupCreation) {
            TagCreationView(isGroupMode: true)
        }
        .sheet(isPresented: $showingAddTagOrGroupPicker) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Button {
                        showingAddTagOrGroupPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingTagCreation = true
                        }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                                .frame(width: 28)
                            Text("New tag")
                                .font(Fonts.body(16))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, Spacing.lg + 28 + Spacing.md)

                    Button {
                        showingAddTagOrGroupPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingGroupCreation = true
                        }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                                .frame(width: 28)
                            Text("New group")
                                .font(Fonts.body(16))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .background(Color.bgPrimary)
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportWithSelectionItem) { item in
            GlobalExportSheet(initialSelection: item.expenses)
        }
        .alert("Delete expense?", isPresented: Binding(
            get: { expenseToDelete != nil },
            set: { if !$0 { expenseToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { expenseToDelete = nil }
            Button("Delete", role: .destructive) {
                if let exp = expenseToDelete { deleteExpense(exp) }
                expenseToDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
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
                    .frame(height: 34)

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

                Button { openExport() } label: {
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

    private var periodExpenseCount: Int {
        periodExpenses.count
    }

    private var expenseCountLabel: String {
        let count = periodExpenseCount
        let noun = count == 1 ? "expense" : "expenses"
        switch periodFilter {
        case .selected:
            return "\(count) selected"
        case .allTime:
            return "\(count) \(noun)"
        case .thisYear:
            return "\(count) \(noun) this year"
        case .thisMonth:
            return "\(count) \(noun) this month"
        }
    }

    // MARK: - Header

    private var selectedTotalCents: Int {
        filteredExpenses
            .filter { selectedExpenseIds.contains($0.id) }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var headerSection: some View {
        let hasSelection = isSelecting && !selectedExpenseIds.isEmpty

        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CurrencyFormatter.shared.format(
                    cents: hasSelection ? selectedTotalCents : displayTotalCents,
                    currencyCode: appState.defaultCurrency
                ))
                .font(Fonts.brand(38))
                .foregroundStyle(Color.textPrimary)
                .opacity(isSelecting && !hasSelection ? 0.15 : 1)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: selectedTotalCents)

                Text(hasSelection
                     ? "\(selectedExpenseIds.count) selected"
                     : expenseCountLabel)
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)
                .opacity(isSelecting && !hasSelection ? 0.15 : 1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                periodToggle

                Text(periodSubtitle)
                    .font(Fonts.caption(11))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.bottom, 2)
            .opacity(isSelecting ? 0.15 : 1)
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

    private func groupIsActive(_ group: TagModel) -> Bool {
        if appState.activeFilterIds.contains(group.id) { return true }
        return childrenOf(group).contains { appState.activeFilterIds.contains($0.id) }
    }

    private func groupActiveCount(_ group: TagModel) -> Int {
        var count = 0
        if appState.activeFilterIds.contains(group.id) { count += 1 }
        count += childrenOf(group).filter { appState.activeFilterIds.contains($0.id) }.count
        return count
    }

    private func groupPillLabel(_ group: TagModel) -> String {
        let activeChildren = childrenOf(group).filter { appState.activeFilterIds.contains($0.id) }
        if appState.activeFilterIds.contains(group.id) {
            return activeChildren.isEmpty ? group.name : "\(group.name) +\(activeChildren.count)"
        }
        if activeChildren.count == 1, let child = activeChildren.first {
            return child.name
        }
        if activeChildren.count > 1, let first = activeChildren.first {
            return "\(first.name) +\(activeChildren.count - 1)"
        }
        return group.name
    }

    private var tagRow: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        appState.clearFilters()
                        withAnimation(.easeInOut(duration: 0.2)) { expandedGroupId = nil }
                    } label: {
                        TagPill(
                            name: "All",
                            tagColor: TagColors.forId("primaryGreen"),
                            isActive: !appState.hasTagFilters
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(homeVisibleTags) { tag in
                        if tag.isGroup {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedGroupId == tag.id {
                                        expandedGroupId = nil
                                    } else {
                                        expandedGroupId = tag.id
                                    }
                                }
                            } label: {
                                TagPill(
                                    name: groupPillLabel(tag),
                                    tagColor: tag.tagColor,
                                    isActive: groupIsActive(tag),
                                    isGroup: true,
                                    isExpanded: expandedGroupId == tag.id
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                appState.toggleFilter(id: tag.id, isGroup: false)
                            } label: {
                                TagPill(
                                    name: tag.name,
                                    tagColor: tag.tagColor,
                                    isActive: appState.activeFilterIds.contains(tag.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button { showingAddTagOrGroupPicker = true } label: {
                        AddTagPill()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture { isSearchFocused = false }

            if let groupId = expandedGroupId,
               let group = homeVisibleTags.first(where: { $0.id == groupId }) {
                groupChildrenRow(group)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func groupChildrenRow(_ group: TagModel) -> some View {
        let groupAllActive = appState.activeFilterIds.contains(group.id)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.toggleFilter(id: group.id, isGroup: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(groupAllActive ? .white : Color.textSecondary)
                        Text("All")
                            .font(.system(size: 13, weight: groupAllActive ? .semibold : .regular))
                    }
                    .foregroundStyle(groupAllActive ? Color.chipActiveText : Color.chipInactiveText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.pill)
                            .fill(groupAllActive ? Color.chipActiveBg : Color.chipInactiveBg)
                    )
                }
                .buttonStyle(.plain)

                ForEach(childrenOf(group)) { child in
                    let isChildActive = appState.activeFilterIds.contains(child.id)
                    Button {
                        appState.toggleFilter(id: child.id, isGroup: false)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isChildActive ? .white : child.tagColor.primaryColor)
                                .frame(width: 7, height: 7)
                            Text(child.name)
                                .font(.system(size: 13, weight: isChildActive ? .semibold : .regular))
                        }
                        .foregroundStyle(isChildActive ? Color.chipActiveText : Color.chipInactiveText)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.pill)
                                .fill(isChildActive ? Color.chipActiveBg : Color.chipInactiveBg)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.borderColor)
            .frame(height: 1)
    }

    // MARK: - Empty State

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || appState.hasTagFilters
    }

    private var emptyState: some View {
        ScrollView {
            VStack {
                Spacer(minLength: UIScreen.main.bounds.height * 0.25)
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
                Spacer(minLength: UIScreen.main.bounds.height * 0.25)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expense List

    private var expenseList: some View {
        List {
            ForEach(filteredExpenses, id: \.id) { expense in
                let tag = primaryTag(for: expense)
                let isSelected = selectedExpenseIds.contains(expense.id)

                HStack(spacing: 0) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: isSelected ? .regular : .light))
                            .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary.opacity(0.55))
                            .frame(width: 44)
                    }

                    ExpenseCard(
                        thumbnailImage: thumbnailImage(for: expense),
                        description: expense.expenseDescription ?? "Expense",
                        merchant: expense.merchant,
                        amountCents: expense.amountCents,
                        currency: expense.currency,
                        date: expense.date,
                        tagName: displayTagName(for: expense),
                        tagColor: tag?.tagColor ?? TagColors.forId("warmGrey"),
                        showRecurringIcon: expense.recurrenceTemplateId != nil || expense.isRecurring
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            toggleExpenseSelection(expense.id)
                        }
                    } else {
                        appState.selectedExpenseId = expense.id
                    }
                }
                .onLongPressGesture(minimumDuration: 0.3) {
                    if !isSelecting {
                        enterSelectionMode(preselecting: expense.id)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !isSelecting {
                        Button(role: .destructive) {
                            expenseToDelete = expense
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .task {
                    await loadThumbnail(for: expense)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
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
            #if DEBUG
            print("[Tally] ERROR deleting expense: \(error)")
            #endif
        }
    }

    private static let maxCachedThumbnails = 150

    private func loadThumbnail(for expense: ExpenseModel) async {
        let cacheKey = expense.attachmentKey ?? expense.id
        guard thumbnailCache[cacheKey] == nil else { return }

        if thumbnailCache.count > Self.maxCachedThumbnails {
            let keysToRemove = Array(thumbnailCache.keys.prefix(thumbnailCache.count / 3))
            for key in keysToRemove { thumbnailCache.removeValue(forKey: key) }
        }

        if let key = expense.attachmentKey,
           let thumb = await AttachmentService.shared.loadThumbnail(key: key) {
            thumbnailCache[cacheKey] = thumb
            return
        }

        if let data = expense.attachmentData, let image = UIImage(data: data) {
            thumbnailCache[cacheKey] = image
        }
    }

    // MARK: - Selection Bottom Toolbar

    private var selectionBottomToolbar: some View {
        HStack(spacing: 0) {
            Button {
                exitSelectionMode()
            } label: {
                Text("Cancel")
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 70, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: Spacing.md)

            Text("\(selectedExpenseIds.count) selected")
                .font(Fonts.caption(15))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Spacing.md)

            Button {
                deleteSelectedExpenses()
            } label: {
                Text("Delete")
                    .font(Fonts.body(16))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.danger)
                    .frame(minWidth: 70, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(selectedExpenseIds.isEmpty)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderColor.opacity(0.6))
                .frame(height: 1)
        }
    }

    // MARK: - Export FAB

    private var exportFAB: some View {
        let count = selectedExpenseIds.count
        let hasSelection = count > 0

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let selected = filteredExpenses.filter { selectedExpenseIds.contains($0.id) }
            exportWithSelectionItem = ExportWithSelectionItem(expenses: selected)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .semibold))
                    .offset(y: -1)
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(
                        Circle()
                            .fill(hasSelection ? Color.actionGreen : Color.textMuted)
                    )
                    .shadow(
                        color: .black.opacity(hasSelection ? 0.35 : 0.1),
                        radius: hasSelection ? 12 : 4,
                        x: 0,
                        y: hasSelection ? 5 : 2
                    )

                if hasSelection {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.actionGreen)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.actionGreen, lineWidth: 1.5)
                        )
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(!hasSelection)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Selection Mode

    private func enterSelectionMode(preselecting id: String? = nil) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting = true
            selectedExpenseIds.removeAll()
            expandedGroupId = nil
            if let id { selectedExpenseIds.insert(id) }
        }
    }

    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting = false
            selectedExpenseIds.removeAll()
        }
    }

    private func toggleExpenseSelection(_ id: String) {
        if selectedExpenseIds.contains(id) {
            selectedExpenseIds.remove(id)
        } else {
            selectedExpenseIds.insert(id)
        }
    }

    private func deleteSelectedExpenses() {
        let toDelete = filteredExpenses.filter { selectedExpenseIds.contains($0.id) }
        for expense in toDelete {
            expense.deletedAt = Date()
            expense.updatedAt = Date()
            if let key = expense.attachmentKey {
                Task { await AttachmentService.shared.deleteAttachment(key: key) }
            }
        }
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[Tally] ERROR deleting expenses: \(error)")
            #endif
        }
        exitSelectionMode()
    }

    private func exportSelectedExpenses() {
        let selected = filteredExpenses.filter { selectedExpenseIds.contains($0.id) }
        exportExpensesAsCSV(selected)
    }

    // MARK: - Export Helpers

    private var activeFilterLabel: String {
        let names = appState.activeFilterIds.compactMap { id in
            tags.first(where: { $0.id == id })?.name
        }
        if names.isEmpty { return "Filtered" }
        if names.count == 1 { return names[0] }
        return "\(names[0]) + \(names.count - 1) more"
    }

    private func openExport() {
        if isSelecting && !selectedExpenseIds.isEmpty {
            let selected = filteredExpenses.filter { selectedExpenseIds.contains($0.id) }
            exportWithSelectionItem = ExportWithSelectionItem(expenses: selected)
        } else if appState.hasTagFilters {
            showingFilteredExport = true
        } else {
            showingGlobalExport = true
        }
    }

    private func exportExpensesAsCSV(_ expenses: [ExpenseModel]) {
        guard !expenses.isEmpty else { return }
        guard appState.canExportCSV else { return }

        let domainTags: [Tag] = tags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: expenses,
            tags: domainTags,
            filenamePrefix: "tally_expenses"
        ) else { return }

        appState.recordCSVExport()
        presentShareSheet(items: [fileURL])
        if isSelecting { exitSelectionMode() }
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

// MARK: - Export With Selection Item

private struct ExportWithSelectionItem: Identifiable {
    let id = UUID()
    let expenses: [ExpenseModel]
}

// MARK: - Period Filter

enum PeriodFilter {
    case selected
    case allTime
    case thisYear
    case thisMonth

    var label: String {
        switch self {
        case .selected: "Selected"
        case .allTime: "All Time"
        case .thisYear: "This Year"
        case .thisMonth: "This Month"
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
