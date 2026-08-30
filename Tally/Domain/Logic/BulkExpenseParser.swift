import Foundation

/// Tag-name matching shared by the import flows (statement import uses it to map a
/// transaction description onto an existing tag). The old free-text "import from
/// notes" parser lived here too and was removed with that feature.
enum BulkExpenseParser {
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

// MARK: - Statement import (PDF bank statements)

/// One transaction extracted from a statement line. `amountCents` is a positive
/// magnitude; `isDebit` says whether it's money out (kept) or money in (filtered).
struct StatementLine: Identifiable {
    let id = UUID()
    var date: Date
    var description: String
    var amountCents: Int
    var isDebit: Bool
}

/// Parses raw bank-statement text (one transaction per line, roughly
/// `date  description  amount [running balance]`) into `StatementLine`s.
///
/// Heuristic v1 for common AU/US layouts; it grows via `StatementParserTests` as
/// real statements surface (like the OCR corpus). Currency is applied later from
/// the user's default (no FX). Debit vs credit is read from sign / parentheses /
/// `CR`·`DR`; an unmarked amount defaults to debit — the review screen and the
/// debit-only filter let the user drop anything misread. Dates are read `dd/MM`
/// (AU default) when ambiguous; the user can fix a date in review.
enum StatementParser {

    struct MoneyToken {
        let range: Range<String.Index>
        let cents: Int
        let isDebit: Bool
    }

    static func parse(_ rawText: String) -> [StatementLine] {
        var out: [StatementLine] = []
        for raw in rawText.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !isNoise(line) else { continue }
            guard let (date, rest) = leadingDate(in: line) else { continue }
            let tokens = moneyTokens(in: rest)
            guard !tokens.isEmpty else { continue }
            // With two or more amounts, the last is usually a running balance, so
            // the transaction amount is the one before it.
            let amount = tokens.count >= 2 ? tokens[tokens.count - 2] : tokens[0]
            let desc = String(rest[..<tokens[0].range.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:"))
            guard amount.cents > 0, !desc.isEmpty else { continue }
            out.append(StatementLine(date: date, description: desc,
                                     amountCents: amount.cents, isDebit: amount.isDebit))
        }
        return out
    }

    // MARK: Noise

    private static let noisePhrases = [
        "opening balance", "closing balance", "brought forward", "carried forward",
        "statement period", "account number", "account name", "bsb", "sort code",
        "date description", "transaction details", "page "
    ]
    private static func isNoise(_ line: String) -> Bool {
        let l = line.lowercased()
        return noisePhrases.contains { l.contains($0) }
    }

    // MARK: Money

    private static func moneyTokens(in text: String) -> [MoneyToken] {
        // A money amount has two decimals (filters out dates, reference numbers,
        // card last-4). Optional $, thousands commas, and debit/credit markers.
        let pattern = #"([(\-]?)\s*\$?(\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})\s*(\)|CR|DR|cr|dr|\+|\-)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        var tokens: [MoneyToken] = []
        for m in regex.matches(in: text, range: ns) {
            guard let full = Range(m.range, in: text),
                  let numR = Range(m.range(at: 2), in: text) else { continue }
            let numStr = text[numR].replacingOccurrences(of: ",", with: "")
            guard let val = Double(numStr) else { continue }
            let lead  = group(m, 1, in: text)
            let trail = group(m, 3, in: text).uppercased()
            let credit = (trail == "CR" || trail == "+")
            tokens.append(MoneyToken(range: full, cents: Int((val * 100).rounded()), isDebit: !credit))
        }
        return tokens
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String {
        guard m.range(at: i).location != NSNotFound,
              let r = Range(m.range(at: i), in: text) else { return "" }
        return String(text[r])
    }

    // MARK: Date

    private static func leadingDate(in line: String) -> (date: Date, rest: String)? {
        let patterns = [
            #"^(\d{4}-\d{2}-\d{2})"#,                          // 2026-03-12
            #"^(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})"#,          // 12/03/2026, 3-3-26
            #"^(\d{1,2}\s+[A-Za-z]{3,9}\.?(?:\s+\d{2,4})?)"#,  // 03 Mar, 3 March 2026
            #"^([A-Za-z]{3,9}\.?\s+\d{1,2}(?:,?\s+\d{2,4})?)"# // Mar 03, March 3, 2026
        ]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p),
                  let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let r = Range(m.range(at: 1), in: line) else { continue }
            let token = String(line[r])
            if let date = parseDate(token) {
                let rest = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (date, rest)
            }
        }
        return nil
    }

    // Formats that carry a real year — kept as parsed.
    private static let datedFormats = [
        "yyyy-MM-dd", "dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd-MM-yy",
        "dd.MM.yyyy", "d MMM yyyy", "d MMMM yyyy", "MMM d yyyy", "MMMM d yyyy"
    ]
    // Year-less formats (e.g. "22 AUG"). DateFormatter defaults these to the year
    // 2000, so we stamp the current year on them instead.
    private static let yearLessFormats = ["d MMM", "d MMMM", "MMM d", "MMMM d"]

    private static func parseDate(_ token: String) -> Date? {
        let t = token.replacingOccurrences(of: ",", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")

        for fmt in datedFormats {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        let cal = Calendar.current
        for fmt in yearLessFormats {
            f.dateFormat = fmt
            if let d = f.date(from: t) {
                var comps = cal.dateComponents([.month, .day], from: d)
                comps.year = cal.component(.year, from: Date())
                return cal.date(from: comps) ?? d
            }
        }
        return nil
    }
}
