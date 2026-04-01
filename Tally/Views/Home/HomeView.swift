import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AdManager.self) private var adManager
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date, order: .reverse) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var searchText = ""
    @State private var showingEntryPicker = false
    @State private var selectedEntryMode: AddEntryMode?
    @State private var thumbnailCache: [String: UIImage] = [:]
    @State private var periodFilter: PeriodFilter = .allTime
    @State private var showingSharedTagPicker = false
    @State private var isHeaderCollapsed = false
    @State private var showingGlobalExport = false
    @State private var showingFilteredExport = false
    @State private var isSelecting = false
    @State private var selectedExpenseIds: Set<String> = []
    @State private var exportWithSelectionItem: ExportWithSelectionItem?
    @State private var expandedGroupId: String?
    @State private var expenseToDelete: ExpenseModel?
    @FocusState private var isSearchFocused: Bool
    @State private var previousScrollOffset: CGFloat = 0
    @State private var fabScrollScale: CGFloat = 1.0
    @State private var fabPressScale: CGFloat = 1.0
    @State private var fabIsPressed: Bool = false
    @State private var fabRippling: Bool = false
    @State private var animatedTotal: Double = 0
    @State private var totalAnimationTrigger: Int = 0
    @State private var totalCountUpTimer: Timer?

    private var periodExpenses: [ExpenseModel] {
        switch periodFilter {
        case .selected:
            return activeExpenses.filter { selectedExpenseIds.contains($0.id) }
        case .allTime:
            return activeExpenses
        case .thisFinancialYear:
            let start = appState.currentFinancialYearStart
            return activeExpenses.filter { $0.date >= start }
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

    private func tagsFor(_ expense: ExpenseModel) -> [TagModel] {
        expense.resolvedTagIds.compactMap { id in tags.first { $0.id == id } }
    }

    private func primaryTag(for expense: ExpenseModel) -> TagModel? {
        tagsFor(expense).first
    }

    /// Label for the first tag only (used in list row pill).
    private func primaryTagDisplayLabel(for expense: ExpenseModel) -> String? {
        let resolved = tagsFor(expense)
        guard let first = resolved.first else { return nil }
        if let parentId = first.parentId,
           let group = tags.first(where: { $0.id == parentId }) {
            return "\(group.name) › \(first.name)"
        }
        return first.name
    }

    private func additionalTagCount(for expense: ExpenseModel) -> Int {
        let n = tagsFor(expense).count
        return n > 1 ? n - 1 : 0
    }

    private let fabCircleDimension: CGFloat = 91
    private let fabPlusFontSize: CGFloat = 34

    private var homeScrollableColumn: some View {
        VStack(spacing: 0) {
            if !isHeaderCollapsed {
                appBar
                    .transition(.move(edge: .top).combined(with: .opacity))

                Spacer()
                    .frame(height: 8)
            }

            headerSection
                .allowsHitTesting(!isSelecting)

            if !isHeaderCollapsed {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            tagRow
                .padding(.top, 4)

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
        .onAppear {
            animateTotal()
        }
        .onChange(of: activeExpenses.count) { _, _ in
            animateTotal()
        }
    }

    private func formatAnimatedTotal() -> String {
        let val = animatedTotal / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: val)) ?? "0.00"
    }

    private func animateTotal() {
        totalCountUpTimer?.invalidate()
        animatedTotal = 0
        let target = Double(displayTotalCents)
        let duration: Double = 0.9
        let startTime = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            let eased = 1.0 - pow(2.0, -10.0 * progress)
            DispatchQueue.main.async {
                animatedTotal = eased * target
                if progress >= 1.0 {
                    animatedTotal = target
                    totalAnimationTrigger += 1
                    t.invalidate()
                    totalCountUpTimer = nil
                }
            }
        }
        totalCountUpTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var fabButton: some View {
        Button(action: {}) {
            ZStack {
                if fabRippling {
                    Circle()
                        .stroke(Color.brandPrimary, lineWidth: 2)
                        .frame(width: fabCircleDimension, height: fabCircleDimension)
                        .scaleEffect(fabRippling ? 2.1 : 1.0)
                        .opacity(fabRippling ? 0 : 0.65)
                        .animation(.easeOut(duration: 0.5), value: fabRippling)
                }
                Image(systemName: "plus")
                    .font(.system(size: fabPlusFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: fabCircleDimension, height: fabCircleDimension)
                    .background(Circle().fill(Color.brandPrimary))
                    .shadow(color: Color.brandPrimary.opacity(0.45), radius: 16, x: 0, y: 8)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(fabScrollScale * fabPressScale)
        .animation(.easeInOut(duration: 0.2), value: fabScrollScale)
        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: fabPressScale)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !fabIsPressed {
                        fabIsPressed = true
                        withAnimation(.easeIn(duration: 0.07)) {
                            fabPressScale = 0.86
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .onEnded { _ in
                    fabIsPressed = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                        fabPressScale = 1.0
                    }
                    fabRippling = false
                    fabRippling = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        fabRippling = false
                    }
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.72)) {
                        showingEntryPicker = true
                    }
                }
        )
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            homeScrollableColumn
            .background(Color(hex: "F6F5F3").ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(Color(hex: "F6F5F3"), for: .navigationBar)
            .keyboardDoneToolbar()
        }
        .background(Color(hex: "F6F5F3").ignoresSafeArea())
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
        .sheet(isPresented: $showingSharedTagPicker) {
            SharedTagPickerSheet(homeVisibilityMode: ())
                .presentationDetents([.large])
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

                Button { appState.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, 4)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Total Spent")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "8F9E94"))

                periodToggle

                Spacer()
            }

            HStack(alignment: .top, spacing: 2) {
                Text("$")
                    .font(Font.custom("Fraunces9pt-LightItalic", size: 28))
                    .foregroundStyle(Color(hex: "BFBAB3"))
                    .padding(.top, 10)

                Text(formatAnimatedTotal())
                    .font(Font.custom("Fraunces9pt-LightItalic", size: 64))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .kerning(-3)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 16)
        .padding(.bottom, Spacing.smd)
    }

    private var periodToggle: some View {
        Menu {
            ForEach([PeriodFilter.allTime, .thisFinancialYear, .thisYear, .thisMonth], id: \.label) { filter in
                Button {
                    withAnimation(nil) { periodFilter = filter }
                } label: {
                    Label(filter.label, systemImage: periodFilter == filter ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(periodFilter.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Color(hex: "EDEAE4"))
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
                .stroke(isSearchFocused ? Color.brandPrimary : Color.borderColor, lineWidth: isSearchFocused ? 1 : 0.5)
        )
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Tag Row

    /// Standalone tags and groups with `showOnHome`, A–Z (same pill row).
    private var homeVisibleTags: [TagModel] {
        tags
            .filter { $0.showOnHome && $0.parentId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

                    Button { showingSharedTagPicker = true } label: {
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

    /// Extra bottom padding inside empty-state scroll; main clearance comes from `safeAreaInset`.
    private let emptyStateBottomSafeInset: CGFloat = 40

    private var emptyState: some View {
        ScrollView {
            VStack {
                Spacer(minLength: UIScreen.main.bounds.height * 0.14)
                Group {
                    if hasActiveFilters {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No matching expenses",
                            message: "Try adjusting your search or filters."
                        )
                    } else {
                        EmptyStateView(
                            icon: "receipt",
                            title: "No expenses yet",
                            message: "Tap + to add your first expense\nand get started."
                        )
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, emptyStateBottomSafeInset)
                Spacer(minLength: UIScreen.main.bounds.height * 0.2)
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !isSelecting {
                    HStack {
                        Spacer()
                        fabButton
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, adManager.shouldShowBannerAd ? 12 : 28)
                }
                if adManager.shouldShowBannerAd {
                    BannerAdView()
                }
            }
            .background(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F6F5F3"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expense List

    private struct DayExpenseGroup: Identifiable {
        let id: String
        let dayStart: Date
        let items: [ExpenseModel]
    }

    private var dayGroups: [DayExpenseGroup] {
        let cal = Calendar.current
        var buckets: [Date: [ExpenseModel]] = [:]
        for expense in filteredExpenses {
            let d = cal.startOfDay(for: expense.date)
            buckets[d, default: []].append(expense)
        }
        let sortedDays = buckets.keys.sorted(by: >)
        return sortedDays.map { day in
            DayExpenseGroup(
                id: "\(day.timeIntervalSince1970)",
                dayStart: day,
                items: (buckets[day] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    private func daySectionTitle(for dayStart: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(dayStart) { return "Today" }
        if cal.isDateInYesterday(dayStart) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: dayStart)
    }

    @ViewBuilder
    private func groupCardRowBackground(index: Int, count: Int) -> some View {
        let r = Radius.lg
        if count == 1 {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color.surface)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 2)
        } else if index == 0 {
            UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: r,
                style: .continuous
            )
            .fill(Color.surface)
            .frame(maxWidth: .infinity)
        } else if index == count - 1 {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.surface)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 2)
        } else {
            Rectangle()
                .fill(Color.surface)
                .frame(maxWidth: .infinity)
        }
    }

    private func keywordSearchText(for expense: ExpenseModel) -> String {
        [expense.expenseDescription, expense.merchant]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func hasReceiptPhoto(_ expense: ExpenseModel) -> Bool {
        expense.attachmentKey != nil || expense.attachmentData != nil
    }

    private func resolveIcon(name: String, tag: String?) -> String {
        HomeExpenseIconResolver.match(name: name, tag: tag).symbol
    }

    private func resolveIconBackground(name: String, tag: String?) -> Color {
        HomeExpenseIconResolver.match(name: name, tag: tag).category.tintColor
    }

    private var expenseList: some View {
        List {
            Color.clear
                .frame(height: 1)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeListScrollAnchorKey.self,
                            value: proxy.frame(in: .named("homeScroll")).minY
                        )
                    }
                )

            ForEach(dayGroups) { group in
                Group {
                    Text(daySectionTitle(for: group.dayStart).uppercased())
                        .font(Fonts.caption(11))
                        .foregroundStyle(Color.textMuted)
                        .tracking(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Spacing.lg)
                        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: Spacing.xs, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, expense in
                        groupedExpenseRow(group: group, index: index, expense: expense)
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !isSelecting {
                    HStack {
                        Spacer()
                        fabButton
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, adManager.shouldShowBannerAd ? 12 : 28)
                }
                if adManager.shouldShowBannerAd {
                    BannerAdView()
                }
            }
            .background(Color.clear)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F6F5F3"))
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(HomeListScrollAnchorKey.self) { minY in
            if minY < -16 {
                if !isHeaderCollapsed {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHeaderCollapsed = true
                    }
                }
            } else if minY > 2 {
                if isHeaderCollapsed {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHeaderCollapsed = false
                    }
                }
            }

            let newOffset = minY
            if previousScrollOffset != 0 {
                let delta = newOffset - previousScrollOffset
                if delta > 2 {
                    fabScrollScale = 0.9
                } else if delta < -2 {
                    fabScrollScale = 1.0
                }
            }
            previousScrollOffset = newOffset
        }
    }

    @ViewBuilder
    private func groupedExpenseRow(group: DayExpenseGroup, index: Int, expense: ExpenseModel) -> some View {
        let tag = primaryTag(for: expense)
        let isSelected = selectedExpenseIds.contains(expense.id)
        let nameKey = keywordSearchText(for: expense)
        let primaryTagName = primaryTag(for: expense)?.name

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: isSelected ? .regular : .light))
                        .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary.opacity(0.55))
                        .frame(width: 44)
                }

                ExpenseCard(
                    thumbnailImage: thumbnailImage(for: expense),
                    hasReceiptAttachment: hasReceiptPhoto(expense),
                    iconSystemName: resolveIcon(name: nameKey, tag: primaryTagName),
                    iconBackground: resolveIconBackground(name: nameKey, tag: primaryTagName),
                    description: expense.expenseDescription ?? "Expense",
                    merchant: expense.merchant,
                    amountCents: expense.amountCents,
                    currency: expense.currency,
                    date: expense.date,
                    primaryTagLabel: primaryTagDisplayLabel(for: expense),
                    primaryTagColor: tag?.tagColor,
                    additionalTagCount: additionalTagCount(for: expense)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if index < group.items.count - 1 {
                Divider()
                    .padding(.leading, 58)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .onLongPressGesture(minimumDuration: 0.2) {
            if !isSelecting {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.prepare()
                if #available(iOS 17.0, *) {
                    gen.impactOccurred(intensity: 1.0)
                } else {
                    gen.impactOccurred()
                }
                enterSelectionMode(preselecting: expense.id)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(groupCardRowBackground(index: index, count: group.items.count))
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

// MARK: - Expense icon resolver (keywords → SF Symbol + tint category)

private enum HomeExpenseIconResolver {
    enum Category {
        case foodDrink
        case transport
        case techOffice
        case subscription
        case health
        case work
        case generic

        var tintColor: Color {
            switch self {
            case .foodDrink: return Color(hex: "A67C52").opacity(0.12)
            case .transport: return Color(hex: "8B8680").opacity(0.12)
            case .techOffice: return Color(hex: "5B8FC7").opacity(0.12)
            case .subscription: return Color(hex: "D48BC9").opacity(0.12)
            case .health: return Color(hex: "E57373").opacity(0.12)
            case .work: return Color(hex: "5B8A72").opacity(0.12)
            case .generic: return Color(hex: "8B8680").opacity(0.12)
            }
        }
    }

    private struct Rule {
        let keywords: [String]
        let symbol: String
        let category: Category
    }

    static func match(name: String, tag: String?) -> (symbol: String, category: Category) {
        let sources = [name, tag ?? ""].filter { !$0.isEmpty }
        for s in sources {
            let lower = s.lowercased()
            for rule in rules {
                for kw in rule.keywords where lower.contains(kw) {
                    return (rule.symbol, rule.category)
                }
            }
        }
        return ("doc.fill", .generic)
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["coffee", "cafe", "latte"], symbol: "cup.and.saucer.fill", category: .foodDrink),
        Rule(keywords: ["groceries", "supermarket", "woolworths", "coles", "aldi"], symbol: "cart.fill", category: .foodDrink),
        Rule(keywords: ["tyre", "tyres", "car", "mechanic", "rego", "vehicle"], symbol: "car.fill", category: .transport),
        Rule(keywords: ["fuel", "petrol"], symbol: "fuelpump.fill", category: .transport),
        Rule(keywords: ["flight", "airfare", "qantas", "jetstar", "virgin"], symbol: "airplane", category: .transport),
        Rule(keywords: ["bus", "train", "opal", "transit"], symbol: "tram.fill", category: .transport),
        Rule(keywords: ["parking", "toll"], symbol: "p.square.fill", category: .transport),
        Rule(keywords: ["keyboard", "keycaps"], symbol: "keyboard.fill", category: .techOffice),
        Rule(keywords: ["monitor", "display", "screen"], symbol: "display", category: .techOffice),
        Rule(keywords: ["mouse", "trackpad"], symbol: "computermouse.fill", category: .techOffice),
        Rule(keywords: ["cable", "adapter", "hub", "usb", "hdmi"], symbol: "cable.connector", category: .techOffice),
        Rule(keywords: ["desk light", "lamp", "light"], symbol: "lightbulb.fill", category: .techOffice),
        Rule(keywords: ["domain", "namecheap", "cloudflare"], symbol: "globe", category: .techOffice),
        Rule(keywords: ["api", "credits", "aws", "hosting", "cloud"], symbol: "cloud.fill", category: .techOffice),
        Rule(keywords: ["subscription", "plan", "monthly", "annual"], symbol: "arrow.2.circlepath", category: .subscription),
        Rule(keywords: ["software", "license", "saas"], symbol: "laptopcomputer", category: .techOffice),
        Rule(keywords: ["doctor", "gp", "medical", "hospital"], symbol: "stethoscope", category: .health),
        Rule(keywords: ["pharmacy", "chemist"], symbol: "pills.fill", category: .health),
        Rule(keywords: ["dentist", "dental"], symbol: "mouth.fill", category: .health),
        Rule(keywords: ["gym", "fitness"], symbol: "dumbbell.fill", category: .health),
        Rule(keywords: ["haircut", "barber", "salon"], symbol: "scissors", category: .health),
        Rule(keywords: ["lunch", "dinner", "food", "meal"], symbol: "fork.knife", category: .foodDrink),
        Rule(keywords: ["bar", "drinks", "pub"], symbol: "wineglass.fill", category: .foodDrink),
        Rule(keywords: ["takeaway", "ubereats", "doordash", "menulog"], symbol: "bag.fill", category: .foodDrink),
        Rule(keywords: ["hotel", "accommodation", "airbnb"], symbol: "bed.double.fill", category: .transport),
        Rule(keywords: ["invoice", "reimbursement"], symbol: "doc.text.fill", category: .work),
        Rule(keywords: ["delivery", "shipping", "postage"], symbol: "shippingbox.fill", category: .transport)
    ]
}

// MARK: - Export With Selection Item

private struct ExportWithSelectionItem: Identifiable {
    let id = UUID()
    let expenses: [ExpenseModel]
}

// MARK: - List scroll (header collapse)

private struct HomeListScrollAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Period Filter

enum PeriodFilter {
    case selected
    case allTime
    case thisFinancialYear
    case thisYear
    case thisMonth

    var label: String {
        switch self {
        case .selected: "Selected"
        case .allTime: "All Time"
        case .thisFinancialYear: "Financial Year"
        case .thisYear: "This Year"
        case .thisMonth: "This Month"
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
