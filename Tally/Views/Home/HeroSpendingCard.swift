import SwiftUI
import Charts

// MARK: - Period enum (shared by HeroSpendingCard + HomeView)

enum HeroPeriod: Int, CaseIterable {
    case month = 0
    case week  = 1
    case year  = 2

    var cardLabel: String {
        switch self {
        case .month: "SPENT THIS MONTH"
        case .week:  "SPENT THIS WEEK"
        case .year:  "SPENT THIS YEAR"
        }
    }

    func dateRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .month:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .year:
            let start = cal.dateInterval(of: .year, for: now)?.start ?? now
            return (start, now)
        }
    }
}

// MARK: - Hero Card

struct HeroSpendingCard: View {
    let allExpenses: [ExpenseModel]
    let homeBarTagId: String?
    let homeBarTagName: String?
    let onTap: (HeroPeriod) -> Void

    @State private var pageIndex: Int = 0

    private func totalCents(for period: HeroPeriod) -> Int {
        let range = period.dateRange()
        var result = allExpenses.filter { $0.date >= range.start && $0.date <= range.end }
        if let tagId = homeBarTagId {
            result = result.filter { $0.resolvedTagIds.contains(tagId) }
        }
        return result.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(HeroPeriod.allCases, id: \.rawValue) { period in
                    HeroPeriodPage(
                        period: period,
                        totalCents: totalCents(for: period),
                        tagName: homeBarTagId != nil ? homeBarTagName : nil
                    )
                    .tag(period.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 82)

            // Page indicator
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    if i == pageIndex {
                        Capsule()
                            .fill(Color(hex: "346049"))
                            .frame(width: 16, height: 5)
                    } else {
                        Circle()
                            .fill(Color(hex: "DEDAD2"))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: pageIndex)
            .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(HeroPeriod(rawValue: pageIndex) ?? .month)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
    }
}

// MARK: - Period Page

private struct HeroPeriodPage: View {
    let period: HeroPeriod
    let totalCents: Int
    let tagName: String?

    private var periodLabel: String {
        guard let tag = tagName else { return period.cardLabel }
        return "\(period.cardLabel) · \(tag.uppercased())"
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(periodLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.3)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }

            HStack(alignment: .top, spacing: 0) {
                Text("$")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 4)
                    .padding(.trailing, 1)

                Text(dollarPart)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .tracking(-1.5)

                Text(".\(centsPart)")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

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
    private var monthlyTotals: [SummaryMonthTotal] {
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
            SummaryMonthTotal(month: month, cents: buckets[month] ?? 0)
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
            if monthlyTotals.allSatisfy({ $0.cents == 0 }) {
                Color(hex: "DEDAD2")
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

// MARK: - Spending period page

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
        return formatter.string(from: NSNumber(value: whole)) ?? "\(whole)"
    }

    private var centsPart: String {
        String(format: "%02d", abs(totalCents % 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }

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

            Text(periodLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Chart data point

private struct SummaryMonthTotal: Identifiable {
    let month: Int
    let cents: Int
    var id: Int { month }
}
