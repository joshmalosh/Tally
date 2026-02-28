import Vision
import UIKit

struct ReceiptOCRResult {
    var amount: Double?
    var merchant: String?
}

enum ReceiptOCRService {

    static func extract(from image: UIImage) async -> ReceiptOCRResult {
        guard let cgImage = image.cgImage else { return ReceiptOCRResult() }

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

        return ReceiptOCRResult(amount: amount, merchant: merchant)
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

    private static let totalKeywords = [
        "total", "grand total", "amount due", "amount", "balance due",
        "subtotal", "sub total", "net total", "total due", "you pay",
        "total payable", "total amount", "sum", "total charge"
    ]

    private static let amountPattern = try! NSRegularExpression(
        pattern: #"[\$£€¥]\s*\d{1,}[,.]?\d{0,2}|\d{1,}[,.]\d{2}\s*[\$£€¥]?|\d{1,}[,.]\d{2}"#,
        options: .caseInsensitive
    )

    private static func extractAmount(from blocks: [TextBlock]) -> Double? {
        // Priority 1: Lines containing "total" keywords with an amount
        for keyword in totalKeywords {
            for block in blocks {
                let lower = block.text.lowercased()
                if lower.contains(keyword) {
                    if let value = parseAmount(from: block.text), value > 0 {
                        return value
                    }
                }
            }
        }

        // Priority 2: Largest currency-formatted amount (likely the total)
        var allAmounts: [(Double, TextBlock)] = []
        for block in blocks {
            if let value = parseAmount(from: block.text), value > 0 {
                allAmounts.append((value, block))
            }
        }

        // Favour amounts near the bottom of the receipt (lower boundingBox.origin.y in Vision = lower on image)
        if let best = allAmounts.sorted(by: { $0.0 > $1.0 }).first {
            return best.0
        }

        return nil
    }

    private static func parseAmount(from text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = amountPattern.matches(in: text, options: [], range: range)

        var best: Double?
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            var numString = String(text[matchRange])

            numString = numString.replacingOccurrences(of: "[$£€¥\\s]", with: "", options: .regularExpression)

            // Handle comma as thousands separator (1,234.56) vs decimal separator (12,50)
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
                if best == nil || value > best! {
                    best = value
                }
            }
        }

        return best
    }

    // MARK: - Merchant Extraction

    private static let merchantSkipPatterns = [
        "receipt", "invoice", "tax", "gst", "abn", "total", "subtotal",
        "change", "cash", "card", "visa", "mastercard", "eftpos",
        "date", "time", "thank", "welcome", "www.", "http", ".com",
        "phone", "tel:", "fax", "email", "address", "qty", "price"
    ]

    private static func extractMerchant(from blocks: [TextBlock]) -> String? {
        // The merchant name is typically the topmost prominent text on a receipt.
        // Vision's boundingBox: origin.y is from the bottom, so highest y = top of image.
        let topBlocks = blocks
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .prefix(5)

        for block in topBlocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.count < 2 || text.count > 40 { continue }

            let lower = text.lowercased()
            let isSkippable = merchantSkipPatterns.contains { lower.contains($0) }
            if isSkippable { continue }

            let digitCount = text.filter(\.isNumber).count
            if Double(digitCount) / Double(text.count) > 0.5 { continue }

            return text
        }

        return nil
    }
}

private struct TextBlock {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}
