import Foundation
import Darwin

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
    /// - Headings: lines ending with ":" or with no parseable amount become suggested tags.
    /// - Tag context applies only to lines that are clearly children: indented, dash-prefixed, or immediately following a heading.
    /// - Blank line or new heading resets tag context. Top-level lines (no indent, no dash, not immediately after heading) → Untagged.
    static func parse(_ rawText: String) -> [ParsedExpense] {
        let rawLines = rawText.components(separatedBy: .newlines)

        var result: [ParsedExpense] = []
        var currentTag: String?
        var previousWasHeading = false

        for i in rawLines.indices {
            let raw = rawLines[i]
            let stripped = raw.trimmingCharacters(in: .whitespaces)

            if stripped.isEmpty {
                currentTag = nil
                previousWasHeading = false
                continue
            }

            let isIndented = raw.hasPrefix("  ") || raw.hasPrefix("\t") || (raw.hasPrefix(" ") && !raw.trimmingCharacters(in: .whitespaces).isEmpty)
            let hasDashPrefix = stripped.hasPrefix("-") || stripped.hasPrefix("–") || stripped.hasPrefix("—")
            let isChildOfHeading = isIndented || hasDashPrefix

            let (desc, amount) = extractDescriptionAndAmount(from: stripped)

            if let amt = amount, amt > 0 {
                let suggestedTag: String?
                if isChildOfHeading || previousWasHeading {
                    suggestedTag = currentTag
                } else {
                    suggestedTag = nil
                }
                previousWasHeading = false
                result.append(ParsedExpense(
                    description: desc.isEmpty ? "Expense" : desc,
                    amountCents: amt,
                    suggestedTagName: suggestedTag
                ))
            } else {
                if !desc.isEmpty {
                    let headingName = stripped.hasSuffix(":")
                        ? String(stripped.dropLast()).trimmingCharacters(in: .whitespaces)
                        : desc
                    if !headingName.isEmpty {
                        currentTag = headingName
                        previousWasHeading = true
                    }
                } else {
                    previousWasHeading = false
                }
            }
        }

        return result
    }

    private static func extractDescriptionAndAmount(from line: String) -> (description: String, amountCents: Int?) {
        let stripped = line.trimmingCharacters(in: .whitespaces)

        // Match description and amount — works with or without colon. Finds last numeric token.
        // Examples: "Mouse/Keyboard 88.99999999" → desc: Mouse/Keyboard, amt: 88.99999999
        //           "Monitor Arms: 58" → desc: Monitor Arms, amt: 58
        //           "Green Slip: $577.81" → desc: Green Slip, amt: 577.81
        let pattern = #"^(.*?)\s*:?\s*\$?([\d,]+\.?\d*)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
              m.numberOfRanges >= 3,
              let descRange = Range(m.range(at: 1), in: stripped),
              let amtRange = Range(m.range(at: 2), in: stripped)
        else { return (stripped, nil) }

        var amtStr = String(stripped[amtRange]).replacingOccurrences(of: ",", with: "")
        amtStr = amtStr.replacingOccurrences(of: #"(\.\d{2})\d+"#, with: "$1", options: .regularExpression)

        guard let value = Double(amtStr), value > 0
        else { return (stripped, nil) }

        let cents = Int(Darwin.round(value * 100))

        let desc = String(stripped[descRange])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—:"))
        return (desc.isEmpty ? "Expense" : desc, cents)
    }

    private static func parseAmount(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "[$£€¥\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
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
