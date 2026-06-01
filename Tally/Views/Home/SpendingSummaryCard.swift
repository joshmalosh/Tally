import SwiftUI
import Charts

// MARK: - SpendingSummaryCard

struct SpendingSummaryCard: View {
    @Environment(AppState.self) private var appState

    let allExpenses: [ExpenseModel]
    let allTags: [TagModel]
    let homeBarTagId: String?
    let homeBarTagName: String?
    let onTap: (HeroPeriod) -> Void

    @State private var pageIndex: Int = 0

    private var currency: String { appState.defaultCurrency }

    // MARK: - Computed helpers

    private func totalCents(for period: HeroPeriod) -> Int {
        let range = period.dateRange()
        var result = allExpenses.filter { $0.date >= range.start && $0.date <= range.end }
        if let tagId = homeBarTagId {
            result = result.filter { $0.resolvedTagIds.contains(tagId) }
        }
        return result.reduce(0) { $0 + $1.amountCents }
    }

    /// Monthly spend totals for the current calendar year (for the chart).
    private var monthlyTotals: [MonthTotal] {
        let cal = Calendar.current
        let now = Date()
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now
        let yearExpenses = allExpenses.filter { $0.date >= yearStart && $0.date <= now }

        var buckets: [Int: Int] = [:]
        for expense in yearExpenses {
            let month = cal.component(.month, from: expense.date)
            buckets[month, default: 0] += expense.amountCents
        }

        let currentMonth = cal.component(.month, from: now)
        return (1...currentMonth).map { month in
            MonthTotal(month: month, cents: buckets[month] ?? 0)
        }
    }

    /// Tag with the highest spend this year.
    private var topTag: (tag: TagModel, cents: Int)? {
        let cal = Calendar.current
        let now = Date()
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now
        let yearExpenses = allExpenses.filter { $0.date >= yearStart && $0.date <= now }

        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        var tagTotals: [String: Int] = [:]
        for expense in yearExpenses {
            for tagId in expense.resolvedTagIds {
                tagTotals[tagId, default: 0] += expense.amountCents
            }
        }

        guard let best = tagTotals.max(by: { $0.value < $1.value }),
              let tag = tagMap[best.key]
        else { return nil }
        return (tag, best.value)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Rectangle()
                .fill(Color(hex: "E8E4DD"))
                .frame(width: 0.5)
                .padding(.vertical, 16)
            rightPanel
                .frame(width: 155)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        TabView(selection: $pageIndex) {
            ForEach(HeroPeriod.allCases, id: \.rawValue) { period in
                SpendingPeriodPage(
                    period: period,
                    totalCents: totalCents(for: period),
                    onTap: { onTap(period) }
                )
                .tag(period.rawValue)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 110)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending trend")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))
                .padding(.leading, 12)

            spendingChart
                .padding(.horizontal, 8)

            if let top = topTag {
                topCategoryRow(tag: top.tag, cents: top.cents)
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Chart

    @ViewBuilder
    private var spendingChart: some View {
        let data = monthlyTotals
        let maxCents = data.map(\.cents).max() ?? 1

        Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Month", point.month),
                    y: .value("Amount", point.cents)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "346049").opacity(0.1), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Month", point.month),
                    y: .value("Amount", point.cents)
                )
                .foregroundStyle(Color(hex: "346049"))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // Dot on the most recent data point
            if let last = data.last {
                PointMark(
                    x: .value("Month", last.month),
                    y: .value("Amount", last.cents)
                )
                .foregroundStyle(Color(hex: "346049"))
                .symbolSize(30)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(maxCents > 0 ? maxCents : 1))
        .frame(height: 50)
        .overlay {
            // Empty state — shown when all months are zero
            if monthlyTotals.allSatisfy({ $0.cents == 0 }) {
                Rectangle()
                    .stroke(
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .foregroundStyle(Color(hex: "DEDAD2"))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Top category row

    private func topCategoryRow(tag: TagModel, cents: Int) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: "FAEEDA"))
                    .frame(width: 22, height: 22)
                Image(systemName: tag.symbolName ?? "tag.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "854F0B"))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Top category")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color(hex: "8F9E94"))
                Text(tag.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(CurrencyFormatter.shared.format(cents: cents, currencyCode: currency))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "346049"))
        }
    }
}

// MARK: - Period page (left panel slide)

private struct SpendingPeriodPage: View {
    let period: HeroPeriod
    let totalCents: Int
    let onTap: () -> Void

    private var periodLabel: String {
        switch period {
        case .month: return "spent this month"
        case .week:  return "spent this week"
        case .year:  return "spent this year"
        }
    }

    private var dollarPart: String {
        let whole = totalCents / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: whole)) ?? "\(whole)"
    }

    private var centsPart: String {
        String(format: "%02d", abs(totalCents % 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Chevron hint — static, always top-right
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }

            // Amount
            HStack(alignment: .top, spacing: 0) {
                Text("$")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 4)
                    .padding(.trailing, 1)

                Text(dollarPart)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .tracking(-1.5)

                Text(".\(centsPart)")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 4)
            }

            // Period label
            Text(periodLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))

            // Delta badge — TODO: wire up real comparison logic
            // Text("↑ 8% vs last year")
            //     .font(.system(size: 11, weight: .semibold))
            //     .foregroundStyle(Color(hex: "C0392B"))
            //     .padding(.horizontal, 8).padding(.vertical, 3)
            //     .background(Color(hex: "FDEAEA"))
            //     .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - MonthTotal (chart data point)

private struct MonthTotal: Identifiable {
    let month: Int
    let cents: Int
    var id: Int { month }
}
