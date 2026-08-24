import SwiftUI
import SwiftData

struct PeriodDetailView: View {
    let period: HeroPeriod
    let expenses: [ExpenseModel]
    let tags: [TagModel]
    var previousExpenses: [ExpenseModel] = []
    var titleOverride: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false
    @State private var expandedCategoryId: String? = nil
    // A tapped bar (week/day/month/year) filters the breakdown below to that
    // bucket, the same way tapping a month drills in on the reports page.
    @State private var selectedBarId: String? = nil
    // Present the expense detail as a stacked sheet from here, rather than via the
    // shared app-root binding — this view is itself often a sheet, and two sheets
    // fighting over the same binding is what left the detail unable to open.
    @State private var detailExpenseId: String? = nil

    // MARK: - Computed totals

    private var totalCents: Int {
        expenses.reduce(0) { $0 + $1.amountCents }
    }

    private var previousTotalCents: Int {
        previousExpenses.reduce(0) { $0 + $1.amountCents }
    }

    private var comparisonPercent: Int? {
        guard previousTotalCents > 0 else { return nil }
        return Int(round((Double(totalCents - previousTotalCents) / Double(previousTotalCents)) * 100))
    }

    // MARK: - Title

    private var titleText: String {
        if let override = titleOverride { return override }
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: now).uppercased()
        case .week:
            return "THIS WEEK"
        case .year:
            return "\(cal.component(.year, from: now))"
        case .lastMonth:
            let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: lastMonthDate).uppercased()
        case .thisFinancialYear:
            return "THIS FINANCIAL YEAR"
        case .allTime:
            return "ALL TIME"
        }
    }

    private var previousPeriodName: String {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .month:
            let prevDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
            return prevDate.formatted(.dateTime.month(.wide))
        case .week:
            return "last week"
        case .year:
            return "\(cal.component(.year, from: now) - 1)"
        case .lastMonth:
            return "the month before"
        case .thisFinancialYear:
            return "last financial year"
        case .allTime:
            return ""
        }
    }

    // MARK: - Formatting

    private var dollarPart: String {
        let whole = totalCents / 100
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: whole)) ?? "\(whole)"
    }

    private var centsPart: String {
        String(format: "%02d", abs(totalCents % 100))
    }

    private func formatCents(_ cents: Int) -> String {
        let whole = abs(cents) / 100
        let frac  = abs(cents) % 100
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let ws = f.string(from: NSNumber(value: whole)) ?? "\(whole)"
        return "$\(ws).\(String(format: "%02d", frac))"
    }

    /// A drill-down expense row that mirrors the home list: receipt thumbnail,
    /// merchant/notes, amount and tag, tappable to open the expense. Reuses the
    /// same `ExpenseCard` the home page uses so the two stay identical.
    @ViewBuilder
    private func expenseCardRow(_ expense: ExpenseModel) -> some View {
        let tag = expense.resolvedTagIds.first.flatMap { id in tags.first { $0.id == id } }
        let label: String? = tag.map { t in
            if let pid = t.parentId, let g = tags.first(where: { $0.id == pid }) {
                return "\(g.name) › \(t.name)"
            }
            return t.name
        }
        let hasReceipt = expense.attachmentKey != nil || expense.attachmentData != nil
        Button {
            detailExpenseId = expense.id
        } label: {
            ExpenseCard(
                receiptCacheKey: hasReceipt ? (expense.attachmentKey ?? expense.id) : nil,
                receiptAttachmentKey: expense.attachmentKey,
                receiptAttachmentData: expense.attachmentData,
                iconEmoji: tag?.displayEmoji,
                iconSystemName: tag?.icon ?? "tag.fill",
                iconBackground: tag?.tagColor.primaryColor.opacity(0.15) ?? Color(hex: "EDEBE6"),
                description: expense.expenseDescription ?? "Expense",
                merchant: expense.merchant,
                notes: expense.notes,
                amountCents: expense.amountCents,
                currency: expense.currency,
                primaryTagLabel: label,
                primaryTagColor: tag?.tagColor,
                additionalTagCount: max(0, expense.resolvedTagIds.count - 1)
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category breakdown

    private struct CategoryRow: Identifiable {
        let id: String
        let name: String
        let color: Color
        let symbol: String
        let emoji: String
        let totalCents: Int
        let percent: Double
    }

    /// The bucket id an expense belongs to, matching `displayBars`' ids so a
    /// tapped bar can filter to its own expenses across every period type.
    private func barKey(for e: ExpenseModel) -> String {
        let cal = Calendar.current
        switch period {
        case .month, .lastMonth:        return "w\(cal.component(.weekOfMonth, from: e.date))"
        case .week:                     return "d\(cal.component(.weekday, from: e.date))"
        case .year, .thisFinancialYear: return "m\(cal.component(.month, from: e.date))"
        case .allTime:                  return "y\(cal.component(.year, from: e.date))"
        }
    }

    /// Expenses shown in the breakdown: the whole period, or one bar's bucket.
    private var visibleExpenses: [ExpenseModel] {
        guard let id = selectedBarId else { return expenses }
        return expenses.filter { barKey(for: $0) == id }
    }

    private var visibleTotalCents: Int { visibleExpenses.reduce(0) { $0 + $1.amountCents } }

    private var categoryRows: [CategoryRow] {
        guard visibleTotalCents > 0 else { return [] }
        var buckets: [String: Int] = [:]
        for expense in visibleExpenses {
            let key = expense.resolvedTagIds.first ?? "__none__"
            buckets[key, default: 0] += expense.amountCents
        }
        let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        return buckets.map { key, cents in
            let percent = Double(cents) / Double(visibleTotalCents) * 100.0
            if key == "__none__" {
                return CategoryRow(id: key, name: "Uncategorised",
                                   color: Color(hex: "8F9E94"),
                                   symbol: "ellipsis.circle.fill",
                                   emoji: "🏷️",
                                   totalCents: cents, percent: percent)
            }
            let tag = tagMap[key]
            return CategoryRow(id: key,
                               name: tag?.name ?? "Unknown",
                               color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                               symbol: tag?.symbolName ?? (tag?.isGroup == true ? "folder.fill" : "tag.fill"),
                               emoji: tag?.displayEmoji ?? "🏷️",
                               totalCents: cents,
                               percent: percent)
        }.sorted { $0.totalCents > $1.totalCents }
    }

    private func expensesForCategory(_ id: String) -> [ExpenseModel] {
        visibleExpenses.filter { ($0.resolvedTagIds.first ?? "__none__") == id }
    }

    // MARK: - Weekly bars

    private struct WeekBar: Identifiable {
        let id: String
        let label: String
        let totalCents: Int
        let isCurrentWeek: Bool
    }

    /// This month's expenses bucketed by week-of-month, with the current week called out.
    private var weekBars: [WeekBar] {
        let cal = Calendar.current
        let now = Date()
        let currentWeekOfMonth = cal.component(.weekOfMonth, from: now)

        var buckets: [Int: Int] = [:]
        for e in expenses {
            let w = cal.component(.weekOfMonth, from: e.date)
            buckets[w, default: 0] += e.amountCents
        }

        // Build bars 1…max week seen (or up to current)
        let maxWeek = max(currentWeekOfMonth, buckets.keys.max() ?? 1)
        return (1...maxWeek).map { w in
            let isCurrent = (w == currentWeekOfMonth)
            let label = isCurrent ? "THIS\nWEEK" : "W\(w)"
            return WeekBar(id: "w\(w)", label: label,
                           totalCents: buckets[w] ?? 0, isCurrentWeek: isCurrent)
        }
    }

    /// A past month's expenses bucketed by week-of-month — no "current week" highlight
    /// since it isn't the live month.
    private var lastMonthWeekBars: [WeekBar] {
        let cal = Calendar.current
        var buckets: [Int: Int] = [:]
        for e in expenses {
            let w = cal.component(.weekOfMonth, from: e.date)
            buckets[w, default: 0] += e.amountCents
        }
        let maxWeek = buckets.keys.max() ?? 1
        return (1...maxWeek).map { w in
            WeekBar(id: "w\(w)", label: "W\(w)", totalCents: buckets[w] ?? 0, isCurrentWeek: false)
        }
    }

    private var displayBars: [WeekBar] {
        let cal = Calendar.current
        switch period {
        case .month:
            return weekBars
        case .lastMonth:
            return lastMonthWeekBars
        case .week:
            let symbols = cal.shortWeekdaySymbols
            var buckets: [Int: Int] = [:]
            for e in expenses {
                let wd = cal.component(.weekday, from: e.date)
                buckets[wd, default: 0] += e.amountCents
            }
            return buckets.sorted { $0.key < $1.key }.map { kv in
                WeekBar(id: "d\(kv.key)", label: symbols[kv.key - 1],
                        totalCents: kv.value, isCurrentWeek: false)
            }
        case .year, .thisFinancialYear:
            // Bucket by month, but order chronologically by each month's actual start
            // date — a financial year's 12 months never repeat a month number, but they
            // don't start in January, so sorting by raw month number (1-12) would be wrong.
            let symbols = cal.shortMonthSymbols
            var cents: [Int: Int] = [:]
            var sortDate: [Int: Date] = [:]
            for e in expenses {
                let m = cal.component(.month, from: e.date)
                cents[m, default: 0] += e.amountCents
                if sortDate[m] == nil {
                    sortDate[m] = cal.dateInterval(of: .month, for: e.date)?.start ?? e.date
                }
            }
            return cents.keys.sorted { (sortDate[$0] ?? .distantPast) < (sortDate[$1] ?? .distantPast) }.map { m in
                WeekBar(id: "m\(m)", label: symbols[m - 1], totalCents: cents[m] ?? 0, isCurrentWeek: false)
            }
        case .allTime:
            var buckets: [Int: Int] = [:]
            for e in expenses {
                let y = cal.component(.year, from: e.date)
                buckets[y, default: 0] += e.amountCents
            }
            return buckets.sorted { $0.key < $1.key }.map { kv in
                WeekBar(id: "y\(kv.key)", label: "\(kv.key)", totalCents: kv.value, isCurrentWeek: false)
            }
        }
    }

    private var chartTitle: String {
        switch period {
        case .month, .lastMonth:        return "By week"
        case .week:                     return "By day"
        case .year, .thisFinancialYear: return "By month"
        case .allTime:                  return "By year"
        }
    }

    private var maxBarCents: Int {
        displayBars.map(\.totalCents).max() ?? 1
    }

    // MARK: - Export month label

    private var exportLabel: String {
        if let override = titleOverride {
            // e.g. "MAY 2026" → "May 2026"
            return override.capitalized
        }
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: now)
        case .week:
            return "this week"
        case .year:
            return "\(cal.component(.year, from: now))"
        case .lastMonth:
            let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: lastMonthDate)
        case .thisFinancialYear:
            return "this financial year"
        case .allTime:
            return "all time"
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                if expenses.isEmpty {
                    emptyState
                } else {
                    summaryHeader
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Free tier: ad directly under the total.
                    InlineUpgradeAd()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    // Weekly/daily/monthly chart
                    if !displayBars.isEmpty {
                        weekChartCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                    }

                    // By category
                    if !categoryRows.isEmpty {
                        categoryCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                    }

                    // Export button inline — scrolls with content, never behind FAB
                    exportButton
                        .padding(.bottom, 100)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) {
            GlobalExportSheet(initialSelection: expenses)
        }
        .sheet(item: $detailExpenseId) { id in
            ExpenseDetailView(expenseId: id)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color(hex: "4A5E50"))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showingExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "4A5E50"))
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "4A5E50"))
                .tracking(1.0)

            HStack(alignment: .top, spacing: 0) {
                Text("$")
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 7)
                Text(dollarPart)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .tracking(-2)
                Text(".\(centsPart)")
                    .font(.system(size: 24, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 9)
            }

            HStack(spacing: 6) {
                Text("\(expenses.count) expense\(expenses.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))

                if let pct = comparisonPercent {
                    Text("·")
                        .foregroundStyle(Color(hex: "8F9E94"))
                    HStack(spacing: 3) {
                        Image(systemName: pct <= 0 ? "arrow.down" : "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(pct < 0 ? "" : "+")\(pct)% vs \(previousPeriodName)")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(pct <= 0 ? Color(hex: "2F6B3F") : Color(hex: "C0392B"))
                }
            }
        }
    }

    // MARK: - Week chart card

    private var weekChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chartTitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(displayBars) { bar in
                        let isHighlighted = selectedBarId == nil ? bar.isCurrentWeek : (bar.id == selectedBarId)
                        VStack(spacing: 5) {
                            if bar.totalCents > 0 {
                                Text(formatCents(bar.totalCents)
                                    .replacingOccurrences(of: ".00", with: ""))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(
                                        isHighlighted
                                        ? Color(hex: "2F402E")
                                        : Color(hex: "8F9E94")
                                    )
                            } else {
                                Text(" ").font(.system(size: 8))
                            }

                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isHighlighted
                                      ? Color(hex: "2F402E")
                                      : Color(hex: "D8EBE0"))
                                .frame(
                                    width: 38,
                                    height: maxBarCents > 0
                                        ? max(6, 90 * CGFloat(bar.totalCents) / CGFloat(maxBarCents))
                                        : 6
                                )

                            Text(bar.label)
                                .font(.system(size: bar.isCurrentWeek ? 8 : 10,
                                             weight: bar.isCurrentWeek ? .semibold : .regular))
                                .foregroundStyle(
                                    bar.isCurrentWeek
                                    ? Color(hex: "2F402E")
                                    : Color(hex: "8F9E94")
                                )
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                // Fixed height regardless of 1-line ("W1") vs 2-line ("THIS
                                // WEEK") labels — otherwise the taller label pushes its bar
                                // out of alignment with neighboring bars (HStack aligns the
                                // whole column to the bottom, not the bar itself).
                                .frame(height: 24, alignment: .top)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedBarId = (selectedBarId == bar.id) ? nil : bar.id
                            }
                        }
                    }
                }
                .frame(height: 130)
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
    }

    // MARK: - Category card

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BY CATEGORY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.5)

            VStack(spacing: 16) {
                ForEach(categoryRows) { row in
                    let isExpanded = expandedCategoryId == row.id
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            // Colored icon circle
                            ZStack {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 36, height: 36)
                                Text(row.emoji)
                                    .font(.system(size: 17))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                Text(String(format: "%.0f%% of total", row.percent))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                            }

                            Spacer()

                            Text(formatCents(row.totalCents))
                                .font(.system(size: 14, weight: .semibold).monospaced())
                                .foregroundStyle(Color(hex: "1C1C1E"))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedCategoryId = isExpanded ? nil : row.id
                            }
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "F0EDEA"))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(row.color.opacity(0.7))
                                    .frame(
                                        width: totalCents > 0
                                            ? geo.size.width * CGFloat(row.totalCents) / CGFloat(totalCents)
                                            : 0,
                                        height: 5
                                    )
                            }
                        }
                        .frame(height: 5)
                        .padding(.leading, 48)

                        if isExpanded {
                            let categoryExpenses = expensesForCategory(row.id)
                            VStack(spacing: 0) {
                                ForEach(Array(categoryExpenses.enumerated()), id: \.element.id) { index, expense in
                                    expenseCardRow(expense)
                                    if index < categoryExpenses.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.leading, 8)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
    }

    // MARK: - Export button

    private var exportButton: some View {
        Button {
            showingExport = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Export \(exportLabel) report")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: "2F402E"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🎉")
                .font(.system(size: 52))
            Text("Nothing spent here")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("No expenses logged for this period.\nEnjoy the quiet!")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8F9E94"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}
