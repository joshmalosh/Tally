import SwiftUI

struct PeriodDetailView: View {
    let period: HeroPeriod
    let expenses: [ExpenseModel]
    let tags: [TagModel]

    @Environment(\.dismiss) private var dismiss

    // MARK: - Totals

    private var totalCents: Int {
        expenses.reduce(0) { $0 + $1.amountCents }
    }

    private var dayCount: Int {
        let cal = Calendar.current
        let range = period.dateRange()
        return max(1, cal.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
    }

    private var dailyAverage: Double {
        guard totalCents > 0 else { return 0 }
        return Double(totalCents) / 100.0 / Double(dayCount)
    }

    // MARK: - Category breakdown

    private struct CategorySpend: Identifiable {
        let id: String
        let name: String
        let color: Color
        let totalCents: Int
    }

    private var tagById: [String: TagModel] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private var categoryBreakdown: [CategorySpend] {
        var buckets: [String: Int] = [:]
        for expense in expenses {
            let key = expense.resolvedTagIds.first ?? "__none__"
            buckets[key, default: 0] += expense.amountCents
        }
        let map = tagById
        return buckets.map { key, total in
            if key == "__none__" {
                return CategorySpend(id: key, name: "Uncategorised",
                                     color: Color(hex: "8F9E94"), totalCents: total)
            }
            let tag = map[key]
            return CategorySpend(id: key,
                                 name: tag?.name ?? "Unknown",
                                 color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                                 totalCents: total)
        }.sorted { $0.totalCents > $1.totalCents }
    }

    // MARK: - Time buckets

    private struct TimeBucket: Identifiable {
        let id: String
        let label: String
        let totalCents: Int
    }

    private var timeBuckets: [TimeBucket] {
        let cal = Calendar.current
        switch period {
        case .month:
            var buckets: [Int: Int] = [:]
            for e in expenses {
                let w = cal.component(.weekOfMonth, from: e.date)
                buckets[w, default: 0] += e.amountCents
            }
            return buckets.sorted { $0.key < $1.key }.enumerated().map { i, kv in
                TimeBucket(id: "w\(kv.key)", label: "Wk \(i + 1)", totalCents: kv.value)
            }

        case .week:
            let symbols = cal.shortWeekdaySymbols
            var buckets: [Int: (label: String, total: Int)] = [:]
            for e in expenses {
                let wd = cal.component(.weekday, from: e.date)
                let label = symbols[wd - 1]
                var entry = buckets[wd] ?? (label: label, total: 0)
                entry.total += e.amountCents
                buckets[wd] = entry
            }
            return buckets.sorted { $0.key < $1.key }.map { kv in
                TimeBucket(id: "d\(kv.key)", label: kv.value.label, totalCents: kv.value.total)
            }

        case .year:
            let symbols = cal.shortMonthSymbols
            var buckets: [Int: (label: String, total: Int)] = [:]
            for e in expenses {
                let m = cal.component(.month, from: e.date)
                let label = symbols[m - 1]
                var entry = buckets[m] ?? (label: label, total: 0)
                entry.total += e.amountCents
                buckets[m] = entry
            }
            return buckets.sorted { $0.key < $1.key }.map { kv in
                TimeBucket(id: "m\(kv.key)", label: kv.value.label, totalCents: kv.value.total)
            }
        }
    }

    private var timeBucketTitle: String {
        switch period {
        case .month: "By week"
        case .week:  "By day"
        case .year:  "By month"
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
        let frac = abs(cents) % 100
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let ws = f.string(from: NSNumber(value: whole)) ?? "\(whole)"
        return "$\(ws).\(String(format: "%02d", frac))"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Running total
                    VStack(alignment: .leading, spacing: 4) {
                        Text(period.cardLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .tracking(0.3)

                        HStack(alignment: .top, spacing: 0) {
                            Text("$")
                                .font(.system(size: 22, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                                .padding(.top, 8)
                                .padding(.trailing, 1)
                            Text(dollarPart)
                                .font(.system(size: 48, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                                .tracking(-1.5)
                            Text(".\(centsPart)")
                                .font(.system(size: 22, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                                .padding(.top, 8)
                        }

                        if dailyAverage > 0 {
                            Text(String(format: "$%.0f daily average", dailyAverage))
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Category breakdown
                    if !categoryBreakdown.isEmpty {
                        sectionCard(title: "By category") {
                            VStack(spacing: 14) {
                                ForEach(categoryBreakdown) { item in
                                    VStack(spacing: 6) {
                                        HStack {
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(item.color)
                                                    .frame(width: 8, height: 8)
                                                Text(item.name)
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                            }
                                            Spacer()
                                            Text(formatCents(item.totalCents))
                                                .font(.system(size: 13, weight: .semibold).monospaced())
                                                .foregroundStyle(Color(hex: "1C1C1E"))
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color(hex: "F0EDEA"))
                                                    .frame(height: 4)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(item.color.opacity(0.65))
                                                    .frame(
                                                        width: totalCents > 0
                                                            ? geo.size.width * CGFloat(item.totalCents) / CGFloat(totalCents)
                                                            : 0,
                                                        height: 4
                                                    )
                                            }
                                        }
                                        .frame(height: 4)
                                    }
                                }
                            }
                        }
                    }

                    // Time breakdown
                    if !timeBuckets.isEmpty {
                        let maxBucket = timeBuckets.map(\.totalCents).max() ?? 1
                        sectionCard(title: timeBucketTitle) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .bottom, spacing: 10) {
                                    ForEach(timeBuckets) { bucket in
                                        VStack(spacing: 4) {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(Color(hex: "346049").opacity(0.75))
                                                .frame(
                                                    width: 28,
                                                    height: maxBucket > 0
                                                        ? max(4, 80 * CGFloat(bucket.totalCents) / CGFloat(maxBucket))
                                                        : 4
                                                )
                                            Text(bucket.label)
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color(hex: "8F9E94"))
                                        }
                                    }
                                }
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .frame(height: 100)
                            }
                        }
                    }

                    Spacer(minLength: 60)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "F6F5F3").ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "EDEAE4"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "4A5E50"))
                .tracking(0.2)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
    }
}
