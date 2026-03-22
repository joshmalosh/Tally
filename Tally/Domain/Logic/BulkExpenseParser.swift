import Foundation

/// Parsed expense item from bulk import — before tag resolution and SwiftData persistence.
struct ParsedExpense: Identifiable {
    let id: String
    var description: String
    var amountCents: Int
    var suggestedTagName: String?

    init(id: String = UUID().uuidString, description: String, amountCents: Int, suggestedTagName: String? = nil) {
        self.id = id
        self.description = description
        self.amountCents = amountCents
        self.suggestedTagName = suggestedTagName
    }
}

enum BulkExpenseParser {
    /// Parse raw text into expenses.
    /// - Headings: lines ending with ":" or with no parseable amount become suggested tags for following expenses.
    /// - Lines with amounts are expenses and inherit the most recent heading as suggested tag.
    /// - Amounts with or without $ valid — strip symbol, parse decimal.
    /// - Items with no parseable amount are skipped (unless they're headings).
    static func parse(_ rawText: String) -> [ParsedExpense] {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [ParsedExpense] = []
        var currentTag: String?

        for stripped in lines {
            if stripped.isEmpty { continue }

            let (desc, amount) = extractDescriptionAndAmount(from: stripped)

            if let amt = amount, amt > 0 {
                // Has amount → expense row; use current heading as suggested tag
                result.append(ParsedExpense(
                    description: desc.isEmpty ? "Expense" : desc,
                    amountCents: amt,
                    suggestedTagName: currentTag
                ))
            } else {
                // No amount → heading (colon at end OR absence of amount)
                if !desc.isEmpty {
                    let headingName = stripped.hasSuffix(":")
                        ? String(stripped.dropLast()).trimmingCharacters(in: .whitespaces)
                        : desc
                    if !headingName.isEmpty {
                        currentTag = headingName
                    }
                }
            }
        }

        return result
    }

    private static func extractDescriptionAndAmount(from line: String) -> (description: String, amountCents: Int?) {
        var remaining = line

        // Try to find amount at end (common pattern: "Coffee $4.50" or "Coffee 4.50")
        let amountPattern = #"[\$£€¥]?\s*(\d{1,}[,.]?\d{0,2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: amountPattern),
              let match = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
              let range = Range(match.range(at: 1), in: remaining)
        else {
            // Try amount in middle or at start
            let anyAmount = #"[\$£€¥]?\s*(\d{1,}[,.]?\d{0,2})"#
            guard let anyRegex = try? NSRegularExpression(pattern: anyAmount),
                  let anyMatch = anyRegex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                  let amtRange = Range(anyMatch.range(at: 1), in: remaining)
            else { return (remaining, nil) }

            let amtStr = String(remaining[amtRange])
            guard let value = parseAmount(amtStr), value > 0 else { return (remaining, nil) }
            var desc = remaining
            if let fullRange = Range(anyMatch.range, in: remaining) {
                desc.removeSubrange(fullRange)
            }
            desc = desc.trimmingCharacters(in: .whitespaces)
            return (desc.isEmpty ? "Expense" : desc, Int(round(value * 100)))
        }

        let amtStr = String(remaining[range])
        guard let value = parseAmount(amtStr), value > 0 else { return (remaining, nil) }
        var desc = remaining
        if let fullRange = Range(match.range, in: remaining) {
            desc.removeSubrange(fullRange)
        }
        desc = desc.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-–—:"))
        return (desc.isEmpty ? "Expense" : desc, Int(round(value * 100)))
    }

    private static func parseAmount(_ text: String) -> Double? {
        var s = text
            .replacingOccurrences(of: "[$£€¥\\s]", with: "", options: .regularExpression)
        if s.contains(",") && s.contains(".") {
            s = s.replacingOccurrences(of: ",", with: "")
        } else if s.contains(",") {
            let parts = s.split(separator: ",")
            if let last = parts.last, last.count == 2 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        }
        return Double(s)
    }

    /// Fuzzy match suggested tag name to existing tag. Case-insensitive, minor spelling differences allowed.
    static func findMatchingTag(suggested: String, existingTags: [String]) -> String? {
        let lower = suggested.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }

        for existing in existingTags {
            let exLower = existing.lowercased()
            if exLower == lower { return existing }
            if levenshteinSimilarity(lower, exLower) > 0.85 { return existing }
        }
        return nil
    }

    private static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        let maxLen = max(a.count, b.count)
        return 1 - Double(dp[a.count][b.count]) / Double(maxLen)
    }
}
