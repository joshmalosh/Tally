import SwiftUI
import UIKit

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

// MARK: - SpendingSummaryCard

/// Compact hero card: a period picker + export action on top, then "Total spent" and
/// "Top category" side by side — both driven by the same selected period so the top
/// category always reflects whatever range the user has picked (Week/Month/Year).
struct SpendingSummaryCard: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedPeriod: HeroPeriod
    /// The pinned-tag filter — bound so the pins inside the card drive it directly.
    @Binding var homeBarTagId: String?

    let allExpenses: [ExpenseModel]
    let allTags: [TagModel]
    /// Tapping the total / "TAP FOR BREAKDOWN" opens the period breakdown.
    let onBreakdownTap: () -> Void

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
        VStack(alignment: .leading, spacing: 12) {
            // Total block — tappable to open the full breakdown.
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    eyebrowView
                    Spacer(minLength: 8)
                    periodMenu
                }
                amountView
                breakdownCue
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .contentShape(Rectangle())
            .onTapGesture { onBreakdownTap() }

            // The pinned tags live inside the green, as the at-a-glance breakdown
            // of the total above. They scroll to the card's edges (own h-padding).
            HomeTagBar(selectedTagId: $homeBarTagId, period: selectedPeriod, onDark: true)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "365F49"), Color(hex: "1E3A2A")],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Heading

    /// The tag currently filtering the view, if any (from the pinned bar).
    private var filterTag: TagModel? {
        guard let id = homeBarTagId else { return nil }
        return allTags.first { $0.id == id }
    }

    /// Scope eyebrow — "TOTAL SPENT", or the tag name in its (lightened) colour when filtered.
    private var eyebrowView: some View {
        let text: String
        let color: Color
        if let tag = filterTag {
            text = tag.name.uppercased()
            color = tag.tagColor.primaryColor.lightened(0.4)
        } else {
            text = "TOTAL SPENT"
            color = .white.opacity(0.6)
        }
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// The hero amount in the serif, big; the symbol and cents ride smaller.
    private var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(currencySymbol)
                .font(.dmSerifDisplay(20))
                .foregroundStyle(.white.opacity(0.72))
            Text(dollarPart)
                .font(.dmSerifDisplay(48))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if showsCents {
                Text(".\(centsPart)")
                    .font(.dmSerifDisplay(20))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    /// Plain tappable period — "This Month ▾" as text, no pill (minimise dropdowns).
    private var periodMenu: some View {
        Menu {
            ForEach(HeroPeriod.pickerOrder, id: \.rawValue) { period in
                Button(period.pickerLabel) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedPeriod = period }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedPeriod.pickerLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .fixedSize()
            .foregroundStyle(.white.opacity(0.9))
        }
        .fixedSize()
    }

    /// The "tap to see the breakdown" cue — monospace, understated.
    private var breakdownCue: some View {
        HStack(spacing: 5) {
            Text("TAP FOR BREAKDOWN")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.top, 2)
    }

}

// MARK: - Spend breakdown bar (home design pass)

/// One category slice of a period's spend.
struct SpendBreakdownSegment: Identifiable {
    let id: String
    let color: Color
    let name: String
    let cents: Int
}

/// Ranked merchant slices for a filtered tag, coloured in lightening shades of the
/// tag's own colour. Used when a pinned tag is selected (the breakdown re-points to
/// the shops inside that tag). Expenses with no merchant are skipped.
func merchantBreakdownSegments(_ expenses: [ExpenseModel], tint: Color, currency: String, maxCount: Int = 5) -> [SpendBreakdownSegment] {
    var totals: [String: Int] = [:]
    for e in expenses where e.currency == currency {
        let name = (e.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        totals[name, default: 0] += e.amountCents
    }
    return totals.sorted { $0.value > $1.value }.prefix(maxCount).enumerated().map { i, kv in
        SpendBreakdownSegment(
            id: kv.key,
            color: tint.lightened(min(0.62, Double(i) * 0.2)),
            name: kv.key,
            cents: kv.value
        )
    }
}

extension Color {
    /// Blend toward white by `amount` (0…1), so shades stay legible on the dark hero.
    func lightened(_ amount: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let f = CGFloat(max(0, min(1, amount)))
        return Color(
            red: Double(r + (1 - r) * f),
            green: Double(g + (1 - g) * f),
            blue: Double(b + (1 - b) * f),
            opacity: Double(a)
        )
    }
}

/// Ranked category slices (desc by spend) for a set of expenses, filtered to the
/// given currency so a foreign-currency expense can't skew the shares. Shared by
/// the hero and the collapsed header so the two always agree.
func spendBreakdownSegments(_ expenses: [ExpenseModel], tags: [TagModel], currency: String) -> [SpendBreakdownSegment] {
    let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    var totals: [String: Int] = [:]
    for e in expenses where e.currency == currency {
        for id in e.resolvedTagIds where tagMap[id] != nil {
            totals[id, default: 0] += e.amountCents
        }
    }
    return totals.compactMap { key, cents -> SpendBreakdownSegment? in
        guard let t = tagMap[key] else { return nil }
        return SpendBreakdownSegment(id: key, color: t.tagColor.primaryColor, name: t.name, cents: cents)
    }
    .sorted { $0.cents > $1.cents }
}

/// The segmented spend bar + tag-name legend, on the dark hero / collapsed bar.
struct SpendBreakdownBar: View {
    let segments: [SpendBreakdownSegment]
    /// Max slices drawn on the bar.
    var maxSegments: Int = 6
    /// Names shown beneath it.
    var legendCount: Int = 4
    var barHeight: CGFloat = 8

    private var total: Int { max(1, segments.prefix(maxSegments).reduce(0) { $0 + $1.cents }) }

    var body: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let shown = Array(segments.prefix(maxSegments))
                    let gaps = CGFloat(max(0, shown.count - 1)) * 2
                    let avail = max(0, geo.size.width - gaps)
                    HStack(spacing: 2) {
                        ForEach(shown) { s in
                            Rectangle()
                                .fill(s.color)
                                .frame(width: max(4, avail * CGFloat(s.cents) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: barHeight)
                .clipShape(Capsule())

                FlowLayout(spacing: 11) {
                    ForEach(segments.prefix(legendCount)) { s in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 7, height: 7)
                            Text(s.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

