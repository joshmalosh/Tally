import XCTest
import CoreGraphics
@testable import Tally

/// Regression suite for the receipt OCR field extraction. Every receipt that
/// has ever been reported as a miss gets a case here so the parser can only
/// get more versatile, never regress. Layouts are synthetic (text + bounding
/// box) but mirror the real receipts' structure. Vision coordinates: y is
/// normalized 0…1 and increases upward.
final class ReceiptOCRServiceTests: XCTestCase {

    // A single OCR block. Amounts usually land in their own right-aligned block,
    // so a "line" is often two blocks sharing a y.
    private func blk(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.3) -> (text: String, box: CGRect) {
        (text, CGRect(x: x, y: y - 0.01, width: w, height: 0.02))
    }
    private func amount(_ value: Double, from lines: [(text: String, box: CGRect)],
                        _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, value, accuracy: 0.001, message, file: file, line: line)
    }

    // MARK: - Hendry's Coffee — total restated on the card line; a curl-misread
    // "$54" must not win over the twice-seen $5.89.

    func testHendrys_total589_notMisread54() {
        let lines: [(text: String, box: CGRect)] = [
            blk("HENDRY'S COFFEE", x: 0.3, y: 0.92),
            blk("www.hendrys.coffee", x: 0.1, y: 0.88),
            blk("Cappuccino", x: 0.1, y: 0.50), blk("$5.80", x: 0.75, y: 0.50),
            blk("Subtotal", x: 0.1, y: 0.42), blk("$5.80", x: 0.75, y: 0.42),
            blk("Card surcharge (1.6%)", x: 0.1, y: 0.39), blk("$0.09", x: 0.75, y: 0.39),
            blk("Total", x: 0.1, y: 0.33), blk("$5.89", x: 0.75, y: 0.33),
            blk("10% Tax Included, $54", x: 0.1, y: 0.30, w: 0.5),   // misread of $0.54
            blk("Visa 3159 (Contactless)", x: 0.1, y: 0.27), blk("$5.89", x: 0.75, y: 0.27),
        ]
        amount(5.89, from: lines, "Total line should win")
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).currencyCode, "bare $ must not set a currency")
    }

    func testHendrys_curled_totalLabelDoesNotPair_crossConfirmWins() {
        // Curl: labels and their amounts sit at different heights so they don't
        // pair. $5.89 still appears twice (total + card) → cross-confirmed.
        let lines: [(text: String, box: CGRect)] = [
            blk("Subtotal", x: 0.1, y: 0.42), blk("$5.80", x: 0.75, y: 0.40),
            blk("Total", x: 0.1, y: 0.33), blk("$5.89", x: 0.75, y: 0.31),
            blk("$54", x: 0.75, y: 0.29),  // stray misread
            blk("Visa 3159", x: 0.1, y: 0.27), blk("$5.89", x: 0.75, y: 0.25),
        ]
        amount(5.89, from: lines, "Twice-seen 5.89 beats one-off 54")
    }

    // MARK: - Sushia — tax line + staff name traps.

    func testSushia_totalAmount_notLastItem() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Sushia Kellyville", x: 0.3, y: 0.95),
            blk("Sale Staff : Melissa", x: 0.1, y: 0.80, w: 0.5),
            blk("Chicken Lover", x: 0.1, y: 0.60), blk("$14.50", x: 0.75, y: 0.60),
            blk("Fish Cake", x: 0.1, y: 0.50), blk("$3.90", x: 0.75, y: 0.50),
            blk("Total Amount :", x: 0.1, y: 0.35), blk("$30.90", x: 0.75, y: 0.35),
            blk("Includes TAX :", x: 0.1, y: 0.32), blk("$2.82", x: 0.75, y: 0.32),
            blk("Eftpos :", x: 0.1, y: 0.29), blk("$30.90", x: 0.75, y: 0.29),
        ]
        amount(30.90, from: lines)
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertNotEqual(result.merchant, "Melissa", "Sale Staff name is not the merchant")
    }

    // MARK: - Paris — French labels + euro + tax lines.

    func testParis_montantDu_euro() {
        let lines: [(text: String, box: CGRect)] = [
            blk("le \"Relais de l'Entrecote\"", x: 0.2, y: 0.95, w: 0.6),
            blk("San Pellegrino", x: 0.1, y: 0.70), blk("7,00 €", x: 0.75, y: 0.70),
            blk("Entrecote A Point", x: 0.1, y: 0.66), blk("29,00 €", x: 0.75, y: 0.66),
            blk("TVA 10,00%", x: 0.1, y: 0.50), blk("7,41 €", x: 0.75, y: 0.50),
            blk("HT", x: 0.1, y: 0.48), blk("74,09 €", x: 0.75, y: 0.48),
            blk("TTC", x: 0.1, y: 0.46), blk("81,50 €", x: 0.75, y: 0.46),
            blk("MONTANT DU", x: 0.1, y: 0.40), blk("81,50 €", x: 0.75, y: 0.40),
        ]
        amount(81.50, from: lines)
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).currencyCode, "EUR")
    }

    // MARK: - Bunnings — GST-in-total line + future-date guard.

    func testBunnings_total_andNoFutureDate() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Bunnings Warehouse", x: 0.3, y: 0.95, w: 0.5),
            blk("Thu 28/05/2026 02:44:15 PM", x: 0.1, y: 0.80, w: 0.6),
            blk("WRENCH ADJUSTABLE", x: 0.1, y: 0.60), blk("$38.80", x: 0.75, y: 0.60),
            blk("SubTotal:", x: 0.1, y: 0.50), blk("$38.80", x: 0.75, y: 0.50),
            blk("Total", x: 0.1, y: 0.44), blk("$38.80", x: 0.75, y: 0.44),
            blk("GST included in the total", x: 0.1, y: 0.41, w: 0.5), blk("$3.53", x: 0.75, y: 0.41),
        ]
        amount(38.80, from: lines)
        let result = ReceiptOCRService.extractForTesting(lines)
        if let date = result.date {
            XCTAssertLessThanOrEqual(date, Date(), "OCR date must never be in the future")
        }
    }

    // MARK: - KFC — an item name contains a "$" amount ("15 Wicked Wings $10")
    // that coincides with its price, so the value 10 appears twice near the top.
    // The real total ($26.55) is at the bottom and >= the subtotal.

    func testKFC_total_notItemNamePrice() {
        let lines: [(text: String, box: CGRect)] = [
            blk("KFC Kellyville Village", x: 0.3, y: 0.95, w: 0.5),
            blk("15 Wicked Wings $10", x: 0.1, y: 0.60, w: 0.5), blk("10.00", x: 0.8, y: 0.60),
            blk("ZINGER BOX", x: 0.1, y: 0.57), blk("16.55", x: 0.8, y: 0.57),
            blk("Subtotal", x: 0.1, y: 0.42), blk("24.14", x: 0.8, y: 0.42),
            blk("Tax", x: 0.1, y: 0.40), blk("2.41", x: 0.8, y: 0.40),
            blk("Take Away Total", x: 0.1, y: 0.37, w: 0.4), blk("26.55", x: 0.8, y: 0.37),
            blk("Visa", x: 0.1, y: 0.33), blk("$26.55", x: 0.8, y: 0.33),
        ]
        amount(26.55, from: lines)
    }

    func testKFC_shadowed_totalDoesNotPair_subtotalFloorHolds() {
        // Total labels don't pair (shadow). $26.55 still appears twice and is
        // >= subtotal; the item's $10 is below the subtotal floor and is rejected.
        let lines: [(text: String, box: CGRect)] = [
            blk("15 Wicked Wings $10", x: 0.1, y: 0.60, w: 0.5), blk("10.00", x: 0.8, y: 0.58),
            blk("Subtotal", x: 0.1, y: 0.42), blk("24.14", x: 0.8, y: 0.40),
            blk("Take Away Total", x: 0.1, y: 0.37, w: 0.4), blk("26.55", x: 0.8, y: 0.35),
            blk("Visa", x: 0.1, y: 0.33), blk("26.55", x: 0.8, y: 0.31),
        ]
        amount(26.55, from: lines)
    }

    // MARK: - Woolworths — big bottom "You saved $14.90" / "Specials $14.90"
    // repeats the savings value twice, while the real TOTAL is small print.

    func testWoolworths_total_notSavedOrSpecials() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Woolworths", x: 0.3, y: 0.95, w: 0.4),
            blk("WW Lean Beef Mince 1kg", x: 0.1, y: 0.70, w: 0.5), blk("19.35", x: 0.8, y: 0.70),
            blk("10 SUBTOTAL", x: 0.1, y: 0.58, w: 0.4), blk("$49.49", x: 0.8, y: 0.58),
            blk("TOTAL", x: 0.1, y: 0.55), blk("$49.49", x: 0.8, y: 0.55),
            blk("PURCHASE", x: 0.1, y: 0.45), blk("$49.49", x: 0.8, y: 0.45),
            blk("EFT", x: 0.1, y: 0.38), blk("$49.49", x: 0.8, y: 0.38),
            blk("TOTAL includes GST", x: 0.1, y: 0.30, w: 0.5), blk("$1.27", x: 0.8, y: 0.30),
            blk("You saved $14.90", x: 0.3, y: 0.22, w: 0.5),
            blk("Specials", x: 0.1, y: 0.18), blk("$14.90", x: 0.8, y: 0.18),
        ]
        amount(49.49, from: lines)
        // Extraction finds the merchant even though the UI only applies it for
        // Pro users — this asserts the parser, not the paywall.
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Woolworths")
    }

    // The header above was too kind: "Woolworths" sat alone with nothing near
    // it, so the merchant assertion passed while the real photo returned a
    // blank merchant. This is the actual header — a large wordmark with three
    // small lines packed beneath it, shot at a slight angle so the tagline
    // drifts into the wordmark's vertical band.
    //
    // The old same-line test divided by the *shorter* box, so the tagline
    // counted as sharing the wordmark's line; the address line below it parses
    // "an amount" out of its street and phone numbers, and "Woolworths" was
    // discarded as half of a label-value pair. Every remaining candidate has
    // digits, so extraction returned nil.
    func testWoolworths_largeHeaderWithSmallPrintBeneath_stillFindsMerchant() {
        // Explicit boxes: the wordmark is 3x the height of the body text and
        // the tagline overlaps its band, which blk()'s uniform height can't
        // express.
        let lines: [(text: String, box: CGRect)] = [
            ("Woolworths",            CGRect(x: 0.28, y: 0.900, width: 0.44, height: 0.060)),
            ("The fresh food people", CGRect(x: 0.30, y: 0.892, width: 0.40, height: 0.018)),
            ("1659 Kellyville Grove PH: 02 9624 9402",
                                      CGRect(x: 0.12, y: 0.870, width: 0.76, height: 0.018)),
            ("2 Hector Court",        CGRect(x: 0.12, y: 0.850, width: 0.40, height: 0.018)),
            ("TAX INVOICE - ABN 88 000 014 675",
                                      CGRect(x: 0.12, y: 0.830, width: 0.76, height: 0.018)),
            blk("TOTAL", x: 0.1, y: 0.55), blk("$49.49", x: 0.8, y: 0.55),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "Woolworths",
                       "a large wordmark must survive small print drifting into its band")
        XCTAssertEqual(result.amount ?? -1, 49.49, accuracy: 0.001)
    }

    // A genuine label-value pair — same text size, side by side — must still be
    // rejected, or the stricter test above would be a licence to pick up staff
    // names again.
    func testLabelValuePairOnOneLine_stillRejected() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Served By", x: 0.10, y: 0.90), blk("Melissa", x: 0.60, y: 0.90),
            blk("TOTAL", x: 0.1, y: 0.55), blk("$30.90", x: 0.8, y: 0.55),
        ]
        XCTAssertNotEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Melissa",
                          "same-size text side by side is still a label-value pair")
    }

    // Noise phrases are stripped as whole words. Previously "cash" was removed
    // as a bare substring, so this merchant came back as "mere Boutique".
    func testMerchantContainingNoiseWordAsSubstring_isNotMangled() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Cashmere Boutique", x: 0.3, y: 0.95, w: 0.4),
            blk("TOTAL", x: 0.1, y: 0.55), blk("$80.00", x: 0.8, y: 0.55),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Cashmere Boutique")
    }

    // Real receipt, 19 Jul 2026: merchant came back "KELLYVILLE" (the suburb).
    // The store line is "WOOLWORTHS  1659   KELLYVILLE  NSW" — Vision splits it,
    // "WOOLWORTHS 1659" was rejected for containing a digit, and the clean
    // suburb won. Chains print the store number after the name, so a single
    // trailing numeric token is now dropped before the digit test, and same-line
    // blocks are read left to right.
    func testWoolworths_storeNumberLine_merchantNotSuburb() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Garlic", x: 0.10, y: 0.80), blk("1.55", x: 0.80, y: 0.80),
            blk("TOTAL", x: 0.10, y: 0.60), blk("$49.49", x: 0.80, y: 0.60),
            blk("WOOLWORTHS  1659", x: 0.10, y: 0.45, w: 0.30),
            blk("KELLYVILLE", x: 0.50, y: 0.45, w: 0.20),
            blk("NSW", x: 0.78, y: 0.45, w: 0.10),
            blk("TAX INVOICE - ABN 88 000 014 675", x: 0.10, y: 0.40, w: 0.70),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "WOOLWORTHS", "the chain, not the suburb")
        XCTAssertEqual(result.amount ?? -1, 49.49, accuracy: 0.001)
    }

    // Same line, but split the way Vision actually splits it — the store number
    // is its own block — and skewed, as a hand-held photo always is. Both
    // details defeated the first attempt at this fix: "1659" parsed as an amount
    // so "WOOLWORTHS" was dropped as a label-value pair, and the blocks' y
    // values differ so an exact-equality x tiebreak never fired.
    func testWoolworths_storeNumberSeparateBlockAndSkewed_merchantNotSuburb() {
        let lines: [(text: String, box: CGRect)] = [
            ("TOTAL",      CGRect(x: 0.10, y: 0.600, width: 0.15, height: 0.020)),
            ("$49.49",     CGRect(x: 0.80, y: 0.596, width: 0.15, height: 0.020)),
            ("WOOLWORTHS", CGRect(x: 0.10, y: 0.450, width: 0.22, height: 0.020)),
            ("1659",       CGRect(x: 0.36, y: 0.447, width: 0.08, height: 0.020)),
            ("KELLYVILLE", CGRect(x: 0.52, y: 0.443, width: 0.20, height: 0.020)),
            ("NSW",        CGRect(x: 0.80, y: 0.440, width: 0.09, height: 0.020)),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "WOOLWORTHS")
    }

    // The real receipt, top to bottom: large "Woolworths" wordmark with a swirl
    // logo beside it, script tagline, address, ABN, then uniform monospace body.
    // The wordmark is the merchant; "KELLYVILLE" on the merchant-ID line further
    // down is the suburb and must lose.
    func testWoolworths_fullReceiptHeader_wordmarkWins() {
        let lines: [(text: String, box: CGRect)] = [
            ("Woolworths",            CGRect(x: 0.24, y: 0.940, width: 0.42, height: 0.028)),
            ("The fresh food people", CGRect(x: 0.28, y: 0.915, width: 0.34, height: 0.013)),
            ("1659 Kellyville Grove  PH: 02 9624 9402",
                                      CGRect(x: 0.22, y: 0.895, width: 0.50, height: 0.011)),
            ("2 Hector Court",        CGRect(x: 0.36, y: 0.882, width: 0.20, height: 0.011)),
            ("TAX INVOICE - ABN 88 000 014 675",
                                      CGRect(x: 0.24, y: 0.869, width: 0.46, height: 0.011)),
            blk("TOTAL", x: 0.22, y: 0.560, w: 0.10), blk("$49.49", x: 0.62, y: 0.560, w: 0.10),
            blk("WOOLWORTHS", x: 0.21, y: 0.480, w: 0.14),
            blk("1659", x: 0.40, y: 0.479, w: 0.05),
            blk("KELLYVILLE", x: 0.52, y: 0.478, w: 0.13),
            blk("NSW", x: 0.68, y: 0.477, w: 0.05),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "Woolworths")
        XCTAssertEqual(result.amount ?? -1, 49.49, accuracy: 0.001)
    }

    // A stray `@` — a logo glyph misread beside a wordmark — must not disqualify
    // a merchant. Only an email's shape should.
    func testWordmarkWithLogoGlyph_notTreatedAsEmail() {
        let lines: [(text: String, box: CGRect)] = [
            ("Woolworths @",  CGRect(x: 0.24, y: 0.940, width: 0.42, height: 0.028)),
            blk("TOTAL", x: 0.10, y: 0.55), blk("$49.49", x: 0.80, y: 0.55),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Woolworths")
    }

    // MARK: - Deus, Bali — Indonesian rupiah, grouped thousands, crumpled photo.

    // Amounts are "1,150,000" style: comma groups of three, no cents. The regex
    // used to grab "655,00" out of "655,000" and the European decimal-comma rule
    // turned it into 655.00 — which is exactly what the app displayed.
    func testDeus_groupedThousands_notTruncatedToCents() {
        let lines: [(text: String, box: CGRect)] = [
            blk("PT. Deus Ex Machina Indonesia", x: 0.20, y: 0.92, w: 0.55),
            blk("ONE OUT TEAM CREW", x: 0.15, y: 0.70, w: 0.40), blk("1,150,000", x: 0.75, y: 0.70),
            blk("RAPTOR TEE", x: 0.15, y: 0.66, w: 0.30), blk("655,000", x: 0.75, y: 0.66),
            blk("SUPERSTITIOUS JACKET", x: 0.15, y: 0.62, w: 0.42), blk("2,835,000", x: 0.75, y: 0.62),
            blk("SubTotal", x: 0.45, y: 0.50, w: 0.15), blk("4,640,000", x: 0.75, y: 0.50),
            blk("Payment Amount ( CC&DC_0%", x: 0.15, y: 0.42, w: 0.45),
            blk("4,640,000", x: 0.75, y: 0.42),
        ]
        amount(4_640_000, from: lines, "grouped thousands must not be read as cents")
    }

    // The letterhead is crumpled and OCRs poorly; the promo banner at the foot of
    // the docket scans cleanly. The masthead must still win — the old two-pass
    // order ran high-confidence over the whole receipt first, so the banner won.
    func testDeus_crumpledHeader_beatsCleanPromoBannerAtFoot() {
        let lines = [
            (text: "PT. Deus Ex Machina Indonesia",
             box: CGRect(x: 0.20, y: 0.915, width: 0.55, height: 0.018), confidence: Float(0.42)),
            (text: "Jalan Batu Mejan No. 8, Canggu - Bali",
             box: CGRect(x: 0.20, y: 0.895, width: 0.55, height: 0.014), confidence: Float(0.40)),
            (text: "SubTotal", box: CGRect(x: 0.45, y: 0.500, width: 0.15, height: 0.014), confidence: 0.90),
            (text: "4,640,000", box: CGRect(x: 0.75, y: 0.500, width: 0.18, height: 0.014), confidence: 0.90),
            (text: "AU-PROMO LEBARAN UP TO",
             box: CGRect(x: 0.40, y: 0.140, width: 0.45, height: 0.016), confidence: Float(0.95)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertNotEqual(result.merchant, "AU-PROMO LEBARAN UP TO",
                          "a promo banner at the foot of the docket is never the merchant")
        XCTAssertEqual(result.merchant, "PT. Deus Ex Machina Indonesia")
    }

    // A stray glyph — the stylised DEUS shield misread as "€" — must not set the
    // expense currency. A symbol only counts beside a number.
    func testCurrencySymbolAloneInLogo_doesNotSetCurrency() {
        let lines: [(text: String, box: CGRect)] = [
            blk("€", x: 0.45, y: 0.95, w: 0.06),
            blk("PT. Deus Ex Machina Indonesia", x: 0.20, y: 0.92, w: 0.55),
            blk("SubTotal", x: 0.45, y: 0.50, w: 0.15), blk("4,640,000", x: 0.75, y: 0.50),
        ]
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).currencyCode,
                     "a logo glyph is not a currency marker")
    }

    // A visible wordmark wins outright — it's printed far larger than the body
    // text, which is a more direct signal than any of the filter passes.
    func testLargeWordmark_winsOverEverythingBelow() {
        let lines: [(text: String, box: CGRect)] = [
            ("BUNNINGS",   CGRect(x: 0.25, y: 0.900, width: 0.50, height: 0.070)),
            ("Warehouse",  CGRect(x: 0.35, y: 0.870, width: 0.30, height: 0.018)),
            ("Rouse Hill", CGRect(x: 0.35, y: 0.850, width: 0.30, height: 0.018)),
            blk("TOTAL", x: 0.10, y: 0.55), blk("$38.80", x: 0.80, y: 0.55),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "BUNNINGS")
    }

    // Uniform monospace with no wordmark — the header pass must find nothing and
    // fall through rather than picking the tallest body line at random. (Kept as
    // a general case. It was written believing Josh's Woolworths photo had no
    // wordmark; it does — that was a wrong reading of a cropped UI thumbnail.)
    func testNoWordmark_fallsThroughToFilterPasses() {
        let lines: [(text: String, box: CGRect)] = [
            blk("WOOLWORTHS", x: 0.10, y: 0.45, w: 0.22),
            blk("KELLYVILLE", x: 0.52, y: 0.45, w: 0.20),
            blk("TOTAL", x: 0.10, y: 0.60), blk("$49.49", x: 0.80, y: 0.60),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "WOOLWORTHS")
    }

    // The guard that "1659" defeated must still hold for real prices.
    func testItemNameBesideItsPrice_stillRejectedAsMerchant() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Flat White", x: 0.10, y: 0.90, w: 0.25), blk("$4.50", x: 0.80, y: 0.90),
            blk("TOTAL", x: 0.10, y: 0.60), blk("$4.50", x: 0.80, y: 0.60),
        ]
        XCTAssertNotEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Flat White")
    }

    // The trailing-number strip must not let addresses through: a leading street
    // number, or more than one numeric token, still disqualifies the line.
    func testAddressLines_stillRejectedAsMerchant() {
        let lines: [(text: String, box: CGRect)] = [
            blk("2 Hector Court", x: 0.10, y: 0.90, w: 0.40),
            blk("1659 Kellyville Grove PH: 02 9624 9402", x: 0.10, y: 0.86, w: 0.70),
            blk("TOTAL", x: 0.10, y: 0.60), blk("$12.00", x: 0.80, y: 0.60),
        ]
        let merchant = ReceiptOCRService.extractForTesting(lines).merchant
        XCTAssertNotEqual(merchant, "Hector Court")
        XCTAssertNotEqual(merchant, "Kellyville Grove PH:")
    }

    func testWoolworths_onlySavingsLegible_neverReturnsSavings() {
        // Worst case: the small print didn't OCR at all and only the large
        // savings text came through. Better to return nothing than the wrong
        // amount — the user then types it rather than silently saving $14.90.
        // NOTE: "Specials" and "$14.90" arrive as SEPARATE blocks on one line,
        // so the amount must inherit the label's exclusion.
        let lines: [(text: String, box: CGRect)] = [
            blk("Woolworths", x: 0.3, y: 0.95, w: 0.4),
            blk("You saved $14.90", x: 0.3, y: 0.22, w: 0.5),
            blk("Specials", x: 0.1, y: 0.18), blk("$14.90", x: 0.8, y: 0.18),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertNotEqual(result.amount ?? -1, 14.90, accuracy: 0.001,
                          "savings figure must never be used as the amount")
    }

    func testWoolworths_perKgRate_neverReturnsUnitPrice() {
        // Weighed-item rate lines ("0.047 kg NET @ $33.00/kg") are unit prices,
        // not amounts. With the small print illegible the scanner previously
        // returned $33.00 — the highest currency-marked figure on the receipt.
        let lines: [(text: String, box: CGRect)] = [
            blk("Woolworths", x: 0.3, y: 0.95, w: 0.4),
            blk("Carrot", x: 0.1, y: 0.80), blk("1.02", x: 0.8, y: 0.80),
            blk("0.392 kg NET @ $2.60/kg", x: 0.12, y: 0.78, w: 0.5),
            blk("Garlic", x: 0.1, y: 0.72), blk("1.55", x: 0.8, y: 0.72),
            blk("0.047 kg NET @ $33.00/kg", x: 0.12, y: 0.70, w: 0.5),
            blk("Qty  2 @  $7.00   each", x: 0.12, y: 0.64, w: 0.5), blk("14.00", x: 0.8, y: 0.64),
            blk("You saved $14.90", x: 0.3, y: 0.22, w: 0.5),
            blk("Specials", x: 0.1, y: 0.18), blk("$14.90", x: 0.8, y: 0.18),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertNotEqual(result.amount ?? -1, 33.00, accuracy: 0.001,
                          "per-kg unit rate must never be used as the amount")
        XCTAssertNotEqual(result.amount ?? -1, 14.90, accuracy: 0.001,
                          "savings figure must never be used as the amount")
    }

    // MARK: - Monos — savings + GST-of lines must not win.

    func testMonos_total_notSavingsOrGst() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Monos Travel Ltd.", x: 0.1, y: 0.90, w: 0.5),
            blk("Subtotal", x: 0.1, y: 0.55), blk("$300.00", x: 0.75, y: 0.55),
            blk("TOTAL SAVINGS $52.94", x: 0.1, y: 0.45, w: 0.6),
            blk("Total (GST incl. #63 473 379 773)", x: 0.1, y: 0.38, w: 0.55),
            blk("$300.00", x: 0.8, y: 0.38),
        ]
        amount(300.00, from: lines)
        // Registered business name wins the merchant.
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).merchant, "Monos Travel Ltd")
    }
}
