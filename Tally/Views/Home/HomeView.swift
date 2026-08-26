import SwiftUI
import OSLog
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AdManager.self) private var adManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date, order: .reverse) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var searchText = ""
    @State private var showingEntryPicker = false
    @State private var selectedEntryMode: AddEntryMode?
    @State private var periodFilter: PeriodFilter = .allTime
    @State private var isHeaderCollapsed = false
    @State private var showingFilteredExport = false
    @State private var isSelecting = false
    @State private var selectedExpenseIds: Set<String> = []
    @State private var exportWithSelectionItem: ExportWithSelectionItem?
    @State private var showingShred = false
    @State private var shredTick = 0
    @FocusState private var isSearchFocused: Bool
    @State private var selectedTab: TallyTab = .home
    @State private var showingFilterSheet = false
    @State private var isKeyboardVisible = false
    @State private var homeBarTagId: String? = nil
    @AppStorage("homeHeroPeriod") private var selectedHeroPeriod: HeroPeriod = .month
    @State private var showingPeriodDetail = false
    @State private var multiReceiptBatch: MultiReceiptBatch?
    // Images picked inside the Add-expense cover, held until that cover finishes
    // dismissing — SwiftUI can't present the review cover while another is still
    // dismissing, so it's handed over in the cover's onDismiss, not on a timer.
    @State private var pendingReviewImages: [UIImage] = []
    @State private var sharedPDFItem: SharedPDFItem?
    @State private var sharedImageItem: SharedImageItem?
    @State private var landedExpenseId: String? = nil
    @State private var showingCelebration = false
    @State private var celebrationAmountCents = 0
    @State private var celebrationCurrency = ""
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""
    @State private var showingSubscription = false
    @State private var showingDailyUpgradePrompt = false
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
        case .lastMonth:
            let cal = Calendar.current
            guard let lastMonth = cal.date(byAdding: .month, value: -1, to: Date()) else { return [] }
            return activeExpenses.filter { cal.isDate($0.date, equalTo: lastMonth, toGranularity: .month) }
        case .custom(let start, let end):
            let cal = Calendar.current
            let from = cal.startOfDay(for: start)
            let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
            return activeExpenses.filter { $0.date >= from && $0.date < to }
        }
    }

    private var filteredExpenses: [ExpenseModel] {
        var result = periodExpenses

        // Home bar quick-filter (single tag, independent of the advanced filter)
        if let tagId = homeBarTagId {
            result = result.filter { $0.resolvedTagIds.contains(tagId) }
        }

        if appState.filterRecurringOnly {
            result = result.filter { $0.isRecurring }
        }

        // A currency filter narrows the list to that currency (the total already
        // resolves to it via activeCurrency).
        if let fc = appState.filterCurrency {
            result = result.filter { $0.currency == fc }
        }

        if appState.hasTagFilters {
            result = result.filter { expense in
                for filterId in appState.activeFilterIds {
                    if appState.groupFilterIds.contains(filterId) {
                        // Match children of the group or the group id itself
                        // (expenses can be tagged with a group directly).
                        let childIds = tags.filter { $0.parentId == filterId }.map(\.id)
                        if !expense.resolvedTagIds.contains(filterId)
                            && !expense.resolvedTagIds.contains(where: { childIds.contains($0) }) {
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
            let tagNames = tagById.mapValues { $0.name.lowercased() }
            result = result.filter { expense in
                (expense.expenseDescription?.lowercased().contains(query) ?? false)
                || (expense.merchant?.lowercased().contains(query) ?? false)
                || (expense.notes?.lowercased().contains(query) ?? false)
                || expense.resolvedTagIds.contains { tagNames[$0]?.contains(query) == true }
            }
        }
        return result
    }

    /// Picks up receipts deposited by the TallyShare extension and routes them
    /// into the review flows — images to multi-receipt review, PDFs to the
    /// add-expense file flow, one at a time. Never interrupts an open flow;
    /// leftovers are picked up when the current cover dismisses or on the
    /// next foreground.
    private func consumeSharedInbox() {
        guard multiReceiptBatch == nil, selectedEntryMode == nil,
              sharedPDFItem == nil, sharedImageItem == nil else { return }
        let items = SharedInboxService.pendingItems()
        guard !items.isEmpty else { return }

        let images = items.filter { !$0.isPDF }.compactMap { item -> UIImage? in
            let image = SharedInboxService.loadImage(item)
            SharedInboxService.remove(item)
            return image
        }
        // One shared receipt goes straight to the single-expense review page.
        if images.count == 1, let only = images.first {
            sharedImageItem = SharedImageItem(image: only)
            return
        }
        if !images.isEmpty {
            // Nothing else is presenting here (guarded above), so bind the images
            // to the item and present directly — no timer needed.
            multiReceiptBatch = MultiReceiptBatch(images: images)
            return
        }

        if let pdf = items.first(where: { $0.isPDF }),
           let claimedURL = SharedInboxService.claimPDF(pdf) {
            sharedPDFItem = SharedPDFItem(url: claimedURL)
        }
    }

    private func monthlyTotalCents(for currency: String) -> Int {
        let cal = Calendar.current
        let now = Date()
        return activeExpenses
            .filter { $0.currency == currency && cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func periodExpensesForHero(_ period: HeroPeriod) -> [ExpenseModel] {
        let range = period.dateRange(financialYearStart: appState.currentFinancialYearStart)
        var result = activeExpenses.filter { $0.date >= range.start && $0.date <= range.end }
        if let tagId = homeBarTagId {
            result = result.filter { $0.resolvedTagIds.contains(tagId) }
        }
        return result
    }

    /// All active expenses, filtered only by the pinned home-bar tag (no period
    /// window) — the monthly report pages across months from this.
    private var homeBarFilteredExpenses: [ExpenseModel] {
        guard let tagId = homeBarTagId else { return activeExpenses }
        return activeExpenses.filter { $0.resolvedTagIds.contains(tagId) }
    }

    // Built once per render; all per-row tag lookups use this instead of linear scans.
    private var tagById: [String: TagModel] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private func tagsFor(_ expense: ExpenseModel) -> [TagModel] {
        let map = tagById
        return expense.resolvedTagIds.compactMap { map[$0] }
    }

    private func primaryTag(for expense: ExpenseModel) -> TagModel? {
        tagsFor(expense).first
    }

    /// Label for the first tag only (used in list row pill).
    private func primaryTagDisplayLabel(for expense: ExpenseModel) -> String? {
        let map = tagById
        guard let first = expense.resolvedTagIds.first.flatMap({ map[$0] }) else { return nil }
        if let parentId = first.parentId, let group = map[parentId] {
            return "\(group.name) › \(first.name)"
        }
        return first.name
    }

    private func additionalTagCount(for expense: ExpenseModel) -> Int {
        let map = tagById
        let n = expense.resolvedTagIds.filter { map[$0] != nil }.count
        return n > 1 ? n - 1 : 0
    }

    private var homeScrollableColumn: some View {
        VStack(spacing: 0) {
            // App bar — always visible
            appBar

            // Spending card — collapses when user scrolls down, reveals on scroll up
            if !isHeaderCollapsed && searchText.isEmpty {
                SpendingSummaryCard(
                    selectedPeriod: $selectedHeroPeriod,
                    allExpenses: activeExpenses,
                    allTags: Array(tags),
                    homeBarTagId: homeBarTagId,
                    onPeriodTap: {
                        showingPeriodDetail = true
                    },
                    onExportTap: {
                        appState.showingExport = true
                    }
                )
                .padding(.top, 6)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            // Persistent header (search + pinned tags) — opaque so the collapsing
            // hero card can't be seen sliding behind it during the animation.
            VStack(spacing: 0) {
                // Search bar — always visible
                searchBar
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                // Home tag bar — always visible (sticky above the list, does not collapse with header)
                HomeTagBar(selectedTagId: $homeBarTagId)
                    .padding(.top, 2)
            }
            // Opaque so the collapsing hero can't ghost behind it. A soft top-to-
            // bottom blend (light parchment easing to the list's top tint) means the
            // bottom edge meets the list with no hard seam.
            .background(
                LinearGradient(
                    colors: [Color(hex: "F0EDE6"), Color(hex: "E9ECE2")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Active filter chips — only renders when filters are active
            ActiveFiltersRow(periodFilter: $periodFilter)
                .animation(.easeOut(duration: 0.2), value: appState.activeFilterIds)
                .animation(.easeOut(duration: 0.2), value: periodFilter)

            // Free tier: banner sits beneath the pinned tags, above the list —
            // well clear of the FAB and tab bar at the bottom of the screen.
            if adManager.shouldShowBannerAd {
                BannerAdView()
                    .padding(.top, 4)
            }

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
    }

    /// "Rise" — warm parchment easing into the hero's forest green toward the
    /// bottom of the screen. Sits behind the Home content as a single layer.
    static let riseGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "F0EDE6"), location: 0.0),
            .init(color: Color(hex: "E6ECE0"), location: 0.36),
            .init(color: Color(hex: "C0D1BB"), location: 0.72),
            .init(color: Color(hex: "9DB598"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .bottom) {
            homeScrollableColumn
                .background(
                    ZStack {
                        Color(hex: "F0EDE6")
                        Self.riseGradient.opacity(0.65)   // dialed back further
                    }
                    .ignoresSafeArea()
                )

            // Keep both views alive in memory — opacity-based switching prevents
            // the "closes on first open" bug that occurs when views are destroyed/recreated.
            ReportsView()
                .background(Color(hex: "F0EDE6").ignoresSafeArea())
                .opacity(selectedTab == .reports ? 1 : 0)
                .allowsHitTesting(selectedTab == .reports)
                .zIndex(50)

            TagsTabView()
                .background(Color(hex: "F0EDE6").ignoresSafeArea())
                .opacity(selectedTab == .tags ? 1 : 0)
                .allowsHitTesting(selectedTab == .tags)
                .zIndex(50)

            // Shred animation — behind the FAB and tab bar (below zIndex 60).
            if showingShred {
                ExpenseShredView()
                    .id(shredTick)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .zIndex(55)
            }

            if !isKeyboardVisible {
                TallyTabBar(selectedTab: $selectedTab) {
                    showingEntryPicker = true
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(60)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .expenseDeleted)) { _ in
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            shredTick += 1
            showingShred = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                showingShred = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .expenseLogged)) { notification in
            guard let id = notification.userInfo?["expenseId"] as? String else { return }
            landedExpenseId = id
            let aCents = notification.userInfo?["amountCents"] as? Int ?? 0
            let curr = notification.userInfo?["currency"] as? String ?? appState.defaultCurrency
            // Sound + confetti timed to end of dismiss animation (~0.35s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                ExpenseSoundService.shared.playExpenseLogged()
                celebrationAmountCents = aCents
                celebrationCurrency = curr
                withAnimation { showingCelebration = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                landedExpenseId = nil
                withAnimation { showingCelebration = false }
            }
        }
        .overlay {
            if showingCelebration {
                ExpenseCelebrationView(
                    amountCents: celebrationAmountCents,
                    currency: celebrationCurrency,
                    monthlyTotalCents: monthlyTotalCents(for: celebrationCurrency)
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .sheet(isPresented: $showingEntryPicker) {
            AddEntryPicker { mode in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedEntryMode = mode
                }
            }
            .presentationDetents([.height(490)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color(hex: "F0EDE6"))
        }
        .fullScreenCover(item: $selectedEntryMode, onDismiss: {
            // The Add-expense cover has now fully dismissed; safe to present the
            // review cover with the images it handed over. Doing this here rather
            // than on a timer removes the empty-screen race for good.
            if !pendingReviewImages.isEmpty {
                multiReceiptBatch = MultiReceiptBatch(images: pendingReviewImages)
                pendingReviewImages = []
            }
        }) { mode in
            if mode == .bulkImport {
                AddMultipleExpensesView()
            } else {
                AddExpenseView(
                    initialMode: mode,
                    onMultiReceiptImages: { images in
                        // Stash the images and dismiss AddExpenseView; the review
                        // cover is presented in this cover's onDismiss above.
                        pendingReviewImages = images
                        selectedEntryMode = nil
                    }
                )
            }
        }
        .fullScreenCover(item: $multiReceiptBatch, onDismiss: {
            consumeSharedInbox()
        }) { batch in
            MultiReceiptReviewView(
                images: batch.images,
                onCancel: { multiReceiptBatch = nil },
                onDone: { multiReceiptBatch = nil }
            )
        }
        .fullScreenCover(item: $sharedPDFItem, onDismiss: {
            consumeSharedInbox()
        }) { item in
            AddExpenseView(initialMode: .uploadFile, initialFileURL: item.url)
        }
        .fullScreenCover(item: $sharedImageItem, onDismiss: {
            consumeSharedInbox()
        }) { item in
            AddExpenseView(initialMode: .photoLibrary, initialImage: item.image)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                consumeSharedInbox()
                maybeShowDailyUpgradePrompt()
            }
        }
        .task {
            consumeSharedInbox()
            appState.recordFirstLaunchIfNeeded()
            maybeShowDailyUpgradePrompt()
        }
        .sheet(isPresented: $showingProUpsell) {
            ProFeatureSheet(featureName: proFeatureName, limitReached: proFeatureName == "CSV export")
        }
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
        .sheet(isPresented: $showingDailyUpgradePrompt) {
            SubscriptionView()
        }
        .sheet(isPresented: $appState.showingExport) {
            GlobalExportSheet()
        }
        .sheet(isPresented: $showingFilteredExport) {
            SelectedExportSheet(
                expenses: filteredExpenses,
                filterLabel: activeFilterLabel
            )
        }
        .sheet(item: $exportWithSelectionItem) { item in
            GlobalExportSheet(initialSelection: item.expenses)
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheet(periodFilter: $periodFilter)
        }
        .sheet(isPresented: $showingPeriodDetail) {
            PeriodDetailView(
                period: selectedHeroPeriod,
                expenses: periodExpensesForHero(selectedHeroPeriod),
                tags: Array(tags),
                allExpenses: homeBarFilteredExpenses
            )
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - App Bar

    private var appBar: some View {
        HStack(alignment: .top) {
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

                // Persistent upgrade affordance for free users, left of Settings.
                if !appState.isPro {
                    Button {
                        showingSubscription = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Go Pro")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    appState.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "4A5E50"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "EDEAE4"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, 4)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
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
                    .stroke(
                        isSearchFocused ? Color.brandPrimary : Color.borderColor,
                        lineWidth: isSearchFocused ? 1 : 0.5
                    )
            )

            Button {
                showingFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13))
                    Text("Filter")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(
                    appState.hasAnyFilter || periodFilter != .allTime
                        ? Color(hex: "2F402E")
                        : Color(hex: "4A5E50")
                )
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(
                            appState.hasAnyFilter || periodFilter != .allTime
                                ? Color(hex: "2F402E")
                                : Color(hex: "DEDAD2"),
                            lineWidth: appState.hasAnyFilter || periodFilter != .allTime ? 1 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Empty State

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || appState.hasAnyFilter
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
            Color.clear.frame(height: 90)
        }
        .scrollContentBackground(.hidden)
        // Transparent so the Home gradient shows through.
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expense List

    private struct DayExpenseGroup: Identifiable {
        let id: String
        let dayStart: Date
        let items: [ExpenseModel]
        /// Position of this group's first expense in the flattened list, so the
        /// inline-ad cadence can run continuously across day groups without a
        /// per-row lookup.
        let startIndex: Int
        /// Year to print as a divider *above* this group — the year that just
        /// ended. The list runs newest → oldest, so at the 2026→2025 boundary the
        /// divider caps the 2026 section and reads "2026", sitting right before
        /// December 2025. nil for the first group (no marker at the very top).
        let yearHeader: Int?
    }

    private var dayGroups: [DayExpenseGroup] {
        let cal = Calendar.current
        var buckets: [Date: [ExpenseModel]] = [:]
        for expense in filteredExpenses {
            let d = cal.startOfDay(for: expense.date)
            buckets[d, default: []].append(expense)
        }
        let sortedDays = buckets.keys.sorted(by: >)
        var offset = 0
        var prevYear: Int? = nil
        return sortedDays.map { day in
            let items = (buckets[day] ?? []).sorted { $0.date > $1.date }
            defer { offset += items.count }
            let year = cal.component(.year, from: day)
            // Label the year that is ending (the group above), only at a boundary.
            let header: Int? = (prevYear != nil && prevYear != year) ? prevYear : nil
            prevYear = year
            return DayExpenseGroup(
                id: "\(day.timeIntervalSince1970)",
                dayStart: day,
                items: items,
                startIndex: offset,
                yearHeader: header
            )
        }
    }

    private var inlineAdRow: some View {
        InlineUpgradeAd()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private static let daySectionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private func daySectionTitle(for dayStart: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(dayStart) { return "Today" }
        if cal.isDateInYesterday(dayStart) { return "Yesterday" }
        return Self.daySectionFormatter.string(from: dayStart)
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
            // UIKit KVO-based detector — SwiftUI preference keys don't propagate
            // reliably from inside List cells (UICollectionView) on iOS 16+.
            ListScrollDetector { offset, maxOffset in
                // heroClearance guards a jitter loop: collapsing makes the list
                // taller and can push the offset back under the expand threshold
                // on a barely-overflowing list, so only collapse when enough
                // content remains below to absorb the hero's height.
                let heroClearance: CGFloat = 260
                withAnimation(.easeInOut(duration: 0.4)) {
                    if offset > 30 && maxOffset - offset > heroClearance { isHeaderCollapsed = true }
                    if offset < 10 { isHeaderCollapsed = false }
                }
            }
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(dayGroups) { group in
                Group {
                    if let headerYear = group.yearHeader {
                        Text(String(headerYear))
                            .font(Font.dmSerifDisplay(24))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                            .padding(.top, 22)
                            .padding(.bottom, 6)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    Text(daySectionTitle(for: group.dayStart))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.bottom, 4)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: Spacing.xs, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, expense in
                        LandingExpenseRow(isLanding: expense.id == landedExpenseId) {
                            groupedExpenseRow(group: group, index: index, expense: expense)
                        }

                        // Free tier: an ad after every 15th expense, counted
                        // across the whole list rather than per day group —
                        // otherwise a run of single-expense days would stack
                        // ads back to back.
                        if adManager.shouldShowBannerAd,
                           (group.startIndex + index + 1) % 15 == 0 {
                            inlineAdRow
                        }
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Reserve the tab bar height. The banner now sits above the list
            // (beneath the pinned tags), so it needs no bottom clearance.
            Color.clear.frame(height: 90)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        // Transparent so the Home gradient shows through.
        .background(Color.clear)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func groupedExpenseRow(group: DayExpenseGroup, index: Int, expense: ExpenseModel) -> some View {
        let tag = primaryTag(for: expense)
        let isSelected = selectedExpenseIds.contains(expense.id)
        let nameKey = keywordSearchText(for: expense)
        let primaryTagName = tag?.name

        // Use the tag's stored SF Symbol, falling back to the name-mapping, then the keyword resolver.
        let tagSymbol: String = {
            if let stored = tag?.symbolName { return stored }
            if let icon  = tag?.icon        { return icon   }
            if let name  = primaryTagName   { return TagSymbolMap.symbol(for: name) }
            let fallback = keywordSearchText(for: expense)
            return HomeExpenseIconResolver.match(name: fallback, tag: primaryTagName).symbol
        }()
        let tagIconBg: Color = tag?.tagColor.primaryColor.opacity(0.15)
            ?? resolveIconBackground(name: nameKey, tag: primaryTagName)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: isSelected ? .regular : .light))
                        .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary.opacity(0.55))
                        .frame(width: 44)
                }

                ExpenseCard(
                    receiptCacheKey: hasReceiptPhoto(expense) ? (expense.attachmentKey ?? expense.id) : nil,
                    receiptAttachmentKey: expense.attachmentKey,
                    receiptAttachmentData: expense.attachmentData,
                    iconEmoji: tag?.displayEmoji,
                    iconSystemName: tagSymbol,
                    iconBackground: tagIconBg,
                    description: expense.expenseDescription ?? "Expense",
                    merchant: expense.merchant,
                    notes: expense.notes,
                    amountCents: expense.amountCents,
                    currency: expense.currency,
                    primaryTagLabel: primaryTagDisplayLabel(for: expense),
                    primaryTagColor: tag?.tagColor,
                    additionalTagCount: additionalTagCount(for: expense)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if index < group.items.count - 1 {
                Color(hex: "F0EDE6")
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !isSelecting else { return }
                    let gen = UIImpactFeedbackGenerator(style: .heavy)
                    gen.prepare()
                    if #available(iOS 17.0, *) {
                        gen.impactOccurred(intensity: 1.0)
                    } else {
                        gen.impactOccurred()
                    }
                    enterSelectionMode(preselecting: expense.id)
                }
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(groupCardRowBackground(index: index, count: group.items.count))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                // No confirmation on swipe — the gesture is deliberate enough.
                Button(role: .destructive) {
                    deleteExpense(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func deleteExpense(_ expense: ExpenseModel) {
        expense.deletedAt = Date()
        expense.updatedAt = Date()
        if let key = expense.attachmentKey {
            Task { await AttachmentService.shared.deleteAttachment(key: key) }
        }
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .expenseDeleted, object: nil)
        } catch {
            Log.data.error("deleting expense failed: \(error.localizedDescription, privacy: .public)")
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
            Log.data.error("deleting expenses failed: \(error.localizedDescription, privacy: .public)")
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

    /// First open of the day, at most every 3 days, never in the first 3 days.
    /// Suppressed while any other sheet is already up so prompts never stack.
    private func maybeShowDailyUpgradePrompt() {
        guard appState.shouldShowUpgradePrompt else { return }
        guard !showingEntryPicker, multiReceiptBatch == nil, !appState.showingSettings,
              !appState.showingExport, appState.selectedExpenseId == nil else { return }
        appState.recordUpgradePromptShown()
        showingDailyUpgradePrompt = true
    }

    private func exportExpensesAsCSV(_ expenses: [ExpenseModel]) {
        guard !expenses.isEmpty else { return }
        guard appState.canExportCSV else {
            proFeatureName = "CSV export"
            showingProUpsell = true
            return
        }

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

// MARK: - Landing animation wrapper for newly logged expenses

private struct LandingExpenseRow<Content: View>: View {
    let isLanding: Bool
    @ViewBuilder let content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var offsetY: CGFloat = 0

    var body: some View {
        content()
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
            .offset(y: offsetY)
            .onAppear { triggerAnimation() }
            .onChange(of: isLanding) { _, newVal in if newVal { triggerAnimation() } }
    }

    private func triggerAnimation() {
        guard isLanding else { return }
        // Set start state first, then defer animation one run loop so SwiftUI
        // renders the initial frame before animating to the final values.
        scale = 0.88; opacity = 0; offsetY = -18
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.60)) {
                scale = 1; opacity = 1; offsetY = 0
            }
        }
    }
}

// MARK: - UIKit scroll detector (replaces preference-key approach)
// SwiftUI List uses UICollectionView internally; preference values set inside
// List cells don't reliably propagate. KVO on UIScrollView.contentOffset works
// regardless of SwiftUI version or internal implementation details.

private struct ListScrollDetector: UIViewRepresentable {
    /// (contentOffset.y, maximum reachable contentOffset.y)
    var onScroll: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeUIView(context: Context) -> ScrollObserverUIView {
        let view = ScrollObserverUIView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ScrollObserverUIView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.onScroll = onScroll
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var onScroll: (CGFloat, CGFloat) -> Void
        private var observation: NSKeyValueObservation?

        init(onScroll: @escaping (CGFloat, CGFloat) -> Void) { self.onScroll = onScroll }

        func startObserving(_ scrollView: UIScrollView) {
            observation?.invalidate()
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                guard let self else { return }
                let maxOffset = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
                DispatchQueue.main.async { self.onScroll(sv.contentOffset.y, maxOffset) }
            }
        }

        deinit { observation?.invalidate() }
    }
}

// UIView subclass so we can hook didMoveToWindow and walk the superview chain
// to find the parent UIScrollView (UICollectionView is a UIScrollView subclass).
private final class ScrollObserverUIView: UIView {
    weak var coordinator: ListScrollDetector.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var view: UIView? = self.superview
            while let v = view {
                if let sv = v as? UIScrollView {
                    self.coordinator?.startObserving(sv)
                    return
                }
                view = v.superview
            }
        }
    }
}

// MARK: - Period Filter

enum PeriodFilter: Equatable {
    case selected
    case allTime
    case thisFinancialYear
    case thisYear
    case thisMonth
    case lastMonth
    case custom(start: Date, end: Date)

    var label: String {
        switch self {
        case .selected: "Selected"
        case .allTime: "All Time"
        case .thisFinancialYear: "Financial Year"
        case .thisYear: "This Year"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .custom: "Custom"
        }
    }

    var isCustom: Bool { if case .custom = self { return true }; return false }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
