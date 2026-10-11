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
    // Photos-style drag-to-select. Each visible row writes its frame (in global/
    // screen coordinates) into `rowFrameStore` while selecting — via onAppear/
    // onChange, not a PreferenceKey, because SwiftUI preferences don't propagate
    // reliably from List cells (same reason ListScrollDetector uses UIKit KVO).
    // A drag beginning in the leading checkmark column toggles each row as the
    // finger *enters* it; `dragLastRowId` is the row currently under the finger, so
    // dragging back over a row (a new entry) toggles it again — deselecting — while
    // lingering on one row does nothing.
    @State private var rowFrameStore = RowFrameStore()
    @State private var isDragSelecting = false
    @State private var dragLastRowId: String? = nil
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
    @State private var showingStatementImport = false
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
            // Nameplate — the Tally wordmark on paper, with Go Pro + settings.
            // Always visible; the controls that used to sit in the green hero
            // moved here (concept 1).
            nameplate

            // Spending hero — the green module (total + period + pins inside).
            // Collapses to a slim green pin rail on scroll. Hidden while searching.
            if searchText.isEmpty {
                if !isHeaderCollapsed {
                    SpendingSummaryCard(
                        selectedPeriod: $selectedHeroPeriod,
                        homeBarTagId: $homeBarTagId,
                        allExpenses: activeExpenses,
                        allTags: Array(tags),
                        onBreakdownTap: { showingPeriodDetail = true }
                    )
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    compactedHeader
                        .padding(.bottom, 4)
                        .transition(.opacity)
                }
            }

            // Persistent header (search + filter) — opaque so the collapsing hero
            // can't be seen sliding behind it during the animation.
            VStack(spacing: 0) {
                searchBar
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
            // Opaque so the collapsing hero can't ghost behind it. A soft top-to-
            // bottom blend (light parchment easing to the list's top tint) means the
            // bottom edge meets the list with no hard seam.
            .background {
                // Matches the top of the warm paper wash so the persistent header
                // blends into the ground with no seam (stays opaque so the
                // collapsing hero can't ghost behind it).
                LinearGradient(
                    colors: [Color(hex: "F3F0E7"), Color(hex: "EFE7D6")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // A background must never catch taps meant for the controls above it.
                .allowsHitTesting(false)
            }

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
                    // Floating close (X) at the top-right of the list while selecting.
                    .overlay(alignment: .topTrailing) {
                        if isSelecting {
                            selectionCloseButton
                                .padding(.trailing, 14)
                                .padding(.top, 8)
                                .transition(.opacity)
                        }
                    }
            }
        }
    }

    /// Native-looking circular close for multi-select — white circle, dark X,
    /// soft shadow so it reads as a floating control above the list.
    private var selectionCloseButton: some View {
        Button { exitSelectionMode() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "2F402E"))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// "Rise" — warm parchment easing into the hero's forest green toward the
    /// bottom of the screen. Sits behind the Home content as a single layer.
    static let riseGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "F0EDE6"), location: 0.0),
            .init(color: Color(hex: "E6ECE0"), location: 0.36),
            // Bottom two stops lightened ~25% toward white so it doesn't go as dark.
            .init(color: Color(hex: "D0DDCC"), location: 0.72),
            .init(color: Color(hex: "B6C8B2"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .bottom) {
            homeScrollableColumn
                .background(
                    // Warm paper wash — the home design-pass ground (concept 21).
                    LinearGradient(
                        colors: [Color(hex: "F3F0E7"), Color(hex: "E9E0CF")],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            // Keep tab views alive in memory — opacity-based switching prevents
            // the "closes on first open" bug that occurs when views are destroyed/recreated.
            // Insights = analytics (the page formerly labelled Reports).
            ReportsView()
                .background(Color(hex: "F0EDE6").ignoresSafeArea())
                .opacity(selectedTab == .insights ? 1 : 0)
                .allowsHitTesting(selectedTab == .insights)
                .zIndex(50)

            // Reports = the documents hub (build expense reports, export).
            ReportsHubView()
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

            // Tab bar (with the FAB) drops away in multi-select mode.
            if !isKeyboardVisible && !isSelecting {
                TallyTabBar(selectedTab: $selectedTab) {
                    showingEntryPicker = true
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(60)
            }

            // Multi-select bottom bar in the tab bar's place: share left, count
            // centre, delete right — mirroring the iOS Photos selection toolbar.
            if isSelecting {
                selectionBottomBar
                    .transition(.move(edge: .bottom))
                    .zIndex(62)
            }

            // Transient Undo toast for the last add/delete, above the tab bar.
            if selectedTab == .home, let undo = appState.pendingUndo {
                UndoToast(label: undo.label) {
                    performUndo(undo)
                } onExpire: {
                    if appState.pendingUndo?.id == undo.id { appState.pendingUndo = nil }
                }
                .id(undo.id)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(59)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: appState.pendingUndo)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .expenseDeleted)) { _ in
            Haptics.crisp()
            shredTick += 1
            showingShred = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
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
                    if mode == .statement {
                        // Pro-only: free users get the upsell instead of the flow.
                        if appState.isPro {
                            showingStatementImport = true
                        } else {
                            proFeatureName = "Statement import"
                            showingProUpsell = true
                        }
                    } else {
                        selectedEntryMode = mode
                    }
                }
            }
            .presentationDetents([.height(adManager.shouldShowBannerAd ? 560 : 490)])
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
        .fullScreenCover(item: $multiReceiptBatch, onDismiss: {
            consumeSharedInbox()
        }) { batch in
            MultiReceiptReviewView(
                images: batch.images,
                onCancel: { multiReceiptBatch = nil },
                onDone: { multiReceiptBatch = nil }
            )
        }
        .fullScreenCover(isPresented: $showingStatementImport) {
            StatementImportView(
                onCancel: { showingStatementImport = false },
                onDone: { showingStatementImport = false }
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
            // Multi-select share: export exactly these expenses, straight to the
            // format step — no period picker, no "last month" default.
            GlobalExportSheet(initialSelection: item.expenses, directSelection: true)
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

    // MARK: - Nameplate

    /// The Tally wordmark on paper, with the offline indicators, Go Pro and
    /// settings. Always visible — the controls that used to live in the green
    /// hero moved here so the green can scroll away cleanly (concept 1).
    private var nameplate: some View {
        HStack(alignment: .center) {
            Image("TallyLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 36)

            Spacer()

            HStack(spacing: 8) {
                if !syncEngine.isOnline {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
                if appState.isOffline {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.danger)
                }
                if !appState.isPro {
                    Button {
                        Haptics.tap()
                        showingSubscription = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Pro")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(hex: "DEDAD2"), lineWidth: 1))
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Haptics.tap()
                    appState.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "4A5E50"))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "E6E1D5"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, 8)
    }

    // MARK: - App Bar (legacy, retained for the search state)

    private var appBar: some View {
        HStack(alignment: .top) {
            // Wordmark removed — the gradient hero (expanded) and the condensed
            // green bar (collapsed) anchor the top instead. The offline indicator
            // keeps its leading slot.
            HStack(spacing: Spacing.sm) {
                if !syncEngine.isOnline {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
            }
            .frame(height: 36)

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

    // MARK: - Collapsed anchor (the slim green pin rail, concept 1 / v2)

    /// Shown in place of the hero once it scrolls away: a slim green rail that
    /// keeps the pinned tags on green (so they never restyle), under the paper
    /// nameplate. No total — that figure lives in the hero one scroll up.
    private var compactedHeader: some View {
        HomeTagBar(selectedTagId: $homeBarTagId, period: selectedHeroPeriod, onDark: true)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(hex: "365F49"), Color(hex: "1E3A2A")],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
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

    /// That day's total, scoped to the active currency like every other total in
    /// the app (no mixing across currencies).
    private func dayTotalLabel(for group: DayExpenseGroup) -> String {
        let cents = group.items
            .filter { $0.currency == appState.activeCurrency }
            .reduce(0) { $0 + $1.amountCents }
        return CurrencyFormatter.shared.format(cents: cents, currencyCode: appState.activeCurrency)
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
                if offset > 30 && maxOffset - offset > heroClearance {
                    withAnimation(.easeInOut(duration: 0.4)) { isHeaderCollapsed = true }
                }
                if offset < 10 {
                    // Reappear twice as fast as it collapses.
                    withAnimation(.easeInOut(duration: 0.2)) { isHeaderCollapsed = false }
                }
            }
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(dayGroups) { group in
                Group {
                    if let headerYear = group.yearHeader {
                        // Mirrors the receipt "DETAILS" divider: grey label, a thin
                        // rule each side, centred, with balanced padding so it sits
                        // midway between the groups it separates.
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color(hex: "636367").opacity(0.25))
                                .frame(height: 0.5)
                            Text(String(headerYear))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "636367"))
                                .tracking(1.0)
                                .monospacedDigit()
                            Rectangle()
                                .fill(Color(hex: "636367").opacity(0.25))
                                .frame(height: 0.5)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    // Day divider: date on the left, a hairline across, and that
                    // day's total on the right. Top-biased padding so it reads as
                    // the heading of the expenses directly beneath it.
                    HStack(spacing: 12) {
                        Text(daySectionTitle(for: group.dayStart).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "8E8E93"))
                            .tracking(1.5)
                        Rectangle()
                            .fill(Color(hex: "8E8E93").opacity(0.3))
                            .frame(height: 0.5)
                        // Only on multi-expense days — on a single-expense day the
                        // amount already sits on the card, so the header total is
                        // a duplicate.
                        if group.items.count >= 2 {
                            Text(dayTotalLabel(for: group))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "8E8E93"))
                                .monospacedDigit()
                        }
                    }
                    .opacity(0.85)
                    .padding(.horizontal, 20)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 6, trailing: 0))
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
        // Freeze the scroll while a drag-select is in flight so the finger tracks
        // rows cleanly. `including:` disables the gesture entirely unless we're in
        // selection mode, so normal scrolling is never affected.
        .scrollDisabled(isDragSelecting)
        .simultaneousGesture(dragSelectGesture, including: isSelecting ? .all : .subviews)
    }

    /// Drag-across selection. Only a drag that begins in the leading checkmark
    /// column (x < 60) is treated as a select-drag — anywhere else the List
    /// scrolls as normal, even while selecting.
    private var dragSelectGesture: some Gesture {
        // Global (screen) coordinates for both the finger and the stored row
        // frames, so they always share one origin — no reliance on a named
        // coordinate space resolving, which is what mis-mapped rows before.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard isSelecting, value.startLocation.x < 60 else { return }
                if !isDragSelecting {
                    isDragSelecting = true
                    dragLastRowId = nil
                }
                // Rows top→bottom (only the on-screen ones — scroll is frozen).
                let ordered = rowFrameStore.frames.sorted { $0.value.minY < $1.value.minY }
                guard let currentIndex = ordered.firstIndex(where: {
                    value.location.y >= $0.value.minY && value.location.y <= $0.value.maxY
                }) else { return }
                let currentId = ordered[currentIndex].key

                // First row of the drag toggles on its own.
                guard let lastId = dragLastRowId,
                      let lastIndex = ordered.firstIndex(where: { $0.key == lastId }) else {
                    dragLastRowId = currentId
                    toggleExpenseSelection(currentId)
                    UISelectionFeedbackGenerator().selectionChanged()
                    return
                }
                if currentId == lastId { return }

                // Toggle every row between the last one and the current one, so a
                // fast drag can't skip a row between samples; reversing direction
                // re-enters rows and toggles them back (deselect).
                let step = lastIndex < currentIndex ? 1 : -1
                for i in stride(from: lastIndex + step, through: currentIndex, by: step) {
                    toggleExpenseSelection(ordered[i].key)
                }
                dragLastRowId = currentId
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .onEnded { _ in
                isDragSelecting = false
                dragLastRowId = nil
            }
    }

    /// Records a row's global frame into `rowFrameStore` for drag-select hit-
    /// testing. Only active while selecting; onAppear/onChange keep it fresh as the
    /// user scrolls, onDisappear drops rows that scroll off so the finger can't
    /// match a stale off-screen frame. Writes to a plain class, so they never
    /// trigger a view update (the gesture just reads the values).
    @ViewBuilder
    private func rowFrameReader(id: String) -> some View {
        if isSelecting {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { rowFrameStore.frames[id] = frame }
                    .onChange(of: frame) { _, newFrame in rowFrameStore.frames[id] = newFrame }
                    .onDisappear { rowFrameStore.frames[id] = nil }
            }
        } else {
            Color.clear
        }
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
                    isStatementSource: expense.source == "statement_import",
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
                    additionalTagCount: additionalTagCount(for: expense),
                    showTrailingTagBar: true
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
        .background(rowFrameReader(id: expense.id))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            if isSelecting {
                // Instant, like native multi-select — no animation delay.
                toggleExpenseSelection(expense.id)
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
                // Full deep-red cell with just a white bin, matching the statement
                // review; keeps the smooth native swipe motion.
                Button(role: .destructive) {
                    deleteExpense(expense)
                } label: {
                    Image(systemName: "trash.fill")
                }
                .tint(Color(hex: "C0392B"))
            }
        }
    }

    /// Reverse the last add (soft-delete the ids) or delete (clear deletedAt).
    /// Expenses are fetched by id because a restore target isn't in `activeExpenses`.
    private func performUndo(_ action: AppState.UndoAction) {
        let ids = action.expenseIds
        let descriptor = FetchDescriptor<ExpenseModel>(predicate: #Predicate { ids.contains($0.id) })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for e in matches {
            e.deletedAt = (action.kind == .added) ? Date() : nil
            e.updatedAt = Date()
        }
        try? modelContext.save()
        appState.pendingUndo = nil
        Haptics.tap()
    }

    private func deleteExpense(_ expense: ExpenseModel) {
        expense.deletedAt = Date()
        expense.updatedAt = Date()
        // Keep the attachment: a soft-deleted expense sits in Recently Deleted and
        // can be restored with its receipt. The file is freed only on a permanent
        // delete from the bin.
        do {
            try modelContext.save()
            appState.pendingUndo = AppState.UndoAction(kind: .deleted, expenseIds: [expense.id], label: "Expense deleted")
            NotificationCenter.default.post(name: .expenseDeleted, object: nil)
        } catch {
            Log.data.error("deleting expense failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Selection Bottom Toolbar

    /// Multi-select toolbar in the tab bar's place: share (left), count (centre),
    /// delete (right) — mirroring the iOS Photos selection bar.
    private var selectionBottomBar: some View {
        HStack(spacing: 0) {
            selectionActionButton(icon: "square.and.arrow.up", fill: Color.actionGreen, iconOffsetY: -1.5) {
                shareSelected()
            }
            Spacer()
            Text("\(selectedExpenseIds.count) selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .monospacedDigit()
            Spacer()
            selectionActionButton(icon: "trash.fill", fill: Color(hex: "C0392B")) {
                deleteSelectedExpenses()
            }
        }
        .padding(.horizontal, 40)
        // Sit the icons just above the home indicator — a small gap below, so the
        // bar reads as anchored to the very bottom of the screen.
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(
            Color.white
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func shareSelected() {
        let selected = filteredExpenses.filter { selectedExpenseIds.contains($0.id) }
        guard !selected.isEmpty else { return }
        exportWithSelectionItem = ExportWithSelectionItem(expenses: selected)
    }

    /// One circular multi-select action (share / delete).
    private func selectionActionButton(icon: String, fill: Color, iconOffsetY: CGFloat = 0,
                                       action: @escaping () -> Void) -> some View {
        let enabled = !selectedExpenseIds.isEmpty
        return Button {
            Haptics.firm()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: iconOffsetY)   // square.and.arrow.up reads low without this
                .frame(width: 54, height: 54)
                .background(Circle().fill(enabled ? fill : Color.textMuted))
                .shadow(color: .black.opacity(enabled ? 0.28 : 0.1), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
        // Attachments are kept until a permanent delete from Recently Deleted.
        for expense in toDelete {
            expense.deletedAt = Date()
            expense.updatedAt = Date()
        }
        let ids = toDelete.map(\.id)
        do {
            try modelContext.save()
            if !ids.isEmpty {
                appState.pendingUndo = AppState.UndoAction(
                    kind: .deleted,
                    expenseIds: ids,
                    label: "Deleted \(ids.count) expense\(ids.count == 1 ? "" : "s")"
                )
            }
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

// MARK: - Row frame store (drag-to-select hit-testing)

/// Plain reference box holding each visible expense row's global frame. A class,
/// not @State/@Observable, so rows can write to it during layout callbacks
/// without triggering view updates; the drag gesture only reads it.
private final class RowFrameStore {
    var frames: [String: CGRect] = [:]
}

// MARK: - Undo toast

/// Bottom snackbar with an Undo action; self-dismisses after 5s via `.task`.
private struct UndoToast: View {
    let label: String
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "B8D9C0"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "2F402E"))
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            onExpire()
        }
    }
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
