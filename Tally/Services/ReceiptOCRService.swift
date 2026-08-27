import Vision
import OSLog
import UIKit

struct ReceiptOCRResult {
    var amount: Double?
    var merchant: String?
    var date: Date?
    var notes: String?
    /// ISO 4217 code when the receipt names its currency unambiguously
    /// (€ → EUR, £ → GBP, "AUD" → AUD…). A bare "$" stays nil.
    var currencyCode: String?
    /// Lower-ranked merchant guesses (clean, gate-passing names only) for the
    /// "Doesn't look right?" picker. Excludes the chosen `merchant`.
    var merchantAlternates: [String] = []
}

enum ReceiptOCRService {

    /// Extract full raw text from image for bulk import. Returns concatenated text blocks.
    static func extractFullText(from image: UIImage) async -> String {
        let cgImage: CGImage
        var orientation: CGImagePropertyOrientation = .up
        if let cg = image.cgImage {
            cgImage = cg
            orientation = cgOrientation(from: image.imageOrientation)
        } else if let ciImage = image.ciImage {
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return "" }
            cgImage = cg
            orientation = cgOrientation(from: image.imageOrientation)
        } else if let data = image.pngData(), let reloaded = UIImage(data: data)?.cgImage {
            // pngData() bakes the orientation in, so the reload is already upright.
            cgImage = reloaded
        } else {
            return ""
        }
        let observations = await recognizeText(in: cgImage, orientation: orientation)
        let blocks = observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { obs -> String? in
                obs.topCandidates(1).first?.string
            }
        return blocks.joined(separator: "\n")
    }

    #if DEBUG
    /// Regression test hook: run field extraction over synthetic OCR lines
    /// (text + normalized bounding box, Vision-style: y increases upward).
    /// Lets tests pin the behaviour on real receipt layouts without images.
    static func extractForTesting(_ lines: [(text: String, box: CGRect)]) -> ReceiptOCRResult {
        extractForTesting(lines.map { (text: $0.text, box: $0.box, confidence: Float(1.0)) })
    }

    /// Test hook for the orientation mapping. Camera photos store pixels sideways
    /// with a `.right` display flag; feeding that flag to Vision is what keeps a
    /// receipt from being read rotated (which sank the merchant heuristics).
    static func orientationForTesting(_ ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        cgOrientation(from: ui)
    }

    /// Confidence-aware variant. Vision scores a crumpled letterhead well below
    /// crisp body text, and which of them wins is a real source of misreads, so
    /// tests need to be able to set it.
    static func extractForTesting(_ lines: [(text: String, box: CGRect, confidence: Float)]) -> ReceiptOCRResult {
        let blocks = lines.map { TextBlock(text: $0.text, confidence: $0.confidence, boundingBox: $0.box) }
        let ranked = rankedMerchants(from: blocks)
        let merchant = ranked.first
        return ReceiptOCRResult(
            amount: extractAmount(from: blocks),
            merchant: merchant,
            date: extractDate(from: blocks),
            notes: extractNotes(from: blocks, merchant: merchant),
            currencyCode: detectCurrency(in: blocks),
            merchantAlternates: Array(ranked.dropFirst().prefix(5))
        )
    }
    #endif

    static func extract(from image: UIImage) async -> ReceiptOCRResult {
        let cgImage: CGImage
        var orientation: CGImagePropertyOrientation = .up
        if let cg = image.cgImage {
            cgImage = cg
            orientation = cgOrientation(from: image.imageOrientation)
        } else if let ciImage = image.ciImage {
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                return ReceiptOCRResult()
            }
            cgImage = cg
            orientation = cgOrientation(from: image.imageOrientation)
        } else if let data = image.pngData(), let reloaded = UIImage(data: data)?.cgImage {
            // pngData() bakes the orientation in, so the reload is already upright.
            cgImage = reloaded
        } else {
            return ReceiptOCRResult()
        }

        let observations = await recognizeText(in: cgImage, orientation: orientation)
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

        #if DEBUG
        dumpBlocks(blocks)
        #endif

        let amount = extractAmount(from: blocks)
        let ranked = rankedMerchants(from: blocks)
        let merchant = ranked.first
        let date = extractDate(from: blocks)
        let notes = extractNotes(from: blocks, merchant: merchant)
        let currencyCode = detectCurrency(in: blocks)

        #if DEBUG
        // Receipt content is the user's data — kept private so it's redacted in
        // release/sysdiagnose, but visible in a DEBUG run for OCR regression work.
        Log.ocr.debug("result amount=\(String(describing: amount), privacy: .private) merchant=\(String(describing: merchant), privacy: .private) currency=\(String(describing: currencyCode), privacy: .private) date=\(String(describing: date), privacy: .private)")
        #endif

        return ReceiptOCRResult(
            amount: amount, merchant: merchant, date: date,
            notes: notes, currencyCode: currencyCode,
            merchantAlternates: Array(ranked.dropFirst().prefix(5))
        )
    }

    // MARK: - Vision

    /// Map a UIImage's display orientation to the Vision/CoreGraphics enum so the
    /// handler can undo it. A camera photo's pixels are stored sideways with a
    /// `.right` orientation flag; the display applies the flag but `image.cgImage`
    /// is the raw sideways buffer, so Vision must be told the flag or it reads the
    /// receipt rotated (every merchant/top-of-receipt heuristic then misfires).
    /// Name-to-name is the correct mapping; the two enums' raw values differ.
    private static func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static func recognizeText(in cgImage: CGImage,
                                      orientation: CGImagePropertyOrientation = .up) async -> [VNRecognizedTextObservation] {
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

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
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
        // The first alternative is grouped thousands — "655,000", "1,150,000",
        // "4,640,000" on an Indonesian receipt, optionally with cents. Without
        // it, `\d+[,.]\d{2}` grabbed "655,00" out of "655,000" and the European
        // decimal-comma rule turned that into 655.00.
        pattern: #"[\$£€¥]?\s*\d{1,3}(?:,\d{3})+(?:\.\d{2})?(?!\d)|[\$£€¥]\s*\d{1,}[,.]?\d{0,2}|\d{1,}[,.]\d{2}\s*[\$£€¥]?|\d{1,}[,.]\d{2}"#,
        options: .caseInsensitive
    )

    private static let subtotalPattern = try! NSRegularExpression(
        pattern: #"sub\s*total|net\s+total"#,
        options: .caseInsensitive
    )

    private static let currencySymbolPattern = try! NSRegularExpression(
        pattern: #"[\$£€¥]"#, options: []
    )

    /// Lines whose amount is NOT the bill total: the tax component ("Total
    /// includes GST of: $22.46", "Includes TAX: $2.82", "GST: $4.10"),
    /// savings/discount lines ("TOTAL SAVINGS $52.94"), change, rounding, tips.
    /// Note: "(GST incl.)" / "incl. GST" mark a tax-INCLUSIVE total and must
    /// NOT be excluded — the patterns below only match the tax-amount phrasings.
    private static let amountExclusionPattern = try! NSRegularExpression(
        pattern: #"includes?\s+(gst|tax|vat)|\b(gst|tax|vat)\s+includ|\b(gst|tax|vat)\s*(of\b|:)|\btva\b|\bht\b|hors\s+taxe|\bppn(bm)?\b|\bpph\b|\bdpp\b|\bsav(?:e|ed|es|ing|ings)\b|special|promotion|discount|\bchange\b|rounding|cash\s*out|\btip\b|reward|points|\brrp\b|\bwas\s|@\s*\$?\d|/kg\b|/ea\b|\beach\b|\bper\s+(kg|item|unit)\b"#,
        options: .caseInsensitive
    )

    /// High-confidence total labels (English + common French receipt forms:
    /// "MONTANT DU", "NET À PAYER", "TOTAL TTC").
    private static let strongTotalPattern = try! NSRegularExpression(
        pattern: #"total\s+amount|grand\s+total|amount\s+due|balance\s+due|total\s+due|amount\s+payable|total\s*\(|total\s*:|montant\s+d[uû]|net\s+[aà]\s+payer|[aà]\s+payer|total\s+ttc"#,
        options: .caseInsensitive
    )

    private static let genericTotalPattern = try! NSRegularExpression(
        pattern: #"(?<!\w)total(?!\w)"#,
        options: .caseInsensitive
    )

    /// Payment-confirmation lines usually restate the exact total.
    private static let paymentPattern = try! NSRegularExpression(
        pattern: #"eftpos|visa|mastercard|amex|debit|credit\s+card|tendered|paid\b|payment"#,
        options: .caseInsensitive
    )

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Exclusion is a property of the printed LINE, not the block. Vision splits
    /// a row into a left label and a right-aligned amount, so "Specials" and
    /// "$14.90" arrive as separate blocks — excluding only the label left the
    /// amount free to win a fallback. An amount block therefore inherits the
    /// exclusion of any block sharing its line.
    private static func isExcluded(_ block: TextBlock, in blocks: [TextBlock]) -> Bool {
        if matches(amountExclusionPattern, block.text) { return true }
        return blocks.contains { other in
            (other.text != block.text || other.boundingBox != block.boundingBox)
                && sameLine(other.boundingBox, block.boundingBox)
                && matches(amountExclusionPattern, other.text)
        }
    }

    /// Skew-tolerant same-line test: blocks share a line when their vertical
    /// extents overlap by at least half the shorter block's height. Tilted
    /// receipts still pass (same printed line overlaps substantially), but
    /// adjacent rows never do — padding-based tests bridged a "Total" column
    /// header to the first item row below it and stole its amount.
    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap > 0 else { return false }
        return overlap >= min(a.height, b.height) * 0.5
    }

    /// Strict "these two blocks are on the same *printed* line" test, for
    /// deciding whether a candidate merchant is really half of a label-value
    /// pair.
    ///
    /// `sameLine` divides by the *shorter* box, so a small block only has to
    /// put half of itself inside a tall one to count. That's right for amounts
    /// (a label and its right-aligned figure often differ in height) but wrong
    /// here: a store name is printed large at the top with small print beneath
    /// it, so on any receipt photographed at a slight angle the tagline or
    /// address drifts into the wordmark's vertical band. The address then
    /// "parses an amount" (street and phone numbers) and the real merchant is
    /// discarded — which is exactly how a Woolworths receipt came back with a
    /// blank merchant while the synthetic test, whose header sits alone with
    /// nothing near it, passed.
    ///
    /// A genuine label-value pair is same-size text, side by side.
    private static func sharesPrintedLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap > 0 else { return false }
        // Most of the taller box must be involved, not just the shorter one.
        guard overlap >= max(a.height, b.height) * 0.6 else { return false }
        // Same font-size class — a header and body text are not one line.
        let ratio = max(a.height, b.height) / max(min(a.height, b.height), 0.0001)
        guard ratio <= 2.0 else { return false }
        // Side by side, not stacked: a label and its value don't overlap
        // horizontally.
        return a.maxX <= b.minX || b.maxX <= a.minX
    }

    /// Nearest amount in a block sharing a line with the keyword block.
    private static func findAmountOnSameLine(as keywordBlock: TextBlock, in blocks: [TextBlock]) -> Double? {
        var candidates: [(Double, CGFloat)] = [] // (amount, horizontal distance)
        for block in blocks where block.text != keywordBlock.text || block.boundingBox != keywordBlock.boundingBox {
            guard sameLine(block.boundingBox, keywordBlock.boundingBox) else { continue }
            // The paired block must not itself be an excluded line.
            guard !matches(amountExclusionPattern, block.text) else { continue }
            if let value = parseAmount(from: block.text), value > 0 {
                let dist = abs(block.boundingBox.midX - keywordBlock.boundingBox.midX)
                candidates.append((value, dist))
            }
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    /// Scored extraction: every plausible (line, amount) pair earns a score from
    /// its label, position, and magnitude; the best-scored candidate wins. This
    /// replaces first-match tiers, which happily returned "TOTAL SAVINGS" or
    /// "Total includes GST of:" lines because they contain the word "total".
    private static func extractAmount(from blocks: [TextBlock]) -> Double? {
        struct Candidate {
            let value: Double
            var score: Int
        }

        // Frequency of each amount (in cents) across non-excluded blocks, plus
        // the receipt maximum. A value that appears more than once — the total
        // restated on the card/payment line — is far more trustworthy than a
        // one-off large misread.
        var freq: [Int: Int] = [:]
        var maxAmount: Double = 0
        for block in blocks where !isExcluded(block, in: blocks) {
            if let v = parseAmount(from: block.text), v > 0 {
                freq[Int((v * 100).rounded()), default: 0] += 1
                if v > maxAmount { maxAmount = v }
            }
        }
        func repeats(_ v: Double) -> Bool { (freq[Int((v * 100).rounded())] ?? 0) >= 2 }

        var candidates: [Candidate] = []
        var subtotalFallback: Double?

        for block in blocks {
            let text = block.text

            // Tax/savings/discount/change/rate lines never nominate their amount.
            if isExcluded(block, in: blocks) { continue }

            let isSubtotal = matches(subtotalPattern, text)
            let isStrongTotal = !isSubtotal && matches(strongTotalPattern, text)
            let isGenericTotal = !isSubtotal && !isStrongTotal && matches(genericTotalPattern, text)
            let isPayment = matches(paymentPattern, text)

            guard isStrongTotal || isGenericTotal || isPayment || isSubtotal else { continue }

            // Amount inline in the same block, else in a block sharing the line.
            var value = parseAmount(from: text)
            var inline = true
            if value == nil || value == 0 {
                value = findAmountOnSameLine(as: block, in: blocks)
                inline = false
            }
            guard let amount = value, amount > 0 else { continue }

            if isSubtotal {
                subtotalFallback = subtotalFallback ?? amount
                continue
            }

            var score = 0
            if isStrongTotal { score += 100 }
            else if isGenericTotal { score += 80 }
            if isPayment { score += 45 }
            if repeats(amount) { score += 40 }          // cross-confirmed
            if amount == maxAmount { score += 12 }
            if block.boundingBox.origin.y < 0.5 { score += 10 } // lower half
            if inline { score += 5 }

            candidates.append(Candidate(value: amount, score: score))
        }

        if let best = candidates.max(by: { ($0.score, $0.value) < ($1.score, $1.value) }),
           best.score >= 45 {
            return best.value
        }

        // No confident labelled total — e.g. a curled/shadowed receipt where the
        // label and its amount didn't pair. Prefer a cross-confirmed amount (a
        // real total is restated on the card line; a misread is not).
        let repeatedVals = freq.filter { $0.value >= 2 }.keys.map { Double($0) / 100 }

        if let subtotal = subtotalFallback {
            // A total is always >= the subtotal. This floor rejects item-name
            // coincidences like "15 Wicked Wings $10" (value 10 appears in both
            // the name and the price) that would otherwise look cross-confirmed.
            if let best = repeatedVals.filter({ $0 >= subtotal - 0.01 }).max() {
                return best
            }
            // No trustworthy total found — the subtotal is far closer to the true
            // total than any stray item amount.
            return subtotal
        }

        if let best = repeatedVals.max() {
            return best
        }

        // Fallbacks: largest currency-marked amount, then the largest amount in
        // the bottom half.

        var currencyAmounts: [Double] = []
        for block in blocks where !isExcluded(block, in: blocks) {
            if matches(currencySymbolPattern, block.text),
               let value = parseAmount(from: block.text), value > 0 {
                currencyAmounts.append(value)
            }
        }
        if let best = currencyAmounts.max() { return best }

        var bottomAmounts: [Double] = []
        for block in blocks where block.boundingBox.origin.y < 0.5 && !isExcluded(block, in: blocks) {
            if let value = parseAmount(from: block.text), value > 0 {
                bottomAmounts.append(value)
            }
        }
        return bottomAmounts.max()
    }

    // MARK: - Currency Detection

    /// Explicit ISO codes and unambiguous symbols only — a bare "$" could be
    /// AUD/USD/NZD/CAD, so it never overrides the user's default currency.
    private static let currencyCodePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Z])(AUD|USD|EUR|GBP|NZD|CAD|JPY|CHF|SGD|HKD|CNY|INR|IDR|THB|MYR|PHP|VND)(?![A-Z])"#,
        options: []
    )

    private static func detectCurrency(in blocks: [TextBlock]) -> String? {
        var codeVotes: [String: Int] = [:]
        var symbolVotes: [String: Int] = [:]

        for block in blocks {
            let text = block.text
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in currencyCodePattern.matches(in: text, range: nsRange) {
                if let r = Range(match.range, in: text) {
                    codeVotes[String(text[r]), default: 0] += 1
                }
            }
            if text.contains("US$") { codeVotes["USD", default: 0] += 1 }
            if text.contains("A$")  { codeVotes["AUD", default: 0] += 1 }
            if text.contains("NZ$") { codeVotes["NZD", default: 0] += 1 }
            if text.contains("C$")  { codeVotes["CAD", default: 0] += 1 }
            // A currency symbol only means something next to a number. A stray
            // glyph — a stylised logo misread as "€" — used to outvote the whole
            // receipt and set the expense to euros on an Indonesian docket.
            guard text.contains(where: \.isNumber) else { continue }
            if text.contains("€") { symbolVotes["EUR", default: 0] += 1 }
            if text.contains("£") { symbolVotes["GBP", default: 0] += 1 }
            if text.contains("¥") { symbolVotes["JPY", default: 0] += 1 }
            if text.contains("₹") { symbolVotes["INR", default: 0] += 1 }
        }

        // An explicit code wins; otherwise an unambiguous symbol.
        if let best = codeVotes.max(by: { $0.value < $1.value }) { return best.key }
        if let best = symbolVotes.max(by: { $0.value < $1.value }) { return best.key }

        // Last resort: the receipt names where it was issued. Shops print their
        // country or state in the letterhead far more reliably than they print
        // a currency code, and a place name is unambiguous in a way a bare "$"
        // never is. Only reached when nothing above voted, so an explicit
        // marker always beats it.
        return currencyFromPlaceName(in: blocks)
    }

    /// Place names that pin a currency, matched whole-word and case-insensitively.
    /// Deliberately short: countries and the few regions and cities that appear
    /// on receipts without their country ("Bali", "Hong Kong"). Ambiguous names
    /// are omitted — plenty of places share a name with somewhere else.
    /// An array, not a dictionary — dictionary iteration order is unspecified, so
    /// a receipt naming two places would resolve to a different currency run to
    /// run. Most specific first: a country beats a city inside it.
    private static let placeCurrencies: [(place: String, code: String)] = [
        ("indonesia", "IDR"), ("new zealand", "NZD"), ("united kingdom", "GBP"),
        ("united states", "USD"), ("hong kong", "HKD"), ("switzerland", "CHF"),
        ("philippines", "PHP"), ("singapore", "SGD"), ("australia", "AUD"),
        ("netherlands", "EUR"), ("malaysia", "MYR"), ("thailand", "THB"),
        ("portugal", "EUR"), ("scotland", "GBP"), ("germany", "EUR"),
        ("vietnam", "VND"), ("england", "GBP"), ("ireland", "EUR"),
        ("jakarta", "IDR"), ("france", "EUR"), ("greece", "EUR"),
        ("canada", "CAD"), ("canggu", "IDR"), ("china", "CNY"), ("india", "INR"),
        ("italy", "EUR"), ("japan", "JPY"), ("spain", "EUR"), ("wales", "GBP"),
        ("bali", "IDR"), ("usa", "USD")
    ]

    /// Compiled once. Word-boundary anchored so "chinatown" doesn't vote CNY and
    /// "usain" doesn't vote USD.
    private static let placePatterns: [(regex: NSRegularExpression, code: String)] =
        placeCurrencies.compactMap { entry in
            let pattern = #"(?<![a-z])"# + NSRegularExpression.escapedPattern(for: entry.place) + #"(?![a-z])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, entry.code)
        }

    private static func currencyFromPlaceName(in blocks: [TextBlock]) -> String? {
        let haystack = blocks.map { $0.text.lowercased() }.joined(separator: " ")
        return placePatterns.first { matches($0.regex, haystack) }?.code
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

        // A receipt date can't be in the future — thermal-print digit misreads
        // (2026 → 2028) would otherwise sail through. Allow a 2-day grace for
        // timezone slop, and skip implausibly old reads too.
        let latestAllowed = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let earliestAllowed = Calendar.current.date(from: DateComponents(year: 2015, month: 1, day: 1)) ?? .distantPast

        for block in sortedByPosition {
            if let date = parseDateFromBlock(block.text),
               date <= latestAllowed, date >= earliestAllowed {
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

    /// `merchantNoisePhrases` compiled with word boundaries, so a phrase only
    /// matches as a whole word. Boundaries are applied only at ends that are
    /// alphanumeric — `\b` before "." or after ":" would never match, which
    /// would silently disable the "www.", ".com" and "tel:" entries.
    private static let merchantNoisePatterns: [NSRegularExpression] = {
        merchantNoisePhrases.compactMap { phrase in
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            let leading  = phrase.first.map  { $0.isLetter || $0.isNumber } ?? false ? #"\b"# : ""
            let trailing = phrase.last.map   { $0.isLetter || $0.isNumber } ?? false ? #"\b"# : ""
            return try? NSRegularExpression(pattern: leading + escaped + trailing,
                                            options: .caseInsensitive)
        }
    }()

    /// Staff/role/contact labels: a block that IS one of these, or that shares a
    /// line with one, is a label-value pair ("Sale Staff : Melissa") — never a
    /// merchant name.
    private static let labelLinePattern = try! NSRegularExpression(
        pattern: #"sale\s*staff|\bstaff\b|cashier|server\b|served\s+by|operator|\bclerk\b|attendant|sold\s+by|your\s+(server|cashier)|customer|member\b|contact|ship\s+to|bill\s+to"#,
        options: .caseInsensitive
    )

    /// Marketing and boilerplate that prints at the foot of a docket. Never a
    /// merchant name, wherever it lands in the block order — this is the
    /// backstop for "AU-PROMO LEBARAN UP TO", which won on a Deus receipt even
    /// after the masthead was searched first, because the masthead yielded no
    /// candidate at all and the fallback scanned the whole receipt.
    private static let merchantRejectPattern = try! NSRegularExpression(
        // Marketing/footer boilerplate, plus receipt-structural labels. A crisp
        // "TOTAL (Inc GST)" in the middle of a Liquorland docket beat the
        // letter-spaced wordmark at the top, which OCR'd at lower confidence —
        // so a total line must never be eligible as a merchant. `total\s*[(:]`
        // catches "TOTAL (Inc GST)" / "TOTAL:" without rejecting a real store
        // like "Total Tools".
        pattern: #"\bpromo\w*|\bdiscount\w*|\bvoucher\b|\bcoupon\b|\bterms\b|\bconditions\b|\brefunds?\b|\bexchange\b|thank\s*you|\brewards?\b|\bsurvey\b|\bwarranty\b|\bpoints\b|\bvalid\b|total\s*[(:]|\bsub\s*total\b|tax\s+invoice|\bgst\b|\bdescription\b|paid\s+by|\beftpos\b|change\s+due|\bpurchase\b|credit\s+account|\bapproved\b"#,
        options: .caseInsensitive
    )

    /// Domain/email-looking text ("account.monos.au") — a URL is where the
    /// receipt came from, not who the merchant is.
    private static let domainLikePattern = try! NSRegularExpression(
        // The `@` half requires an email's shape. A bare `@` used to disqualify a
        // candidate outright, and a logo glyph beside a wordmark — the swirl on a
        // Woolworths receipt, say — can OCR as one.
        pattern: #"[a-z0-9][.][a-z]{2,}|[a-z0-9]@[a-z0-9]"#,
        options: .caseInsensitive
    )

    /// Registered-business suffixes: a line like "Monos Travel Ltd." is the
    /// legal merchant name and beats positional guessing.
    private static let businessSuffixPattern = try! NSRegularExpression(
        pattern: #"\b(pty|ltd|inc|llc|plc|gmbh|co\.|limited|corporation)\b"#,
        options: .caseInsensitive
    )

    /// Punctuation and stray glyphs that cling to the edges of a merchant name —
    /// divider dashes, trailing colons, and a logo misread as `@` or `©`.
    private static let merchantEdgeJunk = CharacterSet(charactersIn: ".,;:-=_*~•·@©®™|/\\ ")

    /// The wordmark, if the photo caught it. A store prints its own name far
    /// larger than anything else on the receipt, so the tallest text in the top
    /// third is the most direct signal available — no filters, no positional
    /// guessing.
    ///
    /// Nothing to find when the header is cropped out of frame or the receipt is
    /// uniform monospace, which is common for supermarket dockets; callers fall
    /// through to the filter passes below.
    private static func largestHeaderText(in blocks: [TextBlock]) -> String? {
        let heights = blocks.map(\.boundingBox.height).sorted()
        guard !heights.isEmpty else { return nil }
        let median = heights[heights.count / 2]
        guard median > 0 else { return nil }

        // Top of the *receipt*, not the image. midY >= 0.6 (image-relative) only
        // worked when the receipt filled the frame; a docket floating mid-photo
        // with table around it put the wordmark below 0.6, so this returned nil
        // and the merchant fell through to junk ("chip" off a Cherry Beans
        // docket, the promo banner off a Deus one). topOfReceipt is the same
        // receipt-relative region the masthead fallback already uses.
        return topOfReceipt(blocks, fraction: 0.4)
            .filter { $0.boundingBox.height >= median * 1.6 && $0.confidence >= 0.3 }
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
            .lazy
            .map { $0.text.trimmingCharacters(in: Self.merchantEdgeJunk) }
            .first { text in
                !text.contains(where: \.isNumber)
                    && text.contains(where: \.isLetter)
                    && !matches(domainLikePattern, text)
                    && !matches(labelLinePattern, text)
                    && !matches(merchantRejectPattern, text)
                    && text.count >= 3 && text.count <= 45
            }
    }

    /// The merchant and its alternates, in priority order, deduped. `.first` is
    /// the same winner the single-value passes produced before; the rest are the
    /// gate-passing lines that ranked lower — clean names only, never the
    /// rejected total/GST junk — for the "Doesn't look right?" picker.
    /// A street or shopping-centre line ends in one of these ("KELLYVILLE GROVE",
    /// "2A HECTOR COURT", "Severn Vale Road"). Such a phrase recurs in a receipt's
    /// header and footer by nature, so it must not win the recurring-phrase boost —
    /// that crowned the centre "KELLYVILLE GROVE" over the (OCR-garbled) shop name.
    /// Suffix only, never a suburb-token test: a shop is often named after its town
    /// ("Berry General Store" in Berry), so a place-name match would reject real names.
    private static let streetCentreSuffixPattern = try! NSRegularExpression(
        pattern: #"\b(GROVE|COURT|CRESCENT|ROAD|RD|STREET|AVENUE|PLACE|PLAZA|CENTRE|CENTER|MALL|ARCADE|LANE|WAY|DRIVE|PARADE|HIGHWAY|BOULEVARD|TERRACE|CLOSE|SQUARE)\b"#,
        options: [.caseInsensitive])

    /// A "<suburb> STATE postcode" address line — "KELLYVILLE NSW 2154".
    private static let auStatePostcodePattern = try! NSRegularExpression(
        pattern: #"\b(NSW|VIC|QLD|SA|WA|TAS|ACT|NT)\b\s+\d{4}\b"#, options: [.caseInsensitive])

    /// Suburb names the receipt prints in a "<suburb> STATE postcode" line — the
    /// word right before the state ("KELLYVILLE NSW 2154" → "kellyville").
    private static func suburbTokens(in blocks: [TextBlock]) -> Set<String> {
        var out = Set<String>()
        for b in blocks {
            let t = b.text
            guard let m = auStatePostcodePattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let mr = Range(m.range, in: t) else { continue }
            if let suburb = t[..<mr.lowerBound].split(whereSeparator: { !$0.isLetter }).last,
               suburb.count >= 3 {
                out.insert(suburb.lowercased())
            }
        }
        return out
    }

    /// Recover the business name from the footer return-address, where a stylised
    /// or OCR-garbled header can't be read: a clean "<Business Name> <Suburb>" line
    /// ("Maw Maw Kellyville") with its trailing suburb stripped → "Maw Maw". Only
    /// fires when the receipt actually names a suburb (a "<suburb> STATE postcode"
    /// line), and is ranked *below* the header wordmark passes, so it only wins
    /// when the header yielded nothing usable.
    private static func footerBusinessName(from blocks: [TextBlock]) -> String? {
        let suburbs = suburbTokens(in: blocks)
        guard !suburbs.isEmpty else { return nil }
        var best: String?
        for block in blocks {
            let raw = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.contains(where: { $0.isNumber }),
                  !matches(labelLinePattern, raw),
                  !matches(merchantRejectPattern, raw),
                  !matches(domainLikePattern, raw) else { continue }
            let words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 2, let last = words.last,
                  suburbs.contains(last.lowercased()) else { continue }
            let name = words.dropLast().joined(separator: " ")
                .trimmingCharacters(in: Self.merchantEdgeJunk)
            guard name.count >= 3, name.split(whereSeparator: \.isWhitespace).count <= 5 else { continue }
            if best == nil || name.count > best!.count { best = name }
        }
        return best
    }

    private static func rankedMerchants(from blocks: [TextBlock]) -> [String] {
        let ordered = readingOrder(blocks)
        let masthead = topOfReceipt(ordered, fraction: 0.4)

        var ranked: [String] = []

        // 0. A wordmark stacked across the top lines ("BERRY" / "GENERAL STORE"
        //    → "BERRY GENERAL STORE"). Reconstructed so the full name wins over
        //    a single-line fragment.
        if let stacked = stackedWordmark(in: masthead) { ranked.append(stacked) }

        // 1. A clearly-largest wordmark at the top.
        if let wordmark = largestHeaderText(in: blocks) { ranked.append(wordmark) }

        // 1b. Header unreadable? Recover the name from the footer return-address
        //     ("Maw Maw Kellyville" → "Maw Maw"). Ranked here, below the wordmark
        //     passes, so a clear header always wins and this only fills the gap.
        if let footerName = footerBusinessName(from: ordered) { ranked.append(footerName) }

        // 2. A registered-business name (Pty/Ltd/…) anywhere on the receipt.
        //    The reject/label gates run here too: "TOTAL (Inc GST)" matches the
        //    business-suffix pattern on "Inc" (Including, not Incorporated), and
        //    without the gate this pass handed it back as the merchant.
        for block in ordered where block.confidence >= 0.4 {
            let raw = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matches(businessSuffixPattern, raw),
                  !raw.contains(where: { $0.isNumber }),
                  !matches(domainLikePattern, raw),
                  !matches(merchantRejectPattern, raw),
                  !matches(labelLinePattern, raw),
                  raw.count >= 4, raw.count <= 45 else { continue }
            let cleaned = raw.trimmingCharacters(in: Self.merchantEdgeJunk)
            if cleaned.count >= 3 { ranked.append(cleaned) }
        }

        // 3. An ALL-CAPS word at the top (LIQUORLAND, WOOLWORTHS) — a strong
        //    signal that survives low OCR confidence; runs the reject gates so
        //    TOTAL / GST / CARDHOLDER COPY (also caps) are filtered out.
        ranked += merchantCandidates(in: masthead, allBlocks: blocks, minConfidence: 0.3, requireAllCaps: true)

        // 4. The masthead, then the whole receipt, high confidence before low —
        //    same order the single-value passes used, so `.first` is unchanged.
        ranked += merchantCandidates(in: masthead, allBlocks: blocks, minConfidence: 0.75)
        ranked += merchantCandidates(in: masthead, allBlocks: blocks, minConfidence: 0.35)
        ranked += merchantCandidates(in: ordered, allBlocks: blocks, minConfidence: 0.75)
        ranked += merchantCandidates(in: ordered, allBlocks: blocks, minConfidence: 0.35)

        // Dedupe case-insensitively, keeping priority order.
        var seen = Set<String>()
        let deduped = ranked.filter { seen.insert($0.lowercased()).inserted }

        // A multi-word name printed more than once is the merchant. A store
        // prints its name as a wordmark up top and again in the letterhead
        // ("BERRY GENERAL STORE" then "The Berry General Store"), so a
        // two-or-more-word phrase appearing in two or more blocks is a strong
        // signal. This needs no list of place names: a lone "NSW" is one word,
        // so it never qualifies.
        func appearances(_ s: String) -> Int {
            let needle = s.lowercased()
            return blocks.filter { $0.text.lowercased().contains(needle) }.count
        }
        let recurringPhrase = deduped
            .filter { $0.split(whereSeparator: \.isWhitespace).count >= 2
                      && appearances($0) >= 2
                      && !matches(streetCentreSuffixPattern, $0) }
            .max { $0.count < $1.count }
        if let anchor = recurringPhrase {
            // Return the fullest form of that name, e.g. the letterhead
            // "The Berry General Store" over the wordmark fragment "GENERAL STORE".
            let best = deduped.filter { $0.lowercased().contains(anchor.lowercased()) }
                .max { $0.count < $1.count } ?? anchor
            return [best] + deduped.filter { $0.lowercased() != best.lowercased() }
        }
        return deduped
    }

    /// The top `fraction` of the receipt's own text extent — not the image's, so
    /// it holds however the receipt sits in frame.
    private static func topOfReceipt(_ blocks: [TextBlock], fraction: CGFloat) -> [TextBlock] {
        let mids = blocks.map(\.boundingBox.midY)
        guard let lowest = mids.min(), let highest = mids.max(), highest > lowest else { return blocks }
        let cutoff = highest - (highest - lowest) * fraction
        return blocks.filter { $0.boundingBox.midY >= cutoff }
    }

    #if DEBUG
    /// Ground truth for a misread receipt: exactly what Vision returned, and
    /// how it chose to split the lines.
    ///
    /// The Woolworths store line took three wrong fixes because each one guessed
    /// at that split — whether "WOOLWORTHS" and "1659" arrive as one block or
    /// two changes which filter rejects the merchant, and the guess is
    /// unfalsifiable without this. Filter Xcode's console by category `ocr`.
    private static func dumpBlocks(_ blocks: [TextBlock]) {
        Log.ocr.debug("---- \(blocks.count, privacy: .public) blocks (x, y, w, h, confidence) ----")
        for b in blocks.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            let r = b.boundingBox
            // Block text is receipt content — private (visible in DEBUG runs).
            Log.ocr.debug("\(String(format: "%.3f %.3f %.3f %.3f  %.2f", r.origin.x, r.origin.y, r.width, r.height, b.confidence), privacy: .public) |\(b.text, privacy: .private)|")
        }
    }
    #endif

    /// Blocks in reading order: printed lines top to bottom, blocks within a
    /// line left to right.
    ///
    /// Sorting on `y` alone leaves same-line blocks in arbitrary order, and a
    /// plain `x` tiebreak on exact `y` equality never fires — a hand-held photo
    /// is always slightly skewed, so "WOOLWORTHS" and "KELLYVILLE" on one
    /// printed line have different `y`. Grouping into lines first is what makes
    /// left-to-right actually hold, and receipts print the chain before the
    /// suburb.
    private static func readingOrder(_ blocks: [TextBlock]) -> [TextBlock] {
        var lines: [[TextBlock]] = []
        for block in blocks.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            if let i = lines.indices.last, let first = lines[i].first,
               sameLine(first.boundingBox, block.boundingBox) {
                lines[i].append(block)
            } else {
                lines.append([block])
            }
        }
        return lines.flatMap { $0.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x } }
    }

    /// A price prints with cents or a currency symbol. A bare integer sitting
    /// beside a name is a store number ("WOOLWORTHS  1659"), a quantity or a
    /// terminal ID — not an amount. `parseAmount` happily reads `1659` as
    /// 1659.0, which made the merchant filter treat the store line as a
    /// label-value pair and discard the chain name.
    private static func looksLikeMoney(_ text: String) -> Bool {
        guard parseAmount(from: text) != nil else { return false }
        return text.contains(where: { "$£€¥".contains($0) })
            || matches(centsPattern, text)
    }

    private static let centsPattern = try! NSRegularExpression(pattern: #"\d[.,]\d{2}(?!\d)"#)

    /// "WOOLWORTHS 1659" → "WOOLWORTHS". Only a single trailing all-digit token
    /// is dropped, and only when nothing else in the line has a digit, so
    /// addresses ("2 Hector Court", "1659 Kellyville Grove PH: 02 9624 9402")
    /// and ABN lines keep their digits and stay disqualified.
    private static let auStates: Set<String> = ["NSW", "VIC", "QLD", "SA", "WA", "TAS", "ACT", "NT"]

    private static func dropTrailingStoreNumber(_ text: String) -> String {
        let tokens = text.split(separator: " ")
        guard tokens.count >= 2,
              let last = tokens.last, last.allSatisfy(\.isNumber),
              !tokens.dropLast().contains(where: { $0.contains(where: \.isNumber) })
        else { return text }
        // A 4-digit number after a state abbreviation is a postcode, not a store
        // number ("KELLYVILLE NSW 2154"). Keep it so the address line stays
        // disqualified as a merchant (its digit keeps it out), instead of becoming
        // "KELLYVILLE NSW" and winning via the recurring header/footer address.
        if last.count == 4,
           auStates.contains(tokens[tokens.count - 2].uppercased()) {
            return text
        }
        return tokens.dropLast().joined(separator: " ")
    }

    /// A block whose letters are all uppercase (LIQUORLAND, WOOLWORTHS). ≥3
    /// letters so "P" or "Rd" don't count.
    private static func isAllCaps(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 3 && !letters.contains(where: \.isLowercase)
    }

    /// Reconstruct a wordmark printed across stacked lines at the very top —
    /// "BERRY" then "GENERAL STORE" → "BERRY GENERAL STORE". Joins the leading
    /// run of all-caps, digit-free, gate-passing lines (max 3 lines / 6 words),
    /// stopping at the first line that breaks the run. Returns nil if the run is
    /// a single line (that path is already covered elsewhere).
    private static func stackedWordmark(in masthead: [TextBlock]) -> String? {
        var parts: [String] = []
        for block in readingOrder(masthead) {
            let raw = block.text.trimmingCharacters(in: Self.merchantEdgeJunk)
            guard isAllCaps(raw),
                  !raw.contains(where: \.isNumber),
                  // A wordmark fragment is short ("GENERAL STORE"); a 4+-word
                  // all-caps line is a slogan ("SAY NO TO PLASTIC BAGS") and must
                  // not be glued onto the name.
                  raw.split(whereSeparator: \.isWhitespace).count <= 3,
                  !matches(merchantRejectPattern, raw),
                  !matches(labelLinePattern, raw),
                  !matches(domainLikePattern, raw)
            else { break }
            parts.append(raw)
            if parts.count >= 3 { break }
        }
        let joined = parts.joined(separator: " ")
        let wordCount = joined.split(whereSeparator: \.isWhitespace).count
        guard parts.count >= 2, wordCount >= 2, wordCount <= 6, joined.count <= 45 else { return nil }
        return joined
    }


    private static func firstMerchantCandidate(in blocks: [TextBlock], allBlocks: [TextBlock],
                                               minConfidence: Float, requireAllCaps: Bool = false) -> String? {
        merchantCandidates(in: blocks, allBlocks: allBlocks,
                           minConfidence: minConfidence, requireAllCaps: requireAllCaps).first
    }

    /// Every gate-passing candidate in `blocks`, in reading order. `firstMerchant
    /// Candidate` is `.first`; the rest feed the "Doesn't look right?" alternates.
    private static func merchantCandidates(in blocks: [TextBlock], allBlocks: [TextBlock],
                                           minConfidence: Float, requireAllCaps: Bool = false) -> [String] {
        var out: [String] = []
        for block in blocks {
            guard block.confidence >= minConfidence else { continue }

            // Digits usually mean amount, ABN, street number or item line — but
            // chains print the store number after the name ("WOOLWORTHS 1659",
            // "KMART 4021"), so drop a single *trailing* numeric token first.
            // Leading numbers stay disqualifying, which is what separates a
            // store line from an address ("2 Hector Court").
            let raw = dropTrailingStoreNumber(block.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard raw.count >= 2 else { continue }
            if raw.contains(where: { $0.isNumber }) { continue }

            // Never use a label-value line ("Sale Staff: Melissa") — whether the
            // label is in this block or in a sibling block on the same line.
            if matches(labelLinePattern, raw) { continue }
            if matches(merchantRejectPattern, raw) { continue }
            let pairedWithLabelOrAmount = allBlocks.contains { other in
                (other.text != block.text || other.boundingBox != block.boundingBox)
                    && sharesPrintedLine(other.boundingBox, block.boundingBox)
                    && (matches(labelLinePattern, other.text) || looksLikeMoney(other.text))
            }
            if pairedWithLabelOrAmount { continue }

            // URLs and emails are not merchant names.
            if matches(domainLikePattern, raw) { continue }

            // Strip noise phrases as whole words. A plain substring replace ate
            // any merchant whose name happened to contain one: "pos" turned
            // "Post Office" into " t Office", "cash" turned "Cashmere Boutique"
            // into "mere Boutique", "time" turned "Timezone" into "zone".
            var text = raw
            for pattern in merchantNoisePatterns {
                text = pattern.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
            text = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: Self.merchantEdgeJunk)

            guard text.count >= 2, text.count <= 45 else { continue }
            if text.contains(where: { $0.isNumber }) { continue }
            // Reject divider/rule lines ("====", "----", "****") — a merchant name has letters.
            guard text.contains(where: { $0.isLetter }) else { continue }

            let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
            guard wordCount <= 6 else { continue }

            if requireAllCaps && !isAllCaps(text) { continue }

            out.append(text)
        }

        return out
    }

    // MARK: - Notes Extraction

    /// A line that carries an amount but is NOT a purchased item — totals,
    /// tax, surcharges, payment lines, headers. Items are what's left.
    private static let timePattern = try! NSRegularExpression(pattern: #"\d{1,2}:\d{2}"#)

    private static let nonItemLinePattern = try! NSRegularExpression(
        pattern: #"sub\s*total|\btotal\b|\btax\b|\bgst\b|surcharge|\bchange\b|\bbalance\b|rounding|\btip\b|amount\s+due|\bpaid\b|\beftpos\b|\bvisa\b|\bmaster|\bamex\b|\bcash\b|\bcard\b|\beach\b|\bqty\b|\bsubtotal\b|discount|\bsaving"#,
        options: .caseInsensitive
    )

    /// A best-guess note describing the transaction — what was bought — shown by
    /// default and overwritten the moment the user types their own. Prefers the
    /// item line(s); falls back to a service descriptor ("Eat in"). The merchant
    /// is deliberately omitted: it has its own field.
    private static func extractNotes(from blocks: [TextBlock], merchant: String?) -> String? {
        // Item lines: a text block sharing a printed line with a real amount,
        // that isn't itself a total/tax/surcharge/payment line.
        var items: [String] = []
        var seen = Set<String>()
        for block in readingOrder(blocks) {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 3, text.count <= 40,
                  text.contains(where: \.isLetter),
                  parseAmount(from: text) == nil,                 // the description, not the price
                  !matches(nonItemLinePattern, text),
                  !matches(labelLinePattern, text),
                  !matches(datePattern, text),                    // "1 Aug 2026" is not an item
                  !matches(writtenDatePattern, text),
                  !matches(timePattern, text),
                  findAmountOnSameLine(as: block, in: blocks) != nil  // priced → a line item
            else { continue }
            // Strip a trailing "x 2" quantity into a compact "×2".
            let cleaned = text
                .replacingOccurrences(of: #"\s*[x×]\s*(\d+)\s*$"#, with: " ×$1",
                                      options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if seen.insert(cleaned.lowercased()).inserted { items.append(cleaned) }
        }

        if !items.isEmpty {
            let note: String
            if items.count == 1 {
                note = items[0]
            } else {
                note = "\(items[0]) +\(items.count - 1) more"
            }
            return note.count <= 60 ? note : String(note.prefix(57)) + "…"
        }

        // Fallback: a service descriptor (Eat in / Takeaway / Dine in).
        for block in blocks where block.confidence >= 0.6 {
            let lower = block.text.lowercased()
            for kw in noteDescriptorKeywords where lower.contains(kw) {
                return kw.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
            }
        }
        return nil
    }

    private static let noteDescriptorKeywords = [
        "eat in", "eat-in", "sit in", "dine in", "dine-in",
        "takeout", "take away", "take-away", "takeaway",
        "online order", "delivery", "pickup", "pick up", "drive thru", "to go"
    ]
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
