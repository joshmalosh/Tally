import Vision
import UIKit
import CoreImage

struct ReceiptOCRResult {
    var amount: Double?
    var merchant: String?
    var date: Date?
    var notes: String?
}

enum ReceiptOCRService {

    // MARK: - Public entry point

    static func extract(from image: UIImage) async -> ReceiptOCRResult {
        let prepared = prepareImage(image)
        guard let cgImage = prepared.cgImage else { return ReceiptOCRResult() }

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

    /// Extract raw text for bulk import
    static func extractFullText(from image: UIImage) async -> String {
        let prepared = prepareImage(image)
        guard let cgImage = prepared.cgImage else { return "" }
        let observations = await recognizeText(in: cgImage)
        return observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Image preparation

    /// Normalise orientation and straighten rotated receipts before OCR.
    private static func prepareImage(_ image: UIImage) -> UIImage {
        // Fix UIImage orientation metadata first
        let oriented = fixOrientation(image)

        // Detect if image is landscape (wider than tall) and rotate 90 degrees
        // Receipts are always portrait — if the image is landscape, the receipt was photographed sideways
        guard let cgImage = oriented.cgImage else { return oriented }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        if width > height {
            // Rotate 90 degrees clockwise
            let size = CGSize(width: height, height: width)
            UIGraphicsBeginImageContextWithOptions(size, false, oriented.scale)
            let context = UIGraphicsGetCurrentContext()!
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .pi / 2)
            oriented.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            let rotated = UIGraphicsGetImageFromCurrentImageContext() ?? oriented
            UIGraphicsEndImageContext()
            return rotated
        }

        return oriented
    }

    private static func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
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
            request.recognitionLanguages = ["en-AU", "en-US", "en-GB"]

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
        pattern: #"[\$£€¥]\s*\d{1,6}[,.]?\d{0,2}|\d{1,6}[,.]\d{2}\s*[\$£€¥]?"#,
        options: .caseInsensitive
    )

    /// Keywords that strongly indicate the final payable total — ordered by priority.
    /// "subtotal" and "sub total" are deliberately excluded — they indicate pre-tax amounts.
    private static let strongTotalKeywords = [
        "grand total", "total due", "total payable", "amount due",
        "amount payable", "you pay", "balance due", "total amount due"
    ]
    private static let weakTotalKeywords = ["total"]
    private static let subtotalKeywords = ["subtotal", "sub total", "sub-total", "net total"]

    private static func extractAmount(from blocks: [TextBlock]) -> Double? {
        // Pass 1: Strong total keywords — look for keyword + amount on same line or adjacent line
        for keyword in strongTotalKeywords {
            if let value = findAmountNearKeyword(keyword, in: blocks) {
                return value
            }
        }

        // Pass 2: Weak "total" keyword, but only if it's NOT preceded by "sub"
        for block in blocks {
            let lower = block.text.lowercased()
            let isSubtotal = subtotalKeywords.contains { lower.contains($0) }
            if !isSubtotal && lower.contains("total") {
                if let value = parseAmount(from: block.text), value > 0 {
                    return value
                }
                // Check adjacent block below (same-line split)
                if let value = findAmountOnSameLine(as: block, in: blocks) {
                    return value
                }
            }
        }

        // Pass 3: Fallback — largest dollar-formatted amount in bottom 40% of receipt
        let bottomBlocks = blocks.filter { $0.boundingBox.origin.y < 0.4 }
        let candidates = bottomBlocks.compactMap { block -> Double? in
            guard let val = parseAmount(from: block.text), val > 0 else { return nil }
            return val
        }
        return candidates.max()
    }

    private static func findAmountNearKeyword(_ keyword: String, in blocks: [TextBlock]) -> Double? {
        for block in blocks {
            let lower = block.text.lowercased()
            guard lower.contains(keyword) else { continue }

            // Amount on same text block
            if let value = parseAmount(from: block.text), value > 0 {
                return value
            }
            // Amount on same horizontal line (split across two blocks)
            if let value = findAmountOnSameLine(as: block, in: blocks) {
                return value
            }
        }
        return nil
    }

    private static func findAmountOnSameLine(as keyBlock: TextBlock, in blocks: [TextBlock]) -> Double? {
        let yTolerance: CGFloat = 0.02
        let keyY = keyBlock.boundingBox.midY
        let candidates = blocks
            .filter { abs($0.boundingBox.midY - keyY) < yTolerance && $0.text != keyBlock.text }
            .compactMap { block -> (Double, CGFloat)? in
                guard let val = parseAmount(from: block.text), val > 0 else { return nil }
                return (val, abs(block.boundingBox.midX - keyBlock.boundingBox.midX))
            }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private static func parseAmount(from text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = amountPattern.matches(in: text, options: [], range: range)
        var best: Double?
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            var s = String(text[matchRange])
            s = s.replacingOccurrences(of: "[$£€¥\\s]", with: "", options: .regularExpression)
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
            if let value = Double(s), value > 0 {
                if best == nil || value > best! { best = value }
            }
        }
        return best
    }

    // MARK: - Merchant Extraction

    /// Noise words that appear at the top of receipts but are NOT merchant names.
    /// These are whole-line or dominant-phrase patterns.
    private static let merchantNoiseLines: Set = [
        "tax invoice", "tax invoice receipt", "invoice", "receipt",
        "sales receipt", "official receipt",
        "abn", "acn", "gst", "gstin",
        "thank you", "thanks for shopping", "thanks for visiting",
        "welcome", "please retain", "please keep",
        "castlehill", "castle hill", // location suffixes for chain stores
        "wh", "store", "branch",
        "front end registers", "register",
        "sale", "transaction",
        "** tax invoice **", "* tax invoice *"
    ]

    private static let merchantNoisePatterns: [String] = [
        "^\\d+$",                          // pure number
        "^[*\\-=#+]{2,}",                 // decorative separators
        "\\b(abn|acn|gst)\\s+\\d",        // ABN/ACN/GST numbers
        "ph:\\s*\\(?\\d",                  // phone numbers
        "tel:\\s*\\(?\\d",
        "\\(?0[2-9]\\)?\\s*\\d{4}",       // Australian phone format
        "\\b\\d{2}/\\d{2}/\\d{4}\\b",     // dates
        "\\b\\d{4}-\\d{2}-\\d{2}\\b",
        "\\b(mon|tue|wed|thu|fri|sat|sun)\\b", // day names
        "www\\.",                           // URLs
        "\\.com|\\.com\\.au|\\.net",
        "@",                               // email addresses
        "r0[0-9]|r[0-9]{2}\\s",           // register IDs like R01
        "\\bp\\d{3,}\\b",                  // printer/POS codes
        "\\bc\\d{6,}\\b",                  // long numeric codes
    ]

    private static func isMerchantNoise(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Exact match against noise lines
        if merchantNoiseLines.contains(lower) { return true }
        // Substring match against noise lines (e.g. "** TAX INVOICE **")
        for noise in merchantNoiseLines {
            if lower.contains(noise) { return true }
        }
        // Regex patterns
        for pattern in merchantNoisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil { return true }
            }
        }
        return false
    }

    private static func extractMerchant(from blocks: [TextBlock]) -> String? {
        // Strategy: scan the top 15% of the receipt (high y values in Vision coordinates).
        // Prefer the LARGEST text block (by character width relative to bounding box width),
        // which is typically the brand/store name printed in large font at the very top.

        // First, get blocks in the top portion of the receipt
        let topBlocks = blocks
            .filter { $0.boundingBox.origin.y > 0.7 } // top 30% of receipt
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        // Try to find the widest/most prominent text block — merchant names are typically
        // printed larger and span more of the receipt width than address lines or noise
        var candidates: [(String, CGFloat)] = [] // (text, bounding box width)
        for block in topBlocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2, text.count <= 60 else { continue }
            guard block.confidence >= 0.5 else { continue }
            guard !isMerchantNoise(text) else { continue }

            // Skip if more than 40% digits
            let digits = text.filter(\.isNumber).count
            if text.count > 0 && Double(digits) / Double(text.count) > 0.4 { continue }

            candidates.append((text, block.boundingBox.width))
        }

        // Pick the widest candidate — large brand names span the full receipt width
        if let best = candidates.max(by: { $0.1 < $1.1 }) {
            return toTitleCase(best.0)
        }

        // Fallback: first non-noise block at the very top
        for block in topBlocks.prefix(8) {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2, text.count <= 60 else { continue }
            guard !isMerchantNoise(text) else { continue }
            let digits = text.filter(\.isNumber).count
            if text.count > 0 && Double(digits) / Double(text.count) > 0.4 { continue }
            return toTitleCase(text)
        }

        return nil
    }

    private static func toTitleCase(_ text: String) -> String {
        text.lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Date Extraction

    private static func extractDate(from blocks: [TextBlock]) -> Date? {
        for block in blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = parseNumericDate(text) { return date }
            if let date = parseWrittenDate(text) { return date }
        }
        return nil
    }

    private static func parseNumericDate(_ text: String) -> Date? {
        let separators: [Character] = ["/", "-", "."]
        for sep in separators {
            guard text.contains(sep) else { continue }
            let parts = text.split(separator: sep).map(String.init)
            guard parts.count == 3 else { continue }
            let nums = parts.compactMap { Int($0.prefix(4)) }
            guard nums.count == 3 else { continue }
            var a = nums[0], b = nums[1], c = nums[2]
            // Expand 2-digit year
            if c < 100 { c += 2000 }
            if a > 2000 {
                return makeDate(year: a, month: b, day: c)
            } else if a > 31 {
                return nil // invalid
            } else if a > 12 {
                return makeDate(year: c, month: b, day: a)
            } else if b > 12 {
                return makeDate(year: c, month: a, day: b)
            } else {
                // Ambiguous — DD/MM/YYYY is default for AU
                return makeDate(year: c, month: b, day: a)
            }
        }
        return nil
    }

    private static func parseWrittenDate(_ text: String) -> Date? {
        let formats = [
            "d MMM yyyy", "d MMMM yyyy", "dd MMM yyyy", "dd MMMM yyyy",
            "MMM d, yyyy", "MMMM d, yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return date
            }
        }
        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (2000...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = 12
        return Calendar.current.date(from: components)
    }

    // MARK: - Notes Extraction (Pro only)

    private static let noteDescriptorKeywords = [
        "takeout", "take away", "take-away", "online order", "dine in", "dine-in",
        "delivery", "pickup", "pick up", "drive thru", "drive-through",
        "to go", "to-go", "counter", "table"
    ]

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
                    if cleaned.count <= 30 && !cleaned.isEmpty {
                        descriptor = cleaned.prefix(1).uppercased() + cleaned.dropFirst().lowercased()
                        break
                    }
                }
            }
            if descriptor != nil { break }
        }

        guard let d = descriptor else { return nil }
        let note = "\(d) — \(merchant.prefix(40))"
        return note.count <= 60 ? note : String(note.prefix(57)) + "..."
    }
}

private struct TextBlock {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}
