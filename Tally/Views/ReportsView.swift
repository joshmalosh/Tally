import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil },
           sort: \ExpenseModel.date, order: .reverse) private var expenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @State private var selectedPeriod: ReportPeriod = .sixMonths
    @State private var selectedMonthOffset: Int = 0   // 0 = current month
    @State private var expandedTagId: String? = nil

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
            return expenses.filter { $0.date >= calendar.date(byAdding: .month, value: -3, to: now)! }
        case .sixMonths:
            return expenses.filter { $0.date >= calendar.date(byAdding: .month, value: -6, to: now)! }
        case .oneYear:
            return expenses.filter { $0.date >= calendar.date(byAdding: .year, value: -1, to: now)! }
        case .allTime:
            return expenses
        }
    }

    private var totalSpent: Double {
        Double(selectedMonthExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
    }

    private var monthlyAverage: Double {
        let total = Double(filteredExpenses.reduce(0) { $0 + $1.amountCents }) / 100.0
        let months: Double
        switch selectedPeriod {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear: months = 12
        case .allTime:
            let oldest = expenses.last?.date ?? Date()
            months = max(1, Double(Calendar.current.dateComponents([.month], from: oldest, to: Date()).month ?? 1))
        }
        return total / months
    }

    private struct MonthData {
        let label: String
        let total: Double
        let isCurrent: Bool
        let offset: Int  // 0 = current month, 1 = last month, etc.
    }

    private var monthCount: Int {
        switch selectedPeriod {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .allTime: return 6
        }
    }

    private var monthlyData: [MonthData] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<monthCount).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: now)!
            let comps = calendar.dateComponents([.year, .month], from: date)
            let monthTotal = filteredExpenses.filter {
                let ec = calendar.dateComponents([.year, .month], from: $0.date)
                return ec.year == comps.year && ec.month == comps.month
            }.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            let label = date.formatted(.dateTime.month(.abbreviated))
            return MonthData(label: label, total: monthTotal, isCurrent: offset == 0, offset: offset)
        }
    }

    // Expenses for the currently selected month
    private var selectedMonthExpenses: [ExpenseModel] {
        let calendar = Calendar.current
        let now = Date()
        let targetDate = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: now)!
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        return filteredExpenses.filter {
            let ec = calendar.dateComponents([.year, .month], from: $0.date)
            return ec.year == comps.year && ec.month == comps.month
        }
    }

    private struct TagSpend: Identifiable {
        let id: String
        let name: String
        let color: Color
        let total: Double
        let expenses: [ExpenseModel]
    }

    private var tagBreakdown: [TagSpend] {
        var result: [String: [ExpenseModel]] = [:]
        for expense in selectedMonthExpenses {
            let tagId = expense.resolvedTagIds.first ?? "untagged"
            result[tagId, default: []].append(expense)
        }
        return result.map { id, expList in
            let total = expList.reduce(0.0) { $0 + Double($1.amountCents) / 100.0 }
            if id == "untagged" {
                return TagSpend(id: id, name: "Untagged", color: Color(hex: "8F9E94"), total: total, expenses: expList)
            }
            let tag = tags.first { $0.id == id }
            return TagSpend(
                id: id,
                name: tag?.name ?? "Unknown",
                color: tag?.tagColor.primaryColor ?? Color(hex: "8F9E94"),
                total: total,
                expenses: expList.sorted { $0.date > $1.date }
            )
        }.sorted { $0.total > $1.total }
    }

    private var maxMonthlyTotal: Double {
        monthlyData.map(\.total).max() ?? 1
    }

    private var selectedMonthLabel: String {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: now)!
        return date.formatted(.dateTime.month(.wide).year())
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
                                selectedMonthOffset = 0
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
                        sub: selectedMonthLabel
                    )
                    summaryCard(
                        label: "Monthly avg",
                        value: "$\(formatAmount(monthlyAverage))",
                        sub: "Per month"
                    )
                }
                .padding(.horizontal, 16)

                // MARK: Bar chart — tappable months
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spending by month")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "4A5E50"))
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(monthlyData.enumerated()), id: \.offset) { _, month in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedMonthOffset = month.offset
                                        expandedTagId = nil
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        // Amount label above bar
                                        if month.total > 0 {
                                            Text("$\(formatAmount(month.total))")
                                                .font(.system(size: 8))
                                                .foregroundStyle(selectedMonthOffset == month.offset ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
                                        } else {
                                            Text("")
                                                .font(.system(size: 8))
                                        }
                                        // Bar
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(selectedMonthOffset == month.offset ? Color(hex: "2F402E") : Color(hex: "E8F0EA"))
                                            .frame(
                                                width: 28,
                                                height: maxMonthlyTotal > 0
                                                    ? max(4, 80 * CGFloat(month.total / maxMonthlyTotal))
                                                    : 4
                                            )
                                        // Month label
                                        Text(month.label)
                                            .font(.system(size: 9))
                                            .foregroundStyle(selectedMonthOffset == month.offset ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
                                            .fontWeight(selectedMonthOffset == month.offset ? .semibold : .regular)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(height: 110)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                // MARK: Tag breakdown — expandable, per-tag cards
                if !tagBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("By tag — \(selectedMonthLabel)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        // Each tag gets its own card — no shared outer card
                        ForEach(Array(tagBreakdown.prefix(8).enumerated()), id: \.element.id) { _, item in
                            VStack(spacing: 0) {
                                // Tag summary row
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedTagId = expandedTagId == item.id ? nil : item.id
                                    }
                                } label: {
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
                                        Image(systemName: expandedTagId == item.id ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Color(hex: "8F9E94"))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // Expanded expense rows — separate background, no clipping
                                if expandedTagId == item.id {
                                    VStack(spacing: 0) {
                                        Divider().padding(.horizontal, 16)
                                        ForEach(item.expenses.prefix(10), id: \.id) { expense in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(expense.merchant ?? expense.expenseDescription ?? "Expense")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(Color(hex: "1C1C1E"))
                                                    Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(Color(hex: "8F9E94"))
                                                }
                                                Spacer()
                                                Text("$\(formatAmount(Double(expense.amountCents) / 100.0))")
                                                    .font(.system(size: 13, weight: .semibold).monospaced())
                                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 9)
                                            .background(Color(hex: "F8F6F3"))
                                            if expense.id != item.expenses.prefix(10).last?.id {
                                                Divider().padding(.horizontal, 16)
                                            }
                                        }
                                    }
                                }
                            }
                            // Each tag section is its own card
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "EDEAE4"), lineWidth: 0.5))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.top, 4)
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
