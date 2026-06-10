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
            // Dispatch to a background queue — handler.perform is synchronous and
            // would block the main thread if called directly from an @MainActor context.
            DispatchQueue.global(qos: .userInitiated).async {
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
        let yTolerance = 0.03 // blocks within ~3% of image height are "same line"
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

    /// First prominent line at the **top** of the receipt: no digits, short phrase, high confidence.
    /// Strips required noise phrases (TAX INVOICE, RECEIPT, ORDER, ABN, GST, etc.).
    private static let merchantNoisePhrases: [String] = [
        "tax invoice", "receipt", "invoice", "order", "abn", "gst", "duplicate",
        "subtotal", "total", "change", "cash", "card", "visa", "mastercard", "eftpos", "amex",
        "date", "time", "thank", "welcome", "phone", "tel:", "fax", "email", "address",
        "qty", "price", "ticket", "terminal", "pos", "take away", "takeout", "dine in",
        "table", "server", "www.", "http", ".com", "item",
        "amount", "description", "service", "docket", "balance", "payment"
    ]

    private static func extractMerchant(from blocks: [TextBlock]) -> String? {
        let ordered = blocks.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        for block in ordered {
            guard block.confidence >= 0.75 else { continue }

            let raw = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.count >= 2 else { continue }

            // Never use a line that contains any numeric character (amounts, ABN, street numbers, item lines).
            if raw.contains(where: { $0.isNumber }) { continue }

            var text = raw
            for phrase in merchantNoisePhrases {
                text = text.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
            }
            text = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-•·"))

            guard text.count >= 2, text.count <= 45 else { continue }
            if text.contains(where: { $0.isNumber }) { continue }

            let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
            guard wordCount <= 6 else { continue }

            return text
        }

        return nil
    }

    // MARK: - Notes Extraction (Pro only)

    private static let noteDescriptorKeywords = [
        "takeout", "take away", "take-away", "online order", "dine in", "dine-in",
        "delivery", "pickup", "pick up", "drive thru", "drive-through",
        "to go", "to-go", "counter"
    ]

    /// Assemble short note (max 60 chars) from merchant + descriptors. High confidence only.
    private static func extractNotes(from blocks: [TextBlock], merchant: String?) -> String? {
        guard let merchant, !merchant.isEmpty else { return nil }

        var descriptor: String?
        let topBlocks = blocks
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
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

        // Also check for "TABLE 4", "ORDER #123" style
        if descriptor == nil {
            let tablePattern = try? NSRegularExpression(pattern: #"table\s*#?\s*\d+"#, options: .caseInsensitive)
            let orderPattern = try? NSRegularExpression(pattern: #"order\s*#?\s*\d*"#, options: .caseInsensitive)
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

// MARK: - TagSuggestionEngine
// Kept here (in a tracked Services file) so it compiles without needing a separate
// Xcode project registration step.

/// Matches receipt context (merchant + notes text) against the user's tag list
/// to produce a single best-guess suggestion shown in the "Tally Suggests" banner.
enum TagSuggestionEngine {

    struct Suggestion {
        let tag: TagModel
        /// Human-readable description of why we suggested this tag.
        /// e.g. "dining or food purchase"
        let reason: String
    }

    /// Returns the best matching tag for the given receipt context, or nil if no
    /// confident match is found.
    static func suggest(merchant: String, notes: String, tags: [TagModel]) -> Suggestion? {
        let corpus = [merchant, notes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        guard !corpus.isEmpty else { return nil }

        let rules: [(keywords: [String], tagHints: [String], reason: String)] = [
            (
                ["restaurant", "cafe", "coffee", "bistro", "kitchen", "eatery",
                 "burger", "pizza", "sushi", "noodle", "curry", "bakery", "deli",
                 "diner", "breakfast", "lunch", "dinner", "brunch", "takeaway",
                 "take away", "takeout", "ubereats", "doordash", "menulog"],
                ["dining", "food", "meals", "eat", "drink", "restaurant"],
                "dining or food purchase"
            ),
            (
                ["uber", "lyft", "ola", "taxi", "cab", "bus ticket", "train",
                 "metro", "tram", "ferry", "petrol", "fuel", "gas station",
                 "parking", "toll", "transit"],
                ["transport", "travel", "transit", "commute"],
                "transport or travel expense"
            ),
            (
                ["woolworths", "coles", "aldi", "costco", "safeway",
                 "supermarket", "fresh market", "produce", "greengrocer",
                 "grocery"],
                ["groceries", "grocery", "supermarket"],
                "grocery purchase"
            ),
            (
                ["netflix", "spotify", "hulu", "disney+", "apple tv",
                 "apple one", "google play", "icloud", "subscription",
                 "monthly plan", "annual plan", "membership fee"],
                ["subscription", "subscriptions", "streaming", "software"],
                "subscription or software service"
            ),
            (
                ["pharmacy", "chemist", "medical centre", "doctor", "hospital",
                 "clinic", "health", "gym", "fitness", "wellness", "dentist",
                 "optical", "physiotherapy"],
                ["health", "medical", "wellbeing", "fitness"],
                "health or medical purchase"
            ),
            (
                ["amazon", "ebay", "shop", "store", "clothing", "apparel",
                 "fashion", "shoes", "accessories", "department store",
                 "outlet", "zara", "uniqlo"],
                ["shopping", "retail", "clothing", "fashion"],
                "shopping purchase"
            ),
            (
                ["bunnings", "home depot", "hardware", "tools", "home improvement",
                 "plumbing", "electrical", "furniture", "ikea", "kmart", "target"],
                ["home improvement", "hardware", "tools", "furniture"],
                "home or hardware purchase"
            ),
            (
                ["office", "stationery", "printer", "supplies", "equipment",
                 "work expense", "business"],
                ["work", "office", "business", "stationery"],
                "work or office purchase"
            ),
            (
                ["hotel", "airbnb", "motel", "hostel", "accommodation", "resort",
                 "flight", "airline", "airport", "booking.com", "expedia"],
                ["accommodation", "travel", "holiday", "flights"],
                "accommodation or travel booking"
            ),
            (
                ["electricity", "gas bill", "water bill", "internet",
                 "phone bill", "telstra", "optus", "vodafone", "insurance",
                 "utility", "utilities", "council rates"],
                ["utilities", "bills", "phone", "insurance"],
                "utility or bill payment"
            ),
        ]

        for rule in rules {
            for keyword in rule.keywords where corpus.contains(keyword) {
                for hint in rule.tagHints {
                    if let match = tags.first(where: {
                        !$0.isSystemTag && $0.name.lowercased().contains(hint)
                    }) ?? tags.first(where: {
                        $0.name.lowercased().contains(hint)
                    }) {
                        return Suggestion(tag: match, reason: rule.reason)
                    }
                }
            }
        }

        return nil
    }
}
