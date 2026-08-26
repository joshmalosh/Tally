import SwiftUI

// MARK: - Period enum (shared by HeroSpendingCard + HomeView)

enum HeroPeriod: Int, CaseIterable {
    case month = 0
    case week  = 1
    case year  = 2
    case lastMonth = 3
    case thisFinancialYear = 4
    case allTime = 5

    /// Display order for period pickers — granularity progression, not raw case order.
    static let pickerOrder: [HeroPeriod] = [.week, .month, .lastMonth, .year, .thisFinancialYear, .allTime]

    var cardLabel: String {
        switch self {
        case .month: "SPENT THIS MONTH"
        case .week:  "SPENT THIS WEEK"
        case .year:  "SPENT THIS YEAR"
        case .lastMonth: "SPENT LAST MONTH"
        case .thisFinancialYear: "SPENT THIS FINANCIAL YEAR"
        case .allTime: "SPENT ALL TIME"
        }
    }

    /// Short label for the hero card's period picker, e.g. "This Year".
    var pickerLabel: String {
        switch self {
        case .month: "This Month"
        case .week:  "This Week"
        case .year:  "This Year"
        case .lastMonth: "Last Month"
        case .thisFinancialYear: "Financial Year"
        case .allTime: "All Time"
        }
    }

    /// - Parameter financialYearStart: required for `.thisFinancialYear` — pass
    ///   `AppState.currentFinancialYearStart`. Unused by every other case.
    func dateRange(financialYearStart: Date = .distantPast) -> (start: Date, end: Date) {
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
        case .lastMonth:
            let lastMonthAnchor = cal.date(byAdding: .month, value: -1, to: now) ?? now
            let interval = cal.dateInterval(of: .month, for: lastMonthAnchor)
            return (interval?.start ?? now, interval?.end ?? now)
        case .thisFinancialYear:
            return (financialYearStart, now)
        case .allTime:
            return (.distantPast, now)
        }
    }
}

// MARK: - Hero bottom wave

/// A gentle wave filling the lower part of the hero card. Sits under the content,
/// clipped to the card, giving the green area a soft curved bottom treatment.
private struct HeroBottomWave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let crest = rect.height * 0.60
        p.move(to: CGPoint(x: 0, y: crest))
        p.addQuadCurve(
            to: CGPoint(x: rect.width, y: crest - rect.height * 0.14),
            control: CGPoint(x: rect.width * 0.5, y: crest + rect.height * 0.16)
        )
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - SpendingSummaryCard

/// Compact hero card: a period picker + export action on top, then "Total spent" and
/// "Top category" side by side — both driven by the same selected period so the top
/// category always reflects whatever range the user has picked (Week/Month/Year).
struct SpendingSummaryCard: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedPeriod: HeroPeriod

    let allExpenses: [ExpenseModel]
    let allTags: [TagModel]
    let homeBarTagId: String?
    /// Called when the user taps the card body — opens PeriodDetailView for the selected period.
    let onPeriodTap: () -> Void
    /// Called when the user taps the Export pill.
    let onExportTap: () -> Void

    private var currency: String { appState.activeCurrency }

    // MARK: - Computed helpers

    /// Expenses within the selected period, narrowed by the home tag bar's active filter (if any).
    private var periodExpenses: [ExpenseModel] {
        let range = selectedPeriod.dateRange(financialYearStart: appState.currentFinancialYearStart)
        var result = allExpenses.filter { $0.date >= range.start && $0.date <= range.end }
        // Only the default currency — a foreign-currency expense (e.g. IDR) must
        // not be added into the total without a conversion rate.
        result = result.filter { $0.currency == currency }
        if let tagId = homeBarTagId {
            result = result.filter { $0.resolvedTagIds.contains(tagId) }
        }
        return result
    }

    private var totalCents: Int {
        periodExpenses.reduce(0) { $0 + $1.amountCents }
    }

    /// Tag with the highest spend within the selected period.
    private var topCategory: (tag: TagModel, cents: Int)? {
        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        var totals: [String: Int] = [:]
        for expense in periodExpenses {
            for tagId in expense.resolvedTagIds {
                totals[tagId, default: 0] += expense.amountCents
            }
        }
        guard let best = totals.max(by: { $0.value < $1.value }), let tag = tagMap[best.key] else { return nil }
        return (tag, best.value)
    }

    private var topCategoryPercent: Int {
        guard let top = topCategory, totalCents > 0 else { return 0 }
        return Int(round(Double(top.cents) / Double(totalCents) * 100))
    }

    private var showsCents: Bool { CurrencyFormatter.shared.usesDecimals(for: currency) }
    private var currencySymbol: String { CurrencyFormatter.shared.symbol(for: currency) }

    private var dollarPart: String {
        CurrencyFormatter.shared.groupedWhole(cents: totalCents, currencyCode: currency)
    }

    private var centsPart: String {
        String(format: "%02d", abs(totalCents % 100))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow

            HStack(alignment: .top, spacing: 0) {
                totalSpentColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let top = topCategory {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    topCategoryColumn(tag: top.tag, cents: top.cents)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 14)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            ZStack {
                Color(hex: "2F402E")
                // A soft curve washing across the lower third — a subtle lighter
                // green under the wave makes the header feel like part of the app,
                // not a flat card sitting on top of it.
                HeroBottomWave()
                    .fill(Color.white.opacity(0.04))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPeriodTap)
        .padding(.horizontal, 16)
    }

    // MARK: - Top row (period picker + export)

    private var topRow: some View {
        HStack {
            Menu {
                ForEach(HeroPeriod.pickerOrder, id: \.rawValue) { period in
                    Button(period.pickerLabel) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedPeriod = period }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                    Text(selectedPeriod.pickerLabel)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }

            Spacer()

            Button(action: onExportTap) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                    Text("Export")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Total spent column

    private var totalSpentColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total spent")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
            HStack(alignment: .top, spacing: 0) {
                Text(currencySymbol)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 5)
                    .padding(.trailing, 1)
                Text(dollarPart)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(-1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if showsCents {
                    Text(".\(centsPart)")
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 5)
                }
            }
        }
    }

    // MARK: - Top category column

    private func topCategoryColumn(tag: TagModel, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top category")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                    // A user tag stores an emoji in `icon` — that must never be
                    // passed to systemName (it logs "no symbol found"). Show the
                    // emoji as text; otherwise use the SF symbol.
                    if let emoji = tag.icon, emoji.isSingleEmoji {
                        Text(emoji).font(.system(size: 22))
                    } else {
                        Image(systemName: tag.symbolName ?? "tag.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(tag.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(CurrencyFormatter.shared.format(cents: cents, currencyCode: currency)) (\(topCategoryPercent)%)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}
