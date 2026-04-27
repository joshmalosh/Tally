import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil },
           sort: \ExpenseModel.date, order: .reverse) private var expenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @State private var selectedPeriod: ReportPeriod = .sixMonths

    enum ReportPeriod: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case allTime = "All"
    }

    private var filteredExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now)!
            return expenses.filter { $0.date >= start }
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: now)!
            return expenses.filter { $0.date >= start }
        case .oneYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now)!
            return expenses.filter { $0.date >= start }
        case .allTime:
            return expenses
        }
    }

    private var totalSpent: Double {
        Double(filteredExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
    }

    private var monthlyAverage: Double {
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear: months = 12
        case .allTime:
            let oldest = expenses.last?.date ?? Date()
            let monthsElapsed = Calendar.current.dateComponents([.month], from: oldest, to: Date()).month ?? 1
            months = max(1, Double(monthsElapsed))
        }
        return totalSpent / months
    }

    private struct MonthData {
        let label: String
        let total: Double
        let isCurrent: Bool
    }

    private var monthlyData: [MonthData] {
        let calendar = Calendar.current
        let now = Date()
        let monthCount: Int
        switch selectedPeriod {
        case .threeMonths: monthCount = 3
        case .sixMonths: monthCount = 6
        case .oneYear: monthCount = 12
        case .allTime: monthCount = 6
        }
        return (0..<monthCount).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: now)!
            let comps = calendar.dateComponents([.year, .month], from: date)
            let monthTotal = filteredExpenses.filter {
                let ec = calendar.dateComponents([.year, .month], from: $0.date)
                return ec.year == comps.year && ec.month == comps.month
            }.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            let label = date.formatted(.dateTime.month(.abbreviated))
            return MonthData(label: label, total: monthTotal, isCurrent: offset == 0)
        }
    }

    private struct TagSpend: Identifiable {
        let id: String
        let name: String
        let color: Color
        let total: Double
    }

    private var tagBreakdown: [TagSpend] {
        var result: [String: Double] = [:]
        for expense in filteredExpenses {
            if let tagId = expense.resolvedTagIds.first {
                result[tagId, default: 0] += Double(expense.amountCents) / 100.0
            } else {
                result["untagged", default: 0] += Double(expense.amountCents) / 100.0
            }
        }
        return result.map { id, total in
            if id == "untagged" {
                return TagSpend(id: id, name: "Untagged", color: Color(hex: "8F9E94"), total: total)
            }
            let tag = tags.first { $0.id == id }
            return TagSpend(
                id: id,
                name: tag?.name ?? "Unknown",
                color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                total: total
            )
        }.sorted { $0.total > $1.total }
    }

    private var maxMonthlyTotal: Double {
        monthlyData.map(\.total).max() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Header + period toggle
                HStack {
                    Text("Reports")
                        .font(Fonts.brand(24))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(ReportPeriod.allCases, id: \.self) { period in
                            Button {
                                selectedPeriod = period
                            } label: {
                                Text(period.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 9)
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
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // MARK: Summary cards
                HStack(spacing: 10) {
                    summaryCard(
                        label: "Total spent",
                        value: "$\(formatAmount(totalSpent))",
                        sub: selectedPeriod == .allTime ? "All time" : "Last \(selectedPeriod.rawValue)"
                    )
                    summaryCard(
                        label: "Monthly avg",
                        value: "$\(formatAmount(monthlyAverage))",
                        sub: "Per month"
                    )
                }
                .padding(.horizontal, 16)

                // MARK: Bar chart
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spending by month")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "4A5E50"))
                        .padding(.horizontal, 16)

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(monthlyData.enumerated()), id: \.offset) { _, month in
                            VStack(spacing: 4) {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(month.isCurrent ? Color(hex: "2F402E") : Color(hex: "E8F0EA"))
                                            .frame(
                                                height: maxMonthlyTotal > 0
                                                    ? max(4, geo.size.height * CGFloat(month.total / maxMonthlyTotal))
                                                    : 4
                                            )
                                    }
                                }
                                Text(month.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(month.isCurrent ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
                                    .fontWeight(month.isCurrent ? .semibold : .regular)
                            }
                        }
                    }
                    .frame(height: 100)
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                // MARK: Tag breakdown
                if !tagBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("By tag")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            ForEach(Array(tagBreakdown.prefix(6).enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 10, height: 10)
                                    Text(item.name)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: "1C1C1E"))
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color(hex: "F0EDEA"))
                                                .frame(height: 4)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(item.color.opacity(0.5))
                                                .frame(
                                                    width: totalSpent > 0
                                                        ? geo.size.width * CGFloat(item.total / totalSpent)
                                                        : 0,
                                                    height: 4
                                                )
                                        }
                                    }
                                    .frame(height: 4)
                                    Text("$\(formatAmount(item.total))")
                                        .font(.system(size: 13, weight: .semibold).monospaced())
                                        .foregroundStyle(Color(hex: "1C1C1E"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                if index < min(5, tagBreakdown.count - 1) {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 100)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F6F5F3").ignoresSafeArea())
    }

    private func summaryCard(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospaced())
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "8F9E94"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
