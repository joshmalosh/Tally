import Foundation

enum ExpenseCalculations {
    static func sortedByDate(expenses: [Expense], ascending: Bool = false) -> [Expense] {
        expenses
            .filter { $0.deletedAt == nil }
            .sorted { ascending ? $0.date < $1.date : $0.date > $1.date }
    }

    /// Generate CSV content. `receiptFilenames` maps expense ID → filename in the receipts folder.
    static func generateCSV(expenses: [Expense], tags: [Tag], receiptFilenames: [String: String] = [:]) -> String {
        let header = "date,description,merchant,currency,amount,groups,tags,notes,receipt"
        let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

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

            let receiptFile = receiptFilenames[expense.id] ?? ""

            let fields = [
                dateFormatter.string(from: expense.date),
                csvEscape(expense.description ?? ""),
                csvEscape(expense.merchant ?? ""),
                expense.currency,
                amount,
                csvEscape(groupField),
                csvEscape(tagNames),
                csvEscape(expense.notes ?? ""),
                receiptFile,
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
