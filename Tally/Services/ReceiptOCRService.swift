import Vision
import UIKit

struct ReceiptOCRResult {
    var amount: Double?
    var merchant: String?
    var date: Date?
    var notes: String?
}

enum ReceiptOCRService {

    /// Extract full raw text from image for bulk import. Returns concatenated text blocks.
    static func extractFullText(from image: UIImage) async -> String {
        let cgImage: CGImage
        if let cg = image.cgImage {
            cgImage = cg
        } else if let ciImage = image.ciImage {
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return "" }
            cgImage = cg
        } else if let data = image.pngData(), let reloaded = UIImage(data: data)?.cgImage {
            cgImage = reloaded
        } else {
            return ""
        }
        let observations = await recognizeText(in: cgImage)
        let blocks = observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { obs -> String? in
                obs.topCandidates(1).first?.string
            }
        return blocks.joined(separator: "\n")
    }

    static func extract(from image: UIImage) async -> ReceiptOCRResult {
        let cgImage: CGImage
        if let cg = image.cgImage {
            cgImage = cg
        } else if let ciImage = image.ciImage {
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                return ReceiptOCRResult()
            }
            cgImage = cg
        } else if let data = image.pngData(), let reloaded = UIImage(data: data)?.cgImage {
            cgImage = reloaded
        } else {
            return ReceiptOCRResult()
        }

        let observations = await recognizeText(in: cgImage)
        let blocks = observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { obs -> TextBlock? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return TextBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: obs.boundingBox
                )
            }

        let amount = extractAmount(from: blocks)
        let merchant = extractMerchant(from: blocks)
        let date = extractDate(from: blocks)
        let notes = extractNotes(from: blocks, merchant: merchant)

        return ReceiptOCRResult(amount: amount, merchant: merchant, date: date, notes: notes)
    }

    // MARK: - Vision

    private static func recognizeText(in cgImage: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Amount Extraction

    private static let amountPattern = try! NSRegularExpression(
        pattern: #"[\$£€¥]\s*\d{1,}[,.]?\d{0,2}|\d{1,}[,.]\d{2}\s*[\$£€¥]?|\d{1,}[,.]\d{2}"#,
        options: .caseInsensitive
    )

    private static let percentPattern = try! NSRegularExpression(
        pattern: #"\d[,.]?\d*\s*%"#,
        options: []
    )

    private static let totalLinePattern = try! NSRegularExpression(
        pattern: #"(?<!\w)(?:grand\s+)?(?:total|net)(?:\s+due|\s+payable|\s+amount|\s+charge)?(?:\s*:)?(?!\w)"#,
        options: .caseInsensitive
    )

    private static let subtotalPattern = try! NSRegularExpression(
        pattern: #"sub\s*total|net\s+total"#,
        options: .caseInsensitive
    )

    private static let currencySymbolPattern = try! NSRegularExpression(
        pattern: #"[\$£€¥]"#, options: []
    )

    /// Find the nearest amount block on the same horizontal line as a keyword block.
    /// Vision's bounding boxes use normalized coordinates (0-1), Y increases upward.
    private static func findAmountOnSameLine(as keywordBlock: TextBlock, in blocks: [TextBlock]) -> Double? {
        let yTolerance = 0.015 // blocks within ~1.5% of image height are "same line"
        let keyY = keywordBlock.boundingBox.midY

        var candidates: [(Double, CGFloat)] = [] // (amount, horizontal distance)
        for block in blocks where block.text != keywordBlock.text || block.boundingBox != keywordBlock.boundingBox {
            guard abs(block.boundingBox.midY - keyY) < yTolerance else { continue }
            if let value = parseAmount(from: block.text), value > 0 {
                let dist = abs(block.boundingBox.midX - keywordBlock.boundingBox.midX)
                candidates.append((value, dist))
            }
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private static func extractAmount(from blocks: [TextBlock]) -> Double? {

        var totalCandidates: [(Double, TextBlock)] = []
        var subtotalCandidates: [(Double, TextBlock)] = []
        var totalKeywordBlocks: [TextBlock] = []    // keyword found but no inline amount
        var subtotalKeywordBlocks: [TextBlock] = []

        for block in blocks {
            let text = block.text
            let nsRange = NSRange(text.startIndex..., in: text)
            let isSubtotal = subtotalPattern.firstMatch(in: text, range: nsRange) != nil
            let isTotal = totalLinePattern.firstMatch(in: text, range: nsRange) != nil

            if let value = parseAmount(from: text), value > 0 {
                if isTotal && !isSubtotal {
                    totalCandidates.append((value, block))
                } else if isSubtotal {
                    subtotalCandidates.append((value, block))
                }
            } else {
                if isTotal && !isSubtotal {
                    totalKeywordBlocks.append(block)
                } else if isSubtotal {
                    subtotalKeywordBlocks.append(block)
                }
            }
        }

        // Tier 1a: "Total" blocks that contained both keyword and amount
        if !totalCandidates.isEmpty {
            let best = totalCandidates.min { $0.1.boundingBox.origin.y < $1.1.boundingBox.origin.y }
            if let best {
                return best.0
            }
        }

        // Tier 1b: "Total"/"Net" keyword block with amount in an adjacent block on the same line.
        // Prefer keywords in the lower portion of the receipt (actual totals vs column headers).
        if !totalKeywordBlocks.isEmpty {
            let sorted = totalKeywordBlocks.sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
            let hasBottomKeyword = sorted.contains { $0.boundingBox.origin.y < 0.5 }
            for kwBlock in sorted {
                if hasBottomKeyword && kwBlock.boundingBox.origin.y >= 0.6 { continue }
                if let value = findAmountOnSameLine(as: kwBlock, in: blocks) {
                    return value
                }
            }
        }

        // Tier 2: Keyword lines — "amount due", "balance due", "you pay", etc.
        let fallbackKeywords = [
            "amount due", "balance due", "you pay", "amount", "balance",
            "due", "charge", "payment", "tendered", "tender", "net:"
        ]
        for keyword in fallbackKeywords {
            for block in blocks {
                let lower = block.text.lowercased()
                if lower.contains(keyword) {
                    if let value = parseAmount(from: block.text), value > 0 {
                        return value
                    }
                    if let value = findAmountOnSameLine(as: block, in: blocks) {
                        return value
                    }
                }
            }
        }

        // Tier 3: Fall back to subtotal
        if !subtotalCandidates.isEmpty {
            let best = subtotalCandidates.min(by: { $0.1.boundingBox.origin.y < $1.1.boundingBox.origin.y })
            if let best {
                return best.0
            }
        }
        if !subtotalKeywordBlocks.isEmpty {
            let sorted = subtotalKeywordBlocks.sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
            for kwBlock in sorted {
                if let value = findAmountOnSameLine(as: kwBlock, in: blocks) {
                    return value
                }
            }
        }

        // Tier 4: Largest amount with a currency symbol
        var currencyAmounts: [(Double, TextBlock)] = []
        for block in blocks {
            let nsRange = NSRange(block.text.startIndex..., in: block.text)
            if currencySymbolPattern.firstMatch(in: block.text, range: nsRange) != nil {
                if let value = parseAmount(from: block.text), value > 0 {
                    currencyAmounts.append((value, block))
                }
            }
        }
        if let best = currencyAmounts.max(by: { $0.0 < $1.0 }) {
            return best.0
        }

        // Tier 5: Last resort — largest standalone amount near the bottom half
        let bottomHalf = blocks.filter { $0.boundingBox.origin.y < 0.5 }
        var allAmounts: [(Double, TextBlock)] = []
        for block in bottomHalf {
            if let value = parseAmount(from: block.text), value > 0 {
                allAmounts.append((value, block))
            }
        }
        if let best = allAmounts.max(by: { $0.0 < $1.0 }) {
            return best.0
        }

        return nil
    }

    private static func parseAmount(from text: String) -> Double? {
        let lower = text.lowercased()
        if lower.contains("rate") || (lower.contains("vat:") && lower.contains("%")) { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = amountPattern.matches(in: text, options: [], range: range)

        var last: Double?
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let matched = String(text[matchRange])

            // Skip if this number is followed by a % sign (it's a percentage, not an amount)
            let afterIdx = matchRange.upperBound
            if afterIdx < text.endIndex {
                let remaining = text[afterIdx...].trimmingCharacters(in: .whitespaces)
                if remaining.hasPrefix("%") { continue }
            }

            var numString = matched
            numString = numString.replacingOccurrences(of: "[$£€¥\\s]", with: "", options: .regularExpression)

            if numString.contains(",") && numString.contains(".") {
                numString = numString.replacingOccurrences(of: ",", with: "")
            } else if numString.contains(",") {
                let parts = numString.split(separator: ",")
                if let last = parts.last, last.count == 2 {
                    numString = numString.replacingOccurrences(of: ",", with: ".")
                } else {
                    numString = numString.replacingOccurrences(of: ",", with: "")
                }
            }

            if let value = Double(numString), value > 0 {
                last = value
            }
        }

        return last
    }

    // MARK: - Merchant Extraction

    private static let merchantNoiseWords: Set<String> = [
        "tax invoice", "receipt", "invoice", "duplicate receipt", "duplicate",
        "customer copy", "vat receipt", "vat receipt summary",
        "gst", "abn", "total", "subtotal", "change due", "cash", "card",
        "visa", "mastercard", "eftpos", "amex", "date", "time",
        "www.", "http", ".com", ".com.au", "phone", "tel:", "fax", "email",
        "address", "qty", "price", "ticket", "terminal", "pos ",
        "server", "user:", "auth:", "sale approved",
        "contactless", "chip", "pin", "entry method", "approved",
        "***", "---", "===", "item", "no split bills",
        "low prices", "every day", "change due"
    ]

    private static let merchantSkipPatterns = [
        "receipt", "duplicate", "invoice", "tax", "gst", "abn",
        "total", "subtotal", "cash", "card", "visa", "mastercard", "eftpos", "amex",
        "www.", "http", ".com", "@", "phone", "tel:", "fax", "email",
        "qty", "price", "ticket", "terminal", "pos ",
        "server", "user:", "auth:", "sale approved",
        "contactless", "chip", "pin", "entry method", "approved",
        "***", "---", "===", "item",
        "thank you", "thank", "welcome", "favourite", "favorite",
        "allergen", "visit us", "our food", "guarantee", "ingredients",
        "low prices", "every day", "split bill", "proprietor",
        "email me", "dining experience", "survey", "feedback",
        "give us", "id #", "change due", "no split"
    ]

    // MARK: - Date Extraction

    /// Matches common receipt date formats: DD/MM/YYYY, DD/MM/YY, DD-MM-YYYY, DD.MM.YYYY,
    /// YYYY-MM-DD, plus variants with optional time components.
    private static let datePattern = try! NSRegularExpression(
        pattern: #"\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#,
        options: []
    )

    /// Matches written dates like "09 Dec 2025", "December 9, 2025"
    private static let writtenDatePattern = try! NSRegularExpression(
        pattern: #"\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*[\s,]+\d{2,4}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2}[\s,]+\d{2,4}"#,
        options: .caseInsensitive
    )

    private static func extractDate(from blocks: [TextBlock]) -> Date? {
        // Prefer date blocks in the upper half of the receipt (dates usually near the top)
        let sortedByPosition = blocks.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        for block in sortedByPosition {
            let text = block.text
            if let date = parseDateFromBlock(text) {
                return date
            }
        }
        return nil
    }

    private static func parseDateFromBlock(_ text: String) -> Date? {
        let nsRange = NSRange(text.startIndex..., in: text)

        // Try numeric date patterns first (DD/MM/YYYY, etc.)
        if let match = datePattern.firstMatch(in: text, range: nsRange),
           let matchRange = Range(match.range, in: text) {
            let dateString = String(text[matchRange])
            if let date = parseNumericDate(dateString) {
                return date
            }
        }

        // Try written date patterns (09 Dec 2025, December 9 2025, etc.)
        if let match = writtenDatePattern.firstMatch(in: text, range: nsRange),
           let matchRange = Range(match.range, in: text) {
            let dateString = String(text[matchRange])
            if let date = parseWrittenDate(dateString) {
                return date
            }
        }

        return nil
    }

    private static func parseNumericDate(_ text: String) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine separator
        let separator: Character
        if cleaned.contains("/") { separator = "/" }
        else if cleaned.contains("-") { separator = "-" }
        else if cleaned.contains(".") { separator = "." }
        else { return nil }

        let parts = cleaned.split(separator: separator).map(String.init)
        guard parts.count == 3 else { return nil }

        let a = Int(parts[0]) ?? 0
        let b = Int(parts[1]) ?? 0
        var c = Int(parts[2]) ?? 0

        // Expand 2-digit year
        if c < 100 { c += 2000 }

        var day: Int
        var month: Int
        let year = c

        if a > 2000 {
            // ISO format: YYYY-MM-DD
            day = c    // c was already set to year above, swap
            month = b
            // Actually re-parse for ISO
            let isoYear = a
            let isoMonth = b
            let isoDay = Int(parts[2]) ?? 0
            return makeDate(year: isoYear, month: isoMonth, day: isoDay)
        } else if a > 12 {
            // Unambiguously DD/MM (day > 12)
            day = a; month = b
        } else if b > 12 {
            // Unambiguously MM/DD (day > 12)
            day = b; month = a
        } else {
            // Ambiguous — default to DD/MM (more common worldwide and on UK receipts)
            day = a; month = b
        }

        return makeDate(year: year, month: month, day: day)
    }

    private static func parseWrittenDate(_ text: String) -> Date? {
        let formatters: [String] = [
            "d MMM yyyy", "d MMMM yyyy", "dd MMM yyyy", "dd MMMM yyyy",
            "MMM d, yyyy", "MMMM d, yyyy", "MMM dd, yyyy", "MMMM dd, yyyy",
            "d MMM yy", "dd MMM yy", "MMM d, yy", "MMM dd, yy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formatters {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return date
            }
        }
        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), year >= 2000 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // Noon to avoid timezone edge cases
        return Calendar.current.date(from: components)
    }

    // MARK: - Merchant Extraction

    /// First prominent non-numeric, non-address text block at top of receipt.
    /// Strips noise: TAX INVOICE, RECEIPT, ORDER, etc.
    /// Optionally concatenates one following line (e.g. "BOSTON" + "STEAK HOUSE" = "Boston Steak House").
    private static func extractMerchant(from blocks: [TextBlock]) -> String? {
        let topBlocks = Array(blocks
            .sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
            .prefix(10))

        for (index, block) in topBlocks.enumerated() {
            var text = processBlockForMerchant(block.text)

            if text.count < 2 || text.count > 50 { continue }

            let lower = text.lowercased()
            let isSkippable = merchantSkipPatterns.contains { lower.contains($0) }
            if isSkippable { continue }

            let digitCount = text.filter(\.isNumber).count
            if text.count > 0 && Double(digitCount) / Double(text.count) > 0.4 { continue }

            let specialCount = text.filter { !$0.isLetter && !$0.isWhitespace && $0 != "-" && $0 != "'" && $0 != "&" }.count
            if text.count > 0 && Double(specialCount) / Double(text.count) > 0.3 { continue }

            if block.confidence < 0.7 { continue }

            // Check next block for concatenation (one additional line max)
            var result = text
            if index + 1 < topBlocks.count {
                let nextBlock = topBlocks[index + 1]
                var nextText = processBlockForMerchant(nextBlock.text)
                if nextText.count >= 2 && nextText.count <= 20 &&
                   nextText.filter(\.isNumber).count == 0 {
                    let nextLower = nextText.lowercased()
                    let nextSkippable = merchantSkipPatterns.contains { nextLower.contains($0) }
                    let nextDigitRatio = Double(nextText.filter(\.isNumber).count) / Double(max(1, nextText.count))
                    let nextSpecialCount = nextText.filter { !$0.isLetter && !$0.isWhitespace && $0 != "-" && $0 != "'" && $0 != "&" }.count
                    let nextSpecialRatio = Double(nextSpecialCount) / Double(max(1, nextText.count))
                    if !nextSkippable && nextDigitRatio < 0.4 && nextSpecialRatio < 0.3 && nextBlock.confidence >= 0.7 {
                        result = "\(text) \(nextText)"
                    }
                }
            }
            return result.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        }

        return nil
    }

    private static func processBlockForMerchant(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for noise in merchantNoiseWords {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: noise) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }
        return text
            .replacingOccurrences(of: "^[*\\-=\\s,#]+|[*\\-=\\s,#]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Notes Extraction (Pro only)

    private static let noteDescriptorKeywords = [
        "takeout", "take out", "take away", "take-away",
        "online order", "dine in", "dine-in", "dining in",
        "delivery", "pickup", "pick up", "drive thru", "drive-through",
        "to go", "to-go", "counter", "sit in", "eat in",
        "in store", "instore", "interior", "mesa"
    ]

    /// Assemble short note (max 60 chars) from merchant + descriptors. High confidence only.
    private static func extractNotes(from blocks: [TextBlock], merchant: String?) -> String? {
        guard let merchant, !merchant.isEmpty else { return nil }

        var descriptor: String?
        let topBlocks = blocks
            .sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
            .prefix(12)

        for block in topBlocks {
            guard block.confidence >= 0.75 else { continue }
            let lower = block.text.lowercased()
            for kw in noteDescriptorKeywords {
                if lower.contains(kw) {
                    let cleaned = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.count <= 25 && !cleaned.isEmpty {
                        descriptor = cleaned.prefix(1).uppercased() + cleaned.dropFirst().lowercased()
                        break
                    }
                }
            }
            if descriptor != nil { break }
        }

        // Also check for "TABLE 4", "ORDER #123", "Mesa: 004" style
        if descriptor == nil {
            let tablePattern = try? NSRegularExpression(pattern: #"table\s*#?\s*\d+"#, options: .caseInsensitive)
            let orderPattern = try? NSRegularExpression(pattern: #"order\s*#?\s*\d*"#, options: .caseInsensitive)
            let mesaPattern = try? NSRegularExpression(pattern: #"mesa\s*[:#]?\s*\d+"#, options: .caseInsensitive)
            for block in topBlocks {
                guard block.confidence >= 0.75 else { continue }
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let t = tablePattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let r = Range(t.range, in: text) {
                    descriptor = String(text[r]).prefix(1).uppercased() + String(text[r]).dropFirst().lowercased()
                    break
                }
                if let o = orderPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let r = Range(o.range, in: text) {
                    descriptor = String(text[r]).prefix(1).uppercased() + String(text[r]).dropFirst().lowercased()
                    break
                }
                if mesaPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    descriptor = "Dine in"
                    break
                }
            }
        }

        let merchantPart = String(merchant.prefix(40)).trimmingCharacters(in: .whitespaces)
        let note: String
        if let d = descriptor, !d.isEmpty {
            note = "\(d) — \(merchantPart)"
        } else {
            return nil  // Only populate if we have a descriptor (high confidence)
        }
        return note.count <= 60 ? note : String(note.prefix(57)) + "..."
    }
}

private struct TextBlock {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}
