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
        switch period {
        case .month:
            let cal = Calendar.current
            let date = cal.date(byAdding: .month, value: 0, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date).uppercased()
        case .week:
            return "THIS WEEK"
        case .year:
            return "\(Calendar.current.component(.year, from: Date()))"
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

    // MARK: - Category breakdown

    private struct CategoryRow: Identifiable {
        let id: String
        let name: String
        let color: Color
        let symbol: String
        let totalCents: Int
        let percent: Double
    }

    private var categoryRows: [CategoryRow] {
        guard totalCents > 0 else { return [] }
        var buckets: [String: Int] = [:]
        for expense in expenses {
            let key = expense.resolvedTagIds.first ?? "__none__"
            buckets[key, default: 0] += expense.amountCents
        }
        let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        return buckets.map { key, cents in
            let percent = Double(cents) / Double(totalCents) * 100.0
            if key == "__none__" {
                return CategoryRow(id: key, name: "Uncategorised",
                                   color: Color(hex: "8F9E94"),
                                   symbol: "ellipsis.circle.fill",
                                   totalCents: cents, percent: percent)
            }
            let tag = tagMap[key]
            return CategoryRow(id: key,
                               name: tag?.name ?? "Unknown",
                               color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                               symbol: tag?.symbolName ?? "tag.fill",
                               totalCents: cents,
                               percent: percent)
        }.sorted { $0.totalCents > $1.totalCents }
    }

    private func expensesForCategory(_ id: String) -> [ExpenseModel] {
        expenses.filter { ($0.resolvedTagIds.first ?? "__none__") == id }
    }

    private func expenseTitle(_ expense: ExpenseModel) -> String {
        if let merchant = expense.merchant, !merchant.isEmpty { return merchant }
        if let description = expense.expenseDescription, !description.isEmpty { return description }
        if let notes = expense.notes, !notes.isEmpty { return notes }
        return "Expense"
    }

    private static let expenseRowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    // MARK: - Weekly bars

    private struct WeekBar: Identifiable {
        let id: String
        let label: String
        let totalCents: Int
        let isCurrentWeek: Bool
    }

    private var weekBars: [WeekBar] {
        guard period == .month else { return [] }
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

    private var weekBarsForOtherPeriods: [WeekBar] {
        // For non-month periods use the old time-bucket approach mapped to WeekBar
        let cal = Calendar.current
        switch period {
        case .month: return weekBars  // handled above
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
        case .year:
            let symbols = cal.shortMonthSymbols
            var buckets: [Int: Int] = [:]
            for e in expenses {
                let m = cal.component(.month, from: e.date)
                buckets[m, default: 0] += e.amountCents
            }
            return buckets.sorted { $0.key < $1.key }.map { kv in
                WeekBar(id: "m\(kv.key)", label: symbols[kv.key - 1],
                        totalCents: kv.value, isCurrentWeek: false)
            }
        }
    }

    private var displayBars: [WeekBar] {
        period == .month ? weekBars : weekBarsForOtherPeriods
    }

    private var chartTitle: String {
        switch period {
        case .month: return "By week"
        case .week:  return "By day"
        case .year:  return "By month"
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
        switch period {
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: Date())
        case .week:  return "this week"
        case .year:  return "\(Calendar.current.component(.year, from: Date()))"
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
                        VStack(spacing: 5) {
                            if bar.totalCents > 0 {
                                Text(formatCents(bar.totalCents)
                                    .replacingOccurrences(of: ".00", with: ""))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(
                                        bar.isCurrentWeek
                                        ? Color(hex: "2F402E")
                                        : Color(hex: "8F9E94")
                                    )
                            } else {
                                Text(" ").font(.system(size: 8))
                            }

                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(bar.isCurrentWeek
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
                                Image(systemName: row.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
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
                                    HStack(spacing: 10) {
                                        Text(Self.expenseRowDateFormatter.string(from: expense.date))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color(hex: "8F9E94"))
                                            .frame(width: 42, alignment: .leading)
                                        Text(expenseTitle(expense))
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(hex: "1C1C1E"))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(formatCents(expense.amountCents))
                                            .font(.system(size: 13, weight: .medium).monospaced())
                                            .foregroundStyle(Color(hex: "1C1C1E"))
                                    }
                                    .padding(.vertical, 8)

                                    if index < categoryExpenses.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.leading, 48)
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
