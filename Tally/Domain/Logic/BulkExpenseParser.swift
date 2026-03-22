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
