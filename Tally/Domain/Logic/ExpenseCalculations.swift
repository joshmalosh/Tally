import Foundation

enum ExpenseCalculations {
    static func monthlyTotal(expenses: [Expense], month: Date, currency: String) -> MonthlyTotal {
        let calendar = Calendar.current
        let filtered = expenses.filter { expense in
            expense.deletedAt == nil
                && expense.currency == currency
                && calendar.isDate(expense.date, equalTo: month, toGranularity: .month)
        }
        let total = filtered.reduce(0) { $0 + $1.amountCents }
        return MonthlyTotal(month: month, totalCents: total, currency: currency, expenseCount: filtered.count)
    }

    static func groupByTag(expenses: [Expense]) -> [String: [Expense]] {
        var result: [String: [Expense]] = [:]
        for expense in expenses where expense.deletedAt == nil {
            for tagId in expense.tagIds {
                result[tagId, default: []].append(expense)
            }
        }
        return result
    }

    static func sortedByDate(expenses: [Expense], ascending: Bool = false) -> [Expense] {
        expenses
            .filter { $0.deletedAt == nil }
            .sorted { ascending ? $0.date < $1.date : $0.date > $1.date }
    }

    static func filterByDateRange(expenses: [Expense], start: Date, end: Date) -> [Expense] {
        expenses.filter { expense in
            expense.deletedAt == nil
                && expense.date >= start
                && expense.date <= end
        }
    }

    static func filterByTag(expenses: [Expense], tagId: String) -> [Expense] {
        expenses.filter { $0.deletedAt == nil && $0.tagIds.contains(tagId) }
    }

    /// Filter expenses by a group tag — returns expenses that have any child tag of the given parent.
    static func filterByGroup(expenses: [Expense], groupId: String, tags: [Tag]) -> [Expense] {
        let childIds = Set(tags.filter { $0.parentId == groupId }.map(\.id))
        return expenses.filter { expense in
            expense.deletedAt == nil && !expense.tagIds.filter({ childIds.contains($0) }).isEmpty
        }
    }

    static func generateCSV(expenses: [Expense], tags: [Tag]) -> String {
        let header = "date,description,merchant,amount,currency,groups,tags,notes,attachment_filename,source,created_at"
        let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()

        let rows = sortedByDate(expenses: expenses, ascending: true).map { expense in
            let amount = String(format: "%.2f", Double(expense.amountCents) / 100.0)

            let resolvedTags = expense.tagIds.compactMap { tagMap[$0] }
            let tagNames = resolvedTags.isEmpty ? "Untagged" : resolvedTags.map(\.name).joined(separator: "; ")

            var groupNames: [String] = []
            for tag in resolvedTags {
                if let parentId = tag.parentId, let parent = tagMap[parentId] {
                    if !groupNames.contains(parent.name) { groupNames.append(parent.name) }
                }
            }
            let groupField = groupNames.joined(separator: "; ")

            let fields = [
                dateFormatter.string(from: expense.date),
                csvEscape(expense.description ?? ""),
                csvEscape(expense.merchant ?? ""),
                amount,
                expense.currency,
                csvEscape(groupField),
                csvEscape(tagNames),
                csvEscape(expense.notes ?? ""),
                expense.attachmentKey ?? "",
                expense.source.rawValue,
                isoFormatter.string(from: expense.createdAt),
            ]
            return fields.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains(";") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
