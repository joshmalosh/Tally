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
    @State private var showingBreakdown = false

    enum ReportPeriod: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths   = "6M"
        case oneYear     = "1Y"
        case allTime     = "All"
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

    /// Expenses within the selected display period.
    private var filteredExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .threeMonths:
            return currencyExpenses.filter { $0.date >= calendar.date(byAdding: .month, value: -3,  to: now)! }
        case .sixMonths:
            return currencyExpenses.filter { $0.date >= calendar.date(byAdding: .month, value: -6,  to: now)! }
        case .oneYear:
            return currencyExpenses.filter { $0.date >= calendar.date(byAdding: .year,  value: -1,  to: now)! }
        case .allTime:
            return currencyExpenses
        }
    }

    /// Same window shifted one full period back — used for % comparison.
    private var previousPeriodExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .threeMonths:
            let end   = calendar.date(byAdding: .month, value: -3,  to: now)!
            let start = calendar.date(byAdding: .month, value: -6,  to: now)!
            return currencyExpenses.filter { $0.date >= start && $0.date < end }
        case .sixMonths:
            let end   = calendar.date(byAdding: .month, value: -6,  to: now)!
            let start = calendar.date(byAdding: .month, value: -12, to: now)!
            return currencyExpenses.filter { $0.date >= start && $0.date < end }
        case .oneYear:
            let end   = calendar.date(byAdding: .year,  value: -1,  to: now)!
            let start = calendar.date(byAdding: .year,  value: -2,  to: now)!
            return currencyExpenses.filter { $0.date >= start && $0.date < end }
        case .allTime:
            return []
        }
    }

    // MARK: - Totals

    private var currentTotal: Double {
        Double(filteredExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
    }

    private var previousTotal: Double {
        Double(previousPeriodExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
    }

    private var comparisonText: String? {
        guard previousTotal > 0 else { return nil }
        let change = (currentTotal - previousTotal) / previousTotal * 100.0
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs previous \(selectedPeriod == .allTime ? "period" : periodLabel)"
    }

    private var comparisonIsDown: Bool {
        previousTotal > 0 && currentTotal < previousTotal
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .threeMonths: return "3 months"
        case .sixMonths:   return "6 months"
        case .oneYear:     return "year"
        case .allTime:     return "period"
        }
    }

    private var periodHeaderLabel: String {
        switch selectedPeriod {
        case .threeMonths: return "TOTAL · LAST 3 MONTHS"
        case .sixMonths:   return "TOTAL · LAST 6 MONTHS"
        case .oneYear:     return "TOTAL · LAST 12 MONTHS"
        case .allTime:     return "TOTAL · ALL TIME"
        }
    }

    // MARK: - Monthly average

    private var monthlyAverage: Double {
        let total = currentTotal
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths:   months = 6
        case .oneYear:     months = 12
        case .allTime:
            let oldest = currencyExpenses.last?.date ?? Date()
            months = max(1, Double(Calendar.current.dateComponents([.month], from: oldest, to: Date()).month ?? 1))
        }
        return total / months
    }

    private var previousYearMonthlyAverage: Double? {
        guard selectedPeriod != .allTime else { return nil }
        guard !previousPeriodExpenses.isEmpty else { return nil }
        let total = previousTotal
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths:   months = 6
        case .oneYear:     months = 12
        case .allTime:     months = 1
        }
        return total / months
    }

    // MARK: - Top category

    private struct TagSpend: Identifiable {
        let id: String
        let name: String
        let color: Color
        let total: Double
        let expenses: [ExpenseModel]
    }

    private var topCategoryForPeriod: TagSpend? {
        // Top category across the full filtered period (not just selected month)
        var result: [String: [ExpenseModel]] = [:]
        for expense in filteredExpenses {
            let tagId = expense.resolvedTagIds.first ?? "untagged"
            result[tagId, default: []].append(expense)
        }
        let breakdown = result.map { id, expList -> TagSpend in
            let total = expList.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            if id == "untagged" {
                return TagSpend(id: id, name: "Untagged", color: Color(hex: "8F9E94"),
                                total: total, expenses: expList)
            }
            let tag = tags.first { $0.id == id }
            return TagSpend(id: id,
                            name: tag?.name ?? "Unknown",
                            color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                            total: total, expenses: expList)
        }.sorted { $0.total > $1.total }
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

    // MARK: - Selected month (for breakdown)

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

    private var selectedMonthTotal: Double {
        selectedMonthExpenses.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
    }

    private var selectedMonthLabelFull: String {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: now)!
        return date.formatted(.dateTime.month(.wide).year())
    }

    private var selectedMonthLabelShort: String {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: now)!
        return date.formatted(.dateTime.month(.abbreviated))
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    totalCard
                    metricsRow
                    barChartCard
                    breakdownCTA
                    // Full-width (no side padding) so the adaptive banner, which is
                    // sized to the full screen width, isn't forced into a narrower
                    // slot and made to overflow.
                    InlineUpgradeAd()
                    Spacer(minLength: 100)
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
            .navigationDestination(isPresented: $showingBreakdown) {
                PeriodDetailView(
                    period: .month,
                    expenses: selectedMonthExpenses,
                    tags: Array(tags),
                    previousExpenses: previousMonthExpenses,
                    titleOverride: selectedMonthLabelFull.uppercased()
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "4A5E50"))
                .tracking(1.2)
            HStack {
                Text("Your reports")
                    .font(Font.dmSerifDisplay(30))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                // Period filter pills
                HStack(spacing: 2) {
                    ForEach(ReportPeriod.allCases, id: \.self) { period in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPeriod = period
                                selectedMonthOffset = 0
                            }
                        } label: {
                            Text(period.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedPeriod == period ? Color(hex: "2F402E") : Color.clear)
                                .foregroundStyle(selectedPeriod == period ? Color.white : Color(hex: "8F9E94"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Total card

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(periodHeaderLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.3)

            Text("$\(formatAmount(currentTotal))")
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .tracking(-1)

            if let comparison = comparisonText {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: comparisonIsDown ? "arrow.down" : "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                        Text(comparisonIsDown
                             ? comparison.replacingOccurrences(of: "-", with: "↓ ")
                                         .replacingOccurrences(of: "↓ -", with: "↓ ")
                             : comparison)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(comparisonIsDown ? Color(hex: "2F6B3F") : Color(hex: "C0392B"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((comparisonIsDown ? Color(hex: "2F6B3F") : Color(hex: "C0392B")).opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    // MARK: - Metrics row (monthly avg + top category)

    private var metricsRow: some View {
        HStack(spacing: 10) {
            // Monthly average
            VStack(alignment: .leading, spacing: 4) {
                Text("MONTHLY AVG")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.5)
                Text("$\(formatAmount(monthlyAverage))")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                if let prev = previousYearMonthlyAverage {
                    Text("$\(formatAmount(prev)) prev period")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))

            // Top category
            if let top = topCategoryForPeriod {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP CATEGORY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .tracking(0.5)
                    Text(top.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .lineLimit(1)
                    Text("$\(formatAmount(top.total)) in \(selectedMonthLabelShort)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: "F2F8F4"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
            }
        }
        // Equal-height cards: both cells stretch to the taller one's height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
    }

    // MARK: - Bar chart

    private var barChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("By month")
                    .font(Font.dmSerifDisplay(18))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Text(appState.activeCurrency)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(monthlyBars) { bar in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMonthOffset = bar.offset
                            }
                        } label: {
                            VStack(spacing: 4) {
                                if bar.total > 0 {
                                    Text(formatAmountCompact(bar.total))
                                        .font(.system(size: 8))
                                        .foregroundStyle(
                                            selectedMonthOffset == bar.offset
                                            ? Color(hex: "2F402E") : Color(hex: "8F9E94")
                                        )
                                } else {
                                    Text("")
                                        .font(.system(size: 8))
                                }

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedMonthOffset == bar.offset
                                          ? Color(hex: "2F402E")
                                          : Color(hex: "D8EBE0"))
                                    .frame(
                                        width: 32,
                                        height: maxMonthlyTotal > 0
                                            ? max(4, 90 * CGFloat(bar.total / maxMonthlyTotal))
                                            : 4
                                    )

                                Text(bar.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        selectedMonthOffset == bar.offset
                                        ? Color(hex: "2F402E") : Color(hex: "8F9E94")
                                    )
                                    .fontWeight(selectedMonthOffset == bar.offset ? .semibold : .regular)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 130)
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Breakdown CTA

    private var breakdownCTA: some View {
        Button {
            showingBreakdown = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THIS MONTH")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(0.8)
                    Text("\(selectedMonthLabelFull) breakdown")
                        .font(Font.dmSerifDisplay(20))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(hex: "2F402E"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
