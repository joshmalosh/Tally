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

    let allExpenses: [ExpenseModel]
    let allTags: [TagModel]
    let homeBarTagId: String?
    /// Called when the user taps the card body — opens PeriodDetailView for the selected period.
    let onPeriodTap: () -> Void
    /// Header controls (design pass: these live in the green header, not a strip above it).
    var isPro: Bool = true
    var isOnline: Bool = true
    var isOffline: Bool = false
    var onProTap: () -> Void = {}
    var onSettingsTap: () -> Void = {}

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

    /// Ranked category slices for the breakdown bar — same period + currency the
    /// Total and Top category above it use.
    private var breakdownSegments: [SpendBreakdownSegment] {
        spendBreakdownSegments(periodExpenses, tags: allTags, currency: currency)
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
            // Heading: the eyebrow shares the top row with the period · Go Pro ·
            // settings trio; the amount gets its OWN full-width row beneath so it
            // can never be squeezed/truncated by the controls (a large total on
            // free, with the Go Pro crown present, overflowed when it shared a row).
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 10) {
                    eyebrowView
                    Spacer(minLength: 8)
                    trioControls
                }
                amountView
            }

            // Breakdown: categories normally, merchants (in shades of the tag
            // colour) when a pinned tag is filtering the view.
            if !displaySegments.isEmpty {
                SpendBreakdownBar(segments: displaySegments)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "365F49"), Color(hex: "1E3A2A")],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPeriodTap)
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

    /// The hero amount (currency symbol + grouped whole + cents).
    private var amountView: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(currencySymbol)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 5).padding(.trailing, 1)
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

    // MARK: - Top-right trio (period · Go Pro · settings)

    private var periodMenu: some View {
        Menu {
            ForEach(HeroPeriod.pickerOrder, id: \.rawValue) { period in
                Button(period.pickerLabel) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedPeriod = period }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 12, weight: .medium))
                Text(selectedPeriod.pickerLabel).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white.opacity(0.15)).clipShape(Capsule())
        }
        .fixedSize()
    }

    /// Period · Go Pro (green crown on white) · settings. Export moved out — it's
    /// reached by tapping into a period.
    @ViewBuilder
    private var trioControls: some View {
        HStack(spacing: 8) {
            periodMenu
            if isOffline {
                Image(systemName: "wifi.slash").font(.system(size: 13)).foregroundStyle(Color(hex: "F3B0A0"))
            }
            if !isOnline {
                Image(systemName: "icloud.slash").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            if !isPro {
                Button(action: onProTap) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E"))
                        .frame(width: 32, height: 32)
                        .background(Color.white).clipShape(Circle())
                        .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.16)).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Category slices normally; merchant slices (shades of the tag colour) when filtered.
    private var displaySegments: [SpendBreakdownSegment] {
        if let tag = filterTag {
            return merchantBreakdownSegments(periodExpenses, tint: tag.tagColor.primaryColor, currency: currency)
        }
        return breakdownSegments
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

