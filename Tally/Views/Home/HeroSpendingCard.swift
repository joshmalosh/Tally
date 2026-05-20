import SwiftUI

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
            .frame(height: 96)

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
            .padding(.bottom, 14)
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
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 5)
                    .padding(.trailing, 1)

                Text(dollarPart)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .tracking(-1.5)

                Text(".\(centsPart)")
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}
