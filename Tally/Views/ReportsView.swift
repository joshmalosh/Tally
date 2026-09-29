import SwiftUI
import OSLog
import SwiftData

struct ReportsView: View {
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil },
           sort: \ExpenseModel.date, order: .reverse) private var expenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Environment(AppState.self) private var appState

    @State private var selectedPeriod: ReportPeriod = .sixMonths
    @State private var selectedMonthOffset: Int = 0
    /// Measured content width of the By month card, so the bars can size to a
    /// shared 6-month scale (fill the width at ≤6 months, that same width scrolling
    /// at 12).
    @State private var byMonthWidth: CGFloat = 0

    enum ReportPeriod: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths   = "6M"
        case oneYear   = "1Y"
        case allTime   = "All"
    }

    // MARK: - Period filtering

    private var periodMonthCount: Int {
        switch selectedPeriod {
        case .threeMonths: return 3
        case .sixMonths:   return 6
        case .oneYear:     return 12
        case .allTime:     return 6
        }
    }

    /// Expenses in the default currency only — mixing currencies without a rate
    /// makes every total meaningless (an IDR expense blew up the sum).
    private var currencyExpenses: [ExpenseModel] {
        expenses.filter { $0.currency == appState.activeCurrency }
    }

    /// Calendar-month-aligned start of the display window: the first day of the
    /// earliest month the chart shows. Aligning the total's window to whole months
    /// (not a rolling date N months back) keeps the headline total equal to the sum
    /// of the visible monthly bars. nil for All Time (no lower bound).
    private var periodStart: Date? {
        guard selectedPeriod != .allTime else { return nil }
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .month, value: -(periodMonthCount - 1), to: Date())!
        return calendar.date(from: calendar.dateComponents([.year, .month], from: earliest))
    }

    /// Expenses within the selected display period.
    private var filteredExpenses: [ExpenseModel] {
        guard let start = periodStart else { return currencyExpenses }
        return currencyExpenses.filter { $0.date >= start }
    }

    /// Start of the window one full period back — the baseline for % comparison.
    private var previousPeriodStart: Date? {
        guard let start = periodStart else { return nil }
        return Calendar.current.date(byAdding: .month, value: -periodMonthCount, to: start)
    }

    /// Same window shifted one full period back — used for % comparison.
    private var previousPeriodExpenses: [ExpenseModel] {
        guard let start = periodStart, let previousStart = previousPeriodStart else { return [] }
        return currencyExpenses.filter { $0.date >= previousStart && $0.date < start }
    }

    /// The user's earliest logged expense in the active currency.
    private var earliestExpenseDate: Date? {
        currencyExpenses.map(\.date).min()
    }

    /// Only compare to a previous period once the app actually has data reaching
    /// back to the start of that period. Comparing a full year to a baseline the
    /// user never logged in produces nonsense like "+205883% vs previous year" — so
    /// if their history doesn't span the prior window, we show no comparison.
    private var hasComparableHistory: Bool {
        guard let prevStart = previousPeriodStart, let earliest = earliestExpenseDate else { return false }
        return earliest <= prevStart
    }

    // MARK: - Totals

    private var totalCents: Int {
        filteredExpenses.reduce(0) { $0 + $1.amountCents }
    }

    private var currentTotal: Double { Double(totalCents) / 100.0 }

    private var previousTotal: Double {
        Double(previousPeriodExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
    }

    private var comparisonText: String? {
        guard hasComparableHistory, previousTotal > 0 else { return nil }
        let change = (currentTotal - previousTotal) / previousTotal * 100.0
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs previous \(selectedPeriod == .allTime ? "period" : periodLabel)"
    }

    private var comparisonIsDown: Bool {
        hasComparableHistory && previousTotal > 0 && currentTotal < previousTotal
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .threeMonths: return "3 months"
        case .sixMonths:   return "6 months"
        case .oneYear:     return "year"
        case .allTime:     return "period"
        }
    }

    /// Dynamic heading over the period total — names the window ("6 Month Total").
    private var totalHeadingLabel: String {
        switch selectedPeriod {
        case .threeMonths: return "3 Month Total"
        case .sixMonths:   return "6 Month Total"
        case .oneYear:     return "12 Month Total"
        case .allTime:     return "All Time Total"
        }
    }

    /// Subtitle for the top-category card — period-wide, so it names the period.
    private var periodSubtitle: String {
        switch selectedPeriod {
        case .threeMonths: return "last 3 months"
        case .sixMonths:   return "last 6 months"
        case .oneYear:     return "last 12 months"
        case .allTime:     return "all time"
        }
    }

    // MARK: - Big-amount formatting (matches the month breakdown header)

    private var currencySymbol: String { CurrencyFormatter.shared.symbol(for: appState.activeCurrency) }
    private var showsCents: Bool { CurrencyFormatter.shared.usesDecimals(for: appState.activeCurrency) }
    private var dollarPart: String { CurrencyFormatter.shared.groupedWhole(cents: totalCents, currencyCode: appState.activeCurrency) }
    private var centsPart: String { String(format: "%02d", abs(totalCents % 100)) }

    // MARK: - Monthly average

    private var monthlyAverage: Double {
        let total = currentTotal
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear:   months = 12
        case .allTime:
            let oldest = currencyExpenses.last?.date ?? Date()
            months = max(1, Double(Calendar.current.dateComponents([.month], from: oldest, to: Date()).month ?? 1))
        }
        return total / months
    }

    private var previousYearMonthlyAverage: Double? {
        guard selectedPeriod != .allTime, hasComparableHistory else { return nil }
        guard !previousPeriodExpenses.isEmpty else { return nil }
        let total = previousTotal
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear:   months = 12
        case .allTime:   months = 1
        }
        return total / months
    }

    // MARK: - Top category

    private struct TagSpend: Identifiable {
        let id: String
        let name: String
        let color: Color
        let emoji: String
        let total: Double
        let expenses: [ExpenseModel]
    }

    private var topCategoryForPeriod: TagSpend? {
        var result: [String: [ExpenseModel]] = [:]
        for expense in filteredExpenses {
            // Anything without a resolvable tag (no tag, or a stale/deleted id) is
            // bucketed as uncategorised — so a dead tag id can't become its own
            // top category, which is why "Unknown" used to win every period.
            let tagId: String
            if let first = expense.resolvedTagIds.first, tags.contains(where: { $0.id == first }) {
                tagId = first
            } else {
                tagId = "untagged"
            }
            result[tagId, default: []].append(expense)
        }
        let breakdown = result.map { id, expList -> TagSpend in
            let total = expList.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            if id == "untagged" {
                return TagSpend(id: id, name: "Untagged", color: Color(hex: "8F9E94"),
                                emoji: "🏷️", total: total, expenses: expList)
            }
            let tag = tags.first { $0.id == id }
            return TagSpend(id: id,
                            name: tag?.name ?? "Untagged",
                            color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                            emoji: tag?.displayEmoji ?? "🏷️",
                            total: total, expenses: expList)
        }.sorted { $0.total > $1.total }
        // Prefer a real category; fall back to Untagged only if there's nothing else.
        return breakdown.first { $0.id != "untagged" } ?? breakdown.first
    }

    // MARK: - Monthly bar chart data

    private struct MonthBar: Identifiable {
        let id: String
        let label: String
        let total: Double
        let offset: Int  // 0 = current month
    }

    private var monthlyBars: [MonthBar] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<periodMonthCount).reversed().map { offset in
            let date  = calendar.date(byAdding: .month, value: -offset, to: now)!
            let comps = calendar.dateComponents([.year, .month], from: date)
            let total = filteredExpenses.filter {
                let ec = calendar.dateComponents([.year, .month], from: $0.date)
                return ec.year == comps.year && ec.month == comps.month
            }.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            let label = date.formatted(.dateTime.month(.abbreviated))
            return MonthBar(id: "\(comps.year!)-\(comps.month!)", label: label, total: total, offset: offset)
        }
    }

    private var maxMonthlyTotal: Double {
        monthlyBars.map(\.total).max() ?? 1
    }

    // MARK: - Selected month (for the inline breakdown)

    private var selectedMonthExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        let targetDate = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: now)!
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        return filteredExpenses.filter {
            let ec = calendar.dateComponents([.year, .month], from: $0.date)
            return ec.year == comps.year && ec.month == comps.month
        }
    }

    private var previousMonthExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        let targetDate = calendar.date(byAdding: .month, value: -(selectedMonthOffset + 1), to: now)!
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        return currencyExpenses.filter {
            let ec = calendar.dateComponents([.year, .month], from: $0.date)
            return ec.year == comps.year && ec.month == comps.month
        }
    }

    private var selectedMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: -selectedMonthOffset, to: Date()) ?? Date()
    }

    private var selectedMonthLabelFull: String {
        selectedMonthDate.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Formatting

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatAmountCompact(_ value: Double) -> String {
        if value >= 1_000 {
            return "$\(String(format: "%.1f", value / 1_000))k"
        }
        return "$\(formatAmount(value))"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        // Summary card: period total + monthly avg + top category.
                        summaryCard
                        // The month chart on its own card.
                        byMonthCard(proxy)
                        // The selected month's full breakdown, inline — the same
                        // component the home-screen breakdown uses.
                        PeriodBreakdownBody(
                            period: .month,
                            expenses: selectedMonthExpenses,
                            tags: Array(tags),
                            previousExpenses: previousMonthExpenses,
                            titleOverride: selectedMonthLabelFull.uppercased(),
                            allExpenses: [],
                            showsTopBar: false,
                            monthAnchorOverride: selectedMonthDate
                        )
                        InlineUpgradeAd()
                        Spacer(minLength: 100)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            #if DEBUG
            .onAppear {
                let byCurrency = Dictionary(grouping: expenses, by: \.currency).mapValues { $0.count }
                Log.data.debug("reports activeCurrency=\(appState.activeCurrency, privacy: .public) currencies=\(byCurrency.description, privacy: .public) filtered=\(filteredExpenses.count, privacy: .public) total=\(currentTotal, privacy: .private)")
            }
            #endif
        }
    }

    // MARK: - Header (title across the top, selector beneath — like Tags & Groups)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Insights")
                .font(Font.dmSerifDisplay(30))
                .foregroundStyle(Color(hex: "1C1C1E"))

            // Full-width segmented period selector.
            HStack(spacing: 3) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriod = period
                            selectedMonthOffset = 0
                        }
                    } label: {
                        Text(period.rawValue)
                            .font(.system(size: 12, weight: selectedPeriod == period ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(selectedPeriod == period ? Color(hex: "2F402E") : Color.clear)
                            .foregroundStyle(selectedPeriod == period ? Color.white : Color(hex: "8F9E94"))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
            .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Summary card (heading on cream + total + avg/top-cat + By month)

    private var cardDivider: some View {
        Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            periodTotalBlock
                .padding(16)
            cardDivider
            metricsDuo
                .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    /// By month chart on its own card (was the third section of the summary card).
    private func byMonthCard(_ proxy: ScrollViewProxy) -> some View {
        byMonthSection(proxy)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
            .padding(.horizontal, 16)
            .id("byMonth")
    }

    /// Compact total heading + period total + expense count + comparison.
    private var periodTotalBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(totalHeadingLabel.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.8)
            HStack(alignment: .top, spacing: 0) {
                Text(currencySymbol)
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 7)
                Text(dollarPart)
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .tracking(-2)
                if showsCents {
                    Text(".\(centsPart)")
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .padding(.top, 9)
                }
            }

            HStack(spacing: 6) {
                Text("\(filteredExpenses.count) expense\(filteredExpenses.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))

                if let comparison = comparisonText {
                    Text("·")
                        .foregroundStyle(Color(hex: "8F9E94"))
                    HStack(spacing: 3) {
                        Image(systemName: comparisonIsDown ? "arrow.down" : "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text(comparison)
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(comparisonIsDown ? Color(hex: "2F6B3F") : Color(hex: "C0392B"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Monthly average | top category — two columns split by a vertical rule.
    private var metricsDuo: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MONTHLY AVG")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.5)
                Text("$\(formatAmount(monthlyAverage))")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let top = topCategoryForPeriod {
                Rectangle()
                    .fill(Color(hex: "DEDAD2"))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text("TOP CATEGORY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .tracking(0.5)
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(top.color).frame(width: 26, height: 26)
                            Text(top.emoji).font(.system(size: 14))
                        }
                        Text(top.name)
                            .font(Font.dmSerifDisplay(24))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("$\(formatAmount(top.total)) · \(periodSubtitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - By month chart (bigger, shorter; tap focuses the month)

    private func byMonthSection(_ proxy: ScrollViewProxy) -> some View {
        // ≤6 months fill the card width; 12 (1Y) keep that same 6-month bar width
        // and scroll sideways. The slot is one bar's width in a 6-up layout.
        let scrollMode = periodMonthCount > 6
        let slot = byMonthWidth > 0 ? max(28, (byMonthWidth - 12 * 5) / 6) : 48

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Text("By month")
                    .font(Font.dmSerifDisplay(18))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                if scrollMode {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("swipe")
                        .font(.system(size: 11))
                    Text("·")
                }
                Text(appState.activeCurrency)
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color(hex: "8F9E94"))

            byMonthBars(scrollMode: scrollMode, slot: slot, proxy: proxy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { byMonthWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in byMonthWidth = newValue }
            }
        )
    }

    @ViewBuilder
    private func byMonthBars(scrollMode: Bool, slot: CGFloat, proxy: ScrollViewProxy) -> some View {
        if scrollMode {
            ScrollViewReader { sp in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(monthlyBars) { bar in
                            monthBar(bar, width: slot, proxy: proxy)
                                .id(bar.offset)
                        }
                    }
                    .frame(height: 118)
                    .padding(.trailing, 2)
                }
                // Left fade cues the earlier months you can swipe back to.
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [Color.white, Color.white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 22)
                        .allowsHitTesting(false)
                }
                // Open on the most recent month (offset 0 sits at the right).
                .onAppear {
                    DispatchQueue.main.async {
                        sp.scrollTo(0, anchor: .trailing)
                    }
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(monthlyBars) { bar in
                    monthBar(bar, width: nil, proxy: proxy)
                }
            }
            .frame(height: 118)
        }
    }

    /// One month's bar. `width` nil = fill the flexible column (≤6 months); a value
    /// pins the column to the shared 6-month slot (scrolling at 12).
    private func monthBar(_ bar: MonthBar, width: CGFloat?, proxy: ScrollViewProxy) -> some View {
        let isSel = selectedMonthOffset == bar.offset
        return Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.28)) {
                selectedMonthOffset = bar.offset
            }
            // Scroll after the breakdown below has expanded, so the By month row
            // lands at the top rather than short.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("byMonth", anchor: .top)
                }
            }
        } label: {
            VStack(spacing: 6) {
                if bar.total > 0 {
                    Text(formatAmountCompact(bar.total))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSel ? Color(hex: "2F402E") : Color(hex: "A9B0A6"))
                        .fontWeight(isSel ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(" ").font(.system(size: 11))
                }

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSel ? Color(hex: "2F402E") : Color(hex: "D8EBE0"))
                    .frame(
                        width: width ?? 48,
                        height: maxMonthlyTotal > 0
                            ? max(6, 72 * CGFloat(bar.total / maxMonthlyTotal))
                            : 6
                    )

                Text(bar.label)
                    .font(.system(size: 12))
                    .foregroundStyle(isSel ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
                    .fontWeight(isSel ? .semibold : .regular)
                    .lineLimit(1)
            }
            .frame(maxWidth: width == nil ? .infinity : width)
        }
        .buttonStyle(.plain)
    }
}
