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
    /// - Indented lines under a heading → heading becomes suggested tag, lines are expenses.
    /// - Top-level items with no parent → no suggested tag.
    /// - Amounts with or without $ valid — strip symbol, parse decimal.
    /// - Items with no parseable amount are skipped.
    static func parse(_ rawText: String) -> [ParsedExpense] {
        let rawLines = rawText.components(separatedBy: .newlines)
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [ParsedExpense] = []
        var currentTag: String?
        var i = 0

        while i < lines.count {
            let stripped = lines[i]
            if stripped.isEmpty { i += 1; continue }
            let isIndented = rawLines[i].hasPrefix("  ") || rawLines[i].hasPrefix("\t") || rawLines[i].hasPrefix(" ")

            // Check if this line looks like a heading (no amount, possibly followed by indented items)
            let (desc, amount) = extractDescriptionAndAmount(from: stripped)

            if amount == nil {
                // No amount — could be a heading
                if !desc.isEmpty {
                    // Peek ahead: are the next lines indented?
                    var hasIndented = false
                    if i + 1 < rawLines.count {
                        let next = rawLines[i + 1]
                        hasIndented = next.hasPrefix("  ") || next.hasPrefix("\t") || next.hasPrefix(" ")
                    }
                    if hasIndented && !isIndented {
                        currentTag = desc
                        i += 1
                        continue
                    }
                }
                i += 1
                continue
            }

            if let amt = amount, amt > 0 {
                let tag = isIndented ? currentTag : nil
                result.append(ParsedExpense(
                    description: desc,
                    amountCents: amt,
                    suggestedTagName: tag
                ))
                if !isIndented { currentTag = nil }
            } else if !isIndented {
                currentTag = nil
            }

            i += 1
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
            desc.removeSubrange(anyMatch.range)
            desc = desc.trimmingCharacters(in: .whitespaces)
            return (desc.isEmpty ? "Expense" : desc, Int(round(value * 100)))
        }

        let amtStr = String(remaining[range])
        guard let value = parseAmount(amtStr), value > 0 else { return (remaining, nil) }
        var desc = remaining
        desc.removeSubrange(match.range)
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
