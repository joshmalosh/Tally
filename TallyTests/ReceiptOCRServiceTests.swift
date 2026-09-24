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

    // The whole docket as photographed: wordmark, letterhead, weighed items with
    // per-kg rates, the merchant-ID block, the EFT block, and the rewards footer.
    // Every Woolworths test below isolates one trap; this is the receipt.
    //
    // Reported readings across three scans: $33.00 (per-kg rate), $14.90
    // (savings), $49.49 correct, then 49.00. Merchant: blank, KELLYVILLE, then
    // Woolworths correct.
    func testWoolworths_wholeReceipt_allFields() {
        let lines: [(text: String, box: CGRect)] = [
            ("Woolworths",            CGRect(x: 0.30, y: 0.952, width: 0.30, height: 0.020)),
            ("The fresh food people", CGRect(x: 0.36, y: 0.936, width: 0.22, height: 0.008)),
            blk("1659 Kellyville Grove  PH: 02 9624 9402", x: 0.30, y: 0.925, w: 0.40),
            blk("2 Hector Court", x: 0.41, y: 0.917, w: 0.16),
            blk("TAX INVOICE - ABN 88 000 014 675", x: 0.33, y: 0.909, w: 0.34),
            blk("POS 065 TRANS 1547 09:33 19/07/2026", x: 0.32, y: 0.901, w: 0.37),

            blk("Carrot", x: 0.30, y: 0.870, w: 0.08),
            blk("0.392 kg NET @ $2.60/kg", x: 0.31, y: 0.862, w: 0.26), blk("1.02", x: 0.63, y: 0.862, w: 0.05),
            blk("Zucchini Green Kg", x: 0.30, y: 0.853, w: 0.19),
            blk("0.352 kg NET @ $4.90/kg", x: 0.31, y: 0.845, w: 0.26), blk("1.72", x: 0.63, y: 0.845, w: 0.05),
            blk("Mushroom Cups Loose", x: 0.30, y: 0.836, w: 0.22),
            blk("0.213 kg NET @ $12.90/kg", x: 0.31, y: 0.828, w: 0.27), blk("2.75", x: 0.63, y: 0.828, w: 0.05),
            blk("Garlic", x: 0.30, y: 0.819, w: 0.08),
            blk("0.047 kg NET @ $33.00/kg", x: 0.31, y: 0.811, w: 0.27), blk("1.55", x: 0.63, y: 0.811, w: 0.05),
            blk("WW Lean Beef Mince 1kg", x: 0.30, y: 0.802, w: 0.25), blk("19.35", x: 0.62, y: 0.802, w: 0.06),
            blk("Campbells Real Stock Beef 500ml", x: 0.30, y: 0.793, w: 0.33), blk("2.75", x: 0.63, y: 0.793, w: 0.05),
            blk("^ Mutti Finely Chopped Tomatoes 790g", x: 0.30, y: 0.784, w: 0.36), blk("3.40", x: 0.63, y: 0.784, w: 0.05),
            blk("San Remo Pasta Elbows No. 35 500g", x: 0.30, y: 0.775, w: 0.35), blk("2.95", x: 0.63, y: 0.775, w: 0.05),
            blk("^#Up&go Energize Strawberry 6x250ml", x: 0.30, y: 0.766, w: 0.37),
            blk("Qty   2 @   $7.00    each", x: 0.31, y: 0.757, w: 0.24), blk("14.00", x: 0.62, y: 0.757, w: 0.06),

            blk("10 SUBTOTAL", x: 0.31, y: 0.735, w: 0.13), blk("$49.49", x: 0.61, y: 0.735, w: 0.07),
            blk("TOTAL", x: 0.33, y: 0.726, w: 0.07), blk("$49.49", x: 0.61, y: 0.726, w: 0.07),

            blk("WOOLWORTHS", x: 0.30, y: 0.690, w: 0.12),
            blk("1659", x: 0.44, y: 0.690, w: 0.04),
            blk("KELLYVILLE", x: 0.52, y: 0.689, w: 0.11),
            blk("NSW", x: 0.66, y: 0.689, w: 0.04),
            blk("MERCH ID:611000602001659", x: 0.30, y: 0.681, w: 0.24),
            blk("TERM ID:", x: 0.50, y: 0.681, w: 0.09), blk("W1659065", x: 0.62, y: 0.681, w: 0.09),
            blk("Visa DEBIT", x: 0.30, y: 0.672, w: 0.11), blk("CREDIT", x: 0.44, y: 0.672, w: 0.07),
            blk("CARD:.............6043 T", x: 0.50, y: 0.672, w: 0.19),
            blk("AID", x: 0.30, y: 0.663, w: 0.03), blk("A0000000031010", x: 0.37, y: 0.663, w: 0.14),
            blk("PURCHASE", x: 0.50, y: 0.663, w: 0.10), blk("$49.49", x: 0.62, y: 0.663, w: 0.07),
            blk("TVR", x: 0.30, y: 0.654, w: 0.03), blk("0000000000", x: 0.38, y: 0.654, w: 0.11),
            blk("ARQC", x: 0.30, y: 0.645, w: 0.05), blk("0ED34F64FB014C61", x: 0.37, y: 0.645, w: 0.16),
            blk("TOTAL", x: 0.50, y: 0.645, w: 0.06), blk("$49.49", x: 0.62, y: 0.645, w: 0.07),
            blk("ATC", x: 0.30, y: 0.636, w: 0.03), blk("0292", x: 0.44, y: 0.636, w: 0.05),
            blk("PSN", x: 0.50, y: 0.636, w: 0.04), blk("00", x: 0.66, y: 0.636, w: 0.03),
            blk("19/07/26 09:33", x: 0.30, y: 0.627, w: 0.14), blk("001547", x: 0.44, y: 0.627, w: 0.07),
            blk("APPROVED", x: 0.50, y: 0.627, w: 0.10), blk("00", x: 0.66, y: 0.627, w: 0.03),

            blk("EFT", x: 0.33, y: 0.608, w: 0.04), blk("$49.49", x: 0.61, y: 0.608, w: 0.07),
            blk("Change", x: 0.33, y: 0.599, w: 0.07), blk("$0.00", x: 0.62, y: 0.599, w: 0.06),
            blk("^Promotional Price", x: 0.29, y: 0.583, w: 0.18),
            blk("#Taxable Items", x: 0.29, y: 0.567, w: 0.15),
            blk("TOTAL includes GST", x: 0.29, y: 0.559, w: 0.19), blk("$1.27", x: 0.62, y: 0.559, w: 0.06),

            ("You saved $14.90", CGRect(x: 0.34, y: 0.537, width: 0.25, height: 0.014)),
            ("Specials",         CGRect(x: 0.29, y: 0.522, width: 0.11, height: 0.013)),
            ("$14.90",           CGRect(x: 0.60, y: 0.522, width: 0.09, height: 0.013)),
            blk("Everyday Rewards", x: 0.38, y: 0.508, w: 0.17),
            blk("Nice! You just collected 50 points.", x: 0.34, y: 0.500, w: 0.30),
            blk("Enjoy $20 off your next shop*", x: 0.36, y: 0.484, w: 0.27),
            blk("1234/2000", x: 0.58, y: 0.472, w: 0.10),
            blk("Points balance", x: 0.31, y: 0.464, w: 0.14),
            blk("*T&Cs apply. Visit everyday.com.au/terms", x: 0.30, y: 0.448, w: 0.38),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)

        XCTAssertEqual(result.amount ?? -1, 49.49, accuracy: 0.001,
                       "not 33.00 (per-kg), 14.90 (savings), 1.27 (GST) or 49.00")
        XCTAssertEqual(result.merchant, "Woolworths", "the wordmark, not the suburb")
        XCTAssertNil(result.currencyCode, "a bare $ must not pin a currency")

        let parts = Calendar.current.dateComponents([.year, .month, .day], from: result.date ?? .distantPast)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 19)
    }

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

    // Woolworths Castle Hill: the two-word suburb "CASTLE HILL" prints in the
    // letterhead address AND the EFTPOS footer ("CASTLE HILL" beside "NSW"), so it
    // recurs and used to win the recurring-2+word-phrase boost over the wordmark
    // ("HILL" isn't a street/centre suffix, so that guard missed it). The wordmark
    // itself carries the swirl logo OCR'd as an "O" ("Woolworths O"). Merchant must
    // be the wordmark, de-glyphed and corroborated by the footer "WOOLWORTHS".
    func testWoolworths_castleHill_recurringSuburbAndLogoGlyph_wordmarkWins() {
        let lines: [(text: String, box: CGRect)] = [
            ("Woolworths O",          CGRect(x: 0.30, y: 0.940, width: 0.30, height: 0.030)),
            ("The fresh food people", CGRect(x: 0.33, y: 0.915, width: 0.24, height: 0.013)),
            ("1045 Castle Hill Showground Village  PH: 02 8633 2991",
                                      CGRect(x: 0.20, y: 0.895, width: 0.55, height: 0.012)),
            ("4 Mandala Parade",      CGRect(x: 0.40, y: 0.882, width: 0.20, height: 0.012)),
            ("TAX INVOICE - ABN 88 000 014 675",
                                      CGRect(x: 0.24, y: 0.869, width: 0.46, height: 0.012)),
            blk("4 SUBTOTAL", x: 0.22, y: 0.64, w: 0.14), blk("$19.75", x: 0.72, y: 0.64, w: 0.10),
            blk("TOTAL", x: 0.22, y: 0.615, w: 0.10), blk("$19.75", x: 0.72, y: 0.615, w: 0.10),
            // EFTPOS footer: "WOOLWORTHS 1045   CASTLE HILL   NSW" as separate blocks.
            blk("WOOLWORTHS", x: 0.21, y: 0.40, w: 0.14),
            blk("1045", x: 0.40, y: 0.399, w: 0.05),
            blk("CASTLE HILL", x: 0.52, y: 0.40, w: 0.13),
            blk("NSW", x: 0.68, y: 0.399, w: 0.05),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "Woolworths", "wordmark, not the recurring suburb")
        XCTAssertEqual(result.amount ?? -1, 19.75, accuracy: 0.001)
    }

    // MARK: - Orientation — the Woolworths photo Vision read sideways.

    // The real miss wasn't the block scoring (the header tests above already
    // pass): the camera photo was stored sideways with a `.right` flag, and the
    // OCR ran on the raw buffer without it, so every block came back rotated 90°
    // (each one taller than wide) and "top of receipt" pointed at the receipt's
    // edge instead of its head. The suburb won. The fix hands Vision the flag;
    // this pins the mapping so a future refactor can't drop it. Name-to-name is
    // correct — the two enums number their cases differently.
    func testImageOrientation_mappedForVision_notByRawValue() {
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.up), .up)
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.right), .right)
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.left), .left)
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.down), .down)
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.upMirrored), .upMirrored)
        XCTAssertEqual(ReceiptOCRService.orientationForTesting(.rightMirrored), .rightMirrored)
    }

    // MARK: - Deus, Bali — Indonesian rupiah, grouped thousands, crumpled photo.

    // The whole docket, top to bottom, at the confidences a crumpled photo
    // actually produces. The tests below isolate one defect each; this one is
    // the receipt itself, and asserts every field including the date — which
    // came out right unaided and is pinned so it stays that way.
    //
    // Reported reading: amount 655.00, currency EUR, merchant
    // "AL FROND LEBARAN UP TO". Only the date was correct.
    func testDeus_wholeReceipt_allFields() {
        let lines: [(text: String, box: CGRect, confidence: Float)] = [
            ("€",                                  CGRect(x: 0.44, y: 0.930, width: 0.07, height: 0.022), 0.31),
            ("PT. Deus Ex Machina Indonesia",      CGRect(x: 0.20, y: 0.905, width: 0.55, height: 0.016), 0.44),
            ("Jalan Batu Mejan No. 8, Canggu - Bali", CGRect(x: 0.18, y: 0.888, width: 0.60, height: 0.013), 0.41),
            ("Phone: +62 811 3883 15",             CGRect(x: 0.26, y: 0.872, width: 0.42, height: 0.013), 0.52),
            ("Email: info@deus.co.id",             CGRect(x: 0.28, y: 0.857, width: 0.38, height: 0.013), 0.55),
            ("NPWP: 31.182.580.2.906.000",         CGRect(x: 0.25, y: 0.842, width: 0.44, height: 0.013), 0.48),

            ("110719512875",                       CGRect(x: 0.13, y: 0.740, width: 0.20, height: 0.012), 0.70),
            ("1,150,000",                          CGRect(x: 0.72, y: 0.742, width: 0.16, height: 0.012), 0.86),
            ("ONE OUT TEAM CREW - LIGHT GREY MARLE - M", CGRect(x: 0.13, y: 0.726, width: 0.62, height: 0.012), 0.66),
            ("655,000",                            CGRect(x: 0.74, y: 0.700, width: 0.13, height: 0.012), 0.88),
            ("RAPTOR TEE - DIRTY WHITE - M",       CGRect(x: 0.13, y: 0.686, width: 0.46, height: 0.012), 0.69),
            ("2,835,000",                          CGRect(x: 0.72, y: 0.660, width: 0.16, height: 0.012), 0.87),
            ("SUPERSTITIOUS JACKET - CHOC BROWN - S", CGRect(x: 0.13, y: 0.646, width: 0.58, height: 0.012), 0.68),

            ("SubTotal",                           CGRect(x: 0.52, y: 0.560, width: 0.14, height: 0.012), 0.90),
            ("4,640,000",                          CGRect(x: 0.72, y: 0.560, width: 0.16, height: 0.012), 0.91),
            ("PPN",                                CGRect(x: 0.13, y: 0.530, width: 0.07, height: 0.012), 0.80),
            ("458,820",                            CGRect(x: 0.42, y: 0.530, width: 0.13, height: 0.012), 0.85),
            ("Payment Amount ( CC&DC_0%",          CGRect(x: 0.13, y: 0.480, width: 0.45, height: 0.012), 0.72),
            ("4,640,000",                          CGRect(x: 0.72, y: 0.480, width: 0.16, height: 0.012), 0.90),

            ("INV-V01/2504/46076",                 CGRect(x: 0.58, y: 0.420, width: 0.30, height: 0.012), 0.84),
            ("25/04/2025 09:13",                   CGRect(x: 0.62, y: 0.402, width: 0.26, height: 0.012), 0.86),
            ("CASH",                               CGRect(x: 0.78, y: 0.370, width: 0.10, height: 0.012), 0.88),
            ("AU-PROMO LEBARAN UP TO",             CGRect(x: 0.46, y: 0.345, width: 0.42, height: 0.014), 0.95),
            ("40%",                                CGRect(x: 0.80, y: 0.330, width: 0.08, height: 0.014), 0.93),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)

        XCTAssertEqual(result.amount ?? -1, 4_640_000, accuracy: 0.001,
                       "grouped thousands, not 655.00")
        XCTAssertEqual(result.currencyCode, "IDR",
                       "letterhead names Indonesia; the lone € is a logo glyph")
        XCTAssertEqual(result.merchant, "PT. Deus Ex Machina Indonesia",
                       "not the promo banner at the foot")

        let parts = Calendar.current.dateComponents([.year, .month, .day], from: result.date ?? .distantPast)
        XCTAssertEqual(parts.year, 2025)
        XCTAssertEqual(parts.month, 4)
        XCTAssertEqual(parts.day, 25)
    }

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
    // expense currency. A symbol only counts beside a number. No country name
    // here, so the place-name fallback stays out of it and the result is nil.
    func testCurrencySymbolAloneInLogo_doesNotSetCurrency() {
        let lines: [(text: String, box: CGRect)] = [
            blk("€", x: 0.45, y: 0.95, w: 0.06),
            blk("Corner Store", x: 0.20, y: 0.92, w: 0.30),
            blk("SubTotal", x: 0.45, y: 0.50, w: 0.15), blk("4,640,000", x: 0.75, y: 0.50),
        ]
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).currencyCode,
                     "a logo glyph is not a currency marker")
    }

    // The letterhead names the country, which is a far more reliable signal than
    // a currency marker — this receipt prints neither "IDR" nor "Rp".
    func testDeus_countryInLetterhead_resolvesRupiah() {
        let lines: [(text: String, box: CGRect)] = [
            blk("PT. Deus Ex Machina Indonesia", x: 0.20, y: 0.92, w: 0.55),
            blk("Jalan Batu Mejan No. 8, Canggu - Bali", x: 0.18, y: 0.90, w: 0.60),
            blk("SubTotal", x: 0.45, y: 0.50, w: 0.15), blk("4,640,000", x: 0.75, y: 0.50),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).currencyCode, "IDR")
    }

    // A place name is the last resort. An explicit symbol beside a number still
    // wins, so a euro receipt from a shop that happens to mention Australia
    // stays in euros.
    func testExplicitSymbol_beatsPlaceName() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Souvenirs of Australia", x: 0.20, y: 0.92, w: 0.45),
            blk("TOTAL", x: 0.10, y: 0.55), blk("€81.50", x: 0.80, y: 0.55),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).currencyCode, "EUR")
    }

    // Word-boundary anchored: a suburb called Chinatown is not a vote for yuan.
    func testPlaceNameInsideAnotherWord_doesNotVote() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Chinatown Noodle House", x: 0.20, y: 0.92, w: 0.45),
            blk("TOTAL", x: 0.10, y: 0.55), blk("18.50", x: 0.80, y: 0.55),
        ]
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).currencyCode)
    }

    // Backstop: promo boilerplate is never the merchant, even when it is the
    // only candidate left. Returning nothing beats returning a marketing slogan.
    func testPromoBanner_neverBecomesMerchant() {
        let lines: [(text: String, box: CGRect)] = [
            blk("AU-PROMO LEBARAN UP TO", x: 0.40, y: 0.30, w: 0.45),
            blk("TOTAL", x: 0.15, y: 0.55), blk("4,640,000", x: 0.75, y: 0.55),
        ]
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).merchant)
    }

    func testFooterBoilerplate_neverBecomesMerchant() {
        for slogan in ["No Cash Refunds - Exchange only valid",
                       "Thank You for shopping with us",
                       "Terms and conditions apply",
                       "Everyday Rewards"] {
            let lines: [(text: String, box: CGRect)] = [
                blk(slogan, x: 0.20, y: 0.30, w: 0.55),
                blk("TOTAL", x: 0.15, y: 0.55), blk("12.00", x: 0.75, y: 0.55),
            ]
            XCTAssertNil(ReceiptOCRService.extractForTesting(lines).merchant,
                         "\"\(slogan)\" is not a merchant")
        }
    }

    // Cherry Beans, Kellyville — the whole receipt sits mid-frame with table
    // around it, so the wordmark's midY is well below the image's top 40%. The
    // header must still win off the receipt's own extent. Reported readings:
    // "chip" (off "Contactless chip" at the foot), then nothing.
    // The name wraps two lines ("Cherry Beans Kellyvil" / "le"); the first line
    // is accepted.
    func testCherryBeans_receiptMidFrame_findsWordmarkNotFooter() {
        let lines: [(text: String, box: CGRect)] = [
            // Wordmark, large, but only at y≈0.72 — below the image's top 40%.
            ("Cherry Beans Kellyvil", CGRect(x: 0.28, y: 0.720, width: 0.44, height: 0.024)),
            ("le",                    CGRect(x: 0.47, y: 0.698, width: 0.06, height: 0.024)),
            blk("ABN: 73 612 976 584", x: 0.34, y: 0.672, w: 0.32),
            blk("Halloumi & Egg roll", x: 0.28, y: 0.560, w: 0.30), blk("11.90", x: 0.66, y: 0.560, w: 0.06),
            blk("TOTAL", x: 0.28, y: 0.470, w: 0.08), blk("35.83", x: 0.66, y: 0.470, w: 0.06),
            blk("Entry mode : Contactless chip", x: 0.28, y: 0.360, w: 0.34),
            blk("APPROVED : approved", x: 0.28, y: 0.320, w: 0.24),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "Cherry Beans Kellyvil",
                       "the wordmark, mid-frame, not the footer 'chip'")
        XCTAssertEqual(result.amount ?? -1, 35.83, accuracy: 0.001)
    }

    // Liquorland — long docket, wordmark at the top reading at the *same* size
    // as the body and at low confidence (so the tall-wordmark pass does not fire
    // and the fallback runs), a crisp "TOTAL (Inc GST)" in the middle. The
    // whole-receipt high-confidence pass picked TOTAL. A total line is never a
    // merchant, so it must be rejected; the top-of-receipt name wins instead.
    // Reported: merchant "TOTAL (Inc GST)", amount 461 correct.
    func testLiquorland_totalLineNeverMerchant() {
        let lines: [(text: String, box: CGRect, confidence: Float)] = [
            ("LIQUORLAND",          CGRect(x: 0.30, y: 0.940, width: 0.40, height: 0.012), 0.55),
            ("ABN 82007512414",     CGRect(x: 0.34, y: 0.900, width: 0.32, height: 0.011), 0.85),
            ("Description",         CGRect(x: 0.28, y: 0.720, width: 0.16, height: 0.011), 0.90),
            ("TOTAL (Inc GST)",     CGRect(x: 0.28, y: 0.640, width: 0.20, height: 0.012), 0.95),
            ("461.00",              CGRect(x: 0.66, y: 0.640, width: 0.08, height: 0.012), 0.95),
            ("Paid by EFTPOS",      CGRect(x: 0.28, y: 0.610, width: 0.20, height: 0.011), 0.92),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertNotEqual(result.merchant, "TOTAL (Inc GST)", "a total line is never a merchant")
        XCTAssertEqual(result.merchant, "LIQUORLAND", "the top-of-receipt name, found via the masthead pass")
        XCTAssertEqual(result.amount ?? -1, 461.00, accuracy: 0.001)
    }

    // rankedMerchants exposes lower-ranked *clean* guesses for the "Doesn't look
    // right?" picker. The winner is excluded from its own alternates, and
    // rejected junk (TOTAL) never appears.
    func testMerchantAlternates_cleanCandidatesOnly() {
        let lines: [(text: String, box: CGRect)] = [
            blk("LIQUORLAND", x: 0.30, y: 0.94, w: 0.40),
            blk("SAY NO TO PLASTIC BAGS", x: 0.30, y: 0.90, w: 0.40),
            blk("TOTAL (Inc GST)", x: 0.28, y: 0.60, w: 0.20), blk("461.00", x: 0.66, y: 0.60),
        ]
        let r = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(r.merchant, "LIQUORLAND")
        XCTAssertFalse(r.merchantAlternates.contains("LIQUORLAND"), "winner excluded from its own alternates")
        XCTAssertFalse(r.merchantAlternates.contains("TOTAL (Inc GST)"), "rejected junk never offered")
        XCTAssertTrue(r.merchantAlternates.contains("SAY NO TO PLASTIC BAGS"), "a clean lower-ranked line is offered")
        XCTAssertLessThanOrEqual(r.merchantAlternates.count, 5)
    }

    // Receipt-structural labels are never a merchant, even alone. Guards the
    // total/GST/EFTPOS/etc. additions to the reject pattern.
    func testStructuralLabels_neverBecomeMerchant() {
        for label in ["TOTAL (Inc GST)", "SUBTOTAL", "TAX INVOICE",
                      "Paid by EFTPOS", "Description", "PURCHASE", "CREDIT ACCOUNT"] {
            let lines: [(text: String, box: CGRect)] = [
                blk(label, x: 0.20, y: 0.90, w: 0.40),
                blk("Amount Due", x: 0.15, y: 0.55, w: 0.15), blk("12.00", x: 0.75, y: 0.55),
            ]
            XCTAssertNotEqual(ReceiptOCRService.extractForTesting(lines).merchant, label,
                              "\"\(label)\" is not a merchant")
        }
    }

    // Berry General Store — the wordmark splits across two lines ("BERRY" /
    // "GENERAL STORE"), "BERRY NSW" leaves a bare "NSW", and the name recurs in
    // the letterhead ("The Berry General Store"). Reported: merchant "NSW".
    // "NSW" is one word so it can't be the recurring-phrase winner; the
    // two-word "General Store" recurs, and its fullest form wins. No place list.
    func testBerryGeneralStore_recurringPhraseWins_notLoneToken() {
        let lines: [(text: String, box: CGRect)] = [
            blk("BERRY", x: 0.35, y: 0.94, w: 0.20),
            blk("GENERAL STORE", x: 0.28, y: 0.92, w: 0.40),
            blk("Get Your Goods", x: 0.32, y: 0.90, w: 0.30),
            blk("23 PRINCE ALFRED ST", x: 0.30, y: 0.885, w: 0.35),
            blk("BERRY", x: 0.40, y: 0.870, w: 0.10),
            blk("NSW", x: 0.55, y: 0.870, w: 0.08),
            blk("The Berry General Store", x: 0.28, y: 0.820, w: 0.45),
            blk("Berry, NSW 2535", x: 0.28, y: 0.790, w: 0.28),
            blk("TOTAL", x: 0.28, y: 0.55, w: 0.10), blk("$44.48", x: 0.66, y: 0.55, w: 0.10),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        let m = result.merchant?.lowercased() ?? ""
        XCTAssertNotEqual(result.merchant, "NSW", "a state is not a merchant")
        XCTAssertTrue(m.contains("berry") && m.contains("general store"),
                      "the full name, not the 'General Store' fragment")
        XCTAssertEqual(result.amount ?? -1, 44.48, accuracy: 0.001)
    }

    // Maw Maw (Kellyville) — the bold shop name "MAW MAW" was OCR-garbled to
    // "MAH MAN" at the top, while the shopping-centre address "KELLYVILLE GROVE"
    // recurs (header line + footer "Kellyville Grove/30"). The recurring-phrase
    // rule then crowned the centre over the shop. Guard: a street/centre address
    // line must never win as merchant. (Clean "Maw Maw" exists only in the footer
    // return-address; recovering it from there is a separate change.)
    func testMawMaw_shoppingCentreAddressNotMerchant() {
        let lines: [(text: String, box: CGRect)] = [
            blk("MAH MAN", x: 0.45, y: 0.850, w: 0.16),
            blk("SHOP T3", x: 0.484, y: 0.831, w: 0.08),
            blk("KELLYVILLE GROVE", x: 0.434, y: 0.811, w: 0.20),
            blk("2A HECTOR COURT", x: 0.430, y: 0.791, w: 0.19),
            blk("KELLYVILLE NSW 2154", x: 0.415, y: 0.770, w: 0.23),
            blk("ABN: 36 686 015 690", x: 0.417, y: 0.703, w: 0.23),
            blk("TAX INVOICE", x: 0.407, y: 0.661, w: 0.26),
            blk("#189682-71 KAW 27-Aug-2026 12:07:18", x: 0.41, y: 0.620, w: 0.34),
            blk("TOTAL", x: 0.291, y: 0.397, w: 0.12), blk("$46.70", x: 0.711, y: 0.400, w: 0.08),
            blk("GST Amount", x: 0.291, y: 0.353, w: 0.12), blk("$4.25", x: 0.724, y: 0.357, w: 0.06),
            blk("EFTPOS", x: 0.294, y: 0.309, w: 0.14), blk("$46.70", x: 0.643, y: 0.313, w: 0.14),
            blk("Maw Maw Kellyville", x: 0.355, y: 0.134, w: 0.215),
            blk("Shop 13 Kellyville Grove/30", x: 0.294, y: 0.106, w: 0.325),
            blk("Severn Vale Road", x: 0.366, y: 0.089, w: 0.192),
            blk("Kellyville NSW 2155", x: 0.342, y: 0.062, w: 0.23),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 46.70, accuracy: 0.001)
        // Vision garbled the bold "MAW MAW" header to "MAH MAN", so the name is
        // recovered from the footer return-address "Maw Maw Kellyville" (suburb
        // "Kellyville" stripped). The centre "KELLYVILLE GROVE" and the suburb line
        // "KELLYVILLE NSW 2154" are both kept out of the running.
        XCTAssertEqual(result.merchant, "Maw Maw")
        // "27-Aug-2026" uses hyphen separators, which the written-date pattern
        // used to reject (spaces/commas only), so the date fell back to Today.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: result.date ?? .distantPast)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 27, "hyphen-separated written date must parse")
    }

    // Auto-note: describe what was bought, not the merchant. The item line is
    // priced; totals/subtotals/surcharges are not items.
    func testNotes_singleItem_becomesTheNote() {
        let lines: [(text: String, box: CGRect)] = [
            // Date/time in the header must not be read as an item, even if a
            // stray number shares its line.
            blk("1 Aug 2026", x: 0.55, y: 0.80, w: 0.20), blk("8:06am", x: 0.55, y: 0.78, w: 0.12),
            blk("Ricotta Hotcakes x 2", x: 0.28, y: 0.70, w: 0.35), blk("$40.00", x: 0.70, y: 0.70),
            blk("($20.00 each)", x: 0.28, y: 0.68, w: 0.20),
            blk("Subtotal", x: 0.28, y: 0.55, w: 0.12), blk("$40.00", x: 0.70, y: 0.55),
            blk("Weekend Surcharge (10%)", x: 0.28, y: 0.52, w: 0.35), blk("$4.00", x: 0.70, y: 0.52),
            blk("Total", x: 0.28, y: 0.48, w: 0.10), blk("$44.48", x: 0.70, y: 0.48),
        ]
        XCTAssertEqual(ReceiptOCRService.extractForTesting(lines).notes, "Ricotta Hotcakes ×2")
    }

    // Totals/surcharges are never items, so a receipt with no line items gives
    // no auto-note rather than "Total".
    func testNotes_onlyTotals_noNote() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Subtotal", x: 0.28, y: 0.55, w: 0.12), blk("$40.00", x: 0.70, y: 0.55),
            blk("Total", x: 0.28, y: 0.48, w: 0.10), blk("$44.48", x: 0.70, y: 0.48),
        ]
        XCTAssertNil(ReceiptOCRService.extractForTesting(lines).notes)
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

    // MARK: - Invoice mode

    // Scorptec order PDF: receipt mode picked the customer ("Joshua Shahinian")
    // as merchant and dumped line items into notes. Invoice mode takes the
    // letterhead vendor, the Grand Total, and a concise order number.
    func testInvoice_scorptec_vendorNotCustomer_grandTotal() {
        let lines: [(text: String, box: CGRect)] = [
            blk("Scorptec Computers", x: 0.15, y: 0.95, w: 0.4),
            blk("Silverwater Store", x: 0.15, y: 0.92, w: 0.4),
            blk("93-95 Derby St, Silverwater, NSW, 2128", x: 0.15, y: 0.90, w: 0.6),
            blk("Order", x: 0.45, y: 0.85, w: 0.1),
            blk("Order No.: 4937644", x: 0.1, y: 0.78, w: 0.4),
            blk("Order Date: 28-08-2026", x: 0.55, y: 0.78, w: 0.4),
            blk("Order Status: NEW", x: 0.55, y: 0.75, w: 0.4),
            blk("Billing Address:", x: 0.1, y: 0.70, w: 0.3),
            blk("Joshua Shahinian", x: 0.1, y: 0.67, w: 0.3),
            blk("Ubiquiti - U7-LITE", x: 0.1, y: 0.55), blk("$358.00", x: 0.8, y: 0.55),
            blk("Subtotal", x: 0.6, y: 0.45), blk("$358.00", x: 0.8, y: 0.45),
            blk("Surcharge", x: 0.6, y: 0.42), blk("$3.58", x: 0.8, y: 0.42),
            blk("Grand Total", x: 0.6, y: 0.39), blk("$361.58", x: 0.8, y: 0.39),
        ]
        let result = ReceiptOCRService.extractInvoiceForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 361.58, accuracy: 0.001, "Grand Total, not a line price")
        XCTAssertEqual(result.merchant, "Scorptec Computers", "vendor letterhead, not the customer")
        XCTAssertNotEqual(result.merchant, "Joshua Shahinian", "billing name is not the vendor")
        XCTAssertEqual(result.notes, "Order 4937644", "concise order number, not a line-item dump")
    }

    // MARK: - International receipts (Tally is global, not AU-only)

    // Iceland — Bónus. ISK has no minor unit and prints "." as the thousands
    // separator, so the total "4.031" is 4031 krónur, not 4.03.
    func testBonus_iceland_dotThousands_notCents() {
        let lines: [(text: String, box: CGRect)] = [
            ("BÓNUS", CGRect(x: 0.18, y: 0.94, width: 0.30, height: 0.032)),
            ("Bónus Skipholti", CGRect(x: 0.30, y: 0.88, width: 0.26, height: 0.012)),
            ("gunry handsápa 500 m", CGRect(x: 0.10, y: 0.60, width: 0.5, height: 0.012)),
            ("198", CGRect(x: 0.78, y: 0.60, width: 0.08, height: 0.012)),
            ("Samtals kr", CGRect(x: 0.10, y: 0.30, width: 0.25, height: 0.013)),
            ("4.031", CGRect(x: 0.76, y: 0.30, width: 0.12, height: 0.013)),
            ("Greiðslukort", CGRect(x: 0.10, y: 0.28, width: 0.25, height: 0.013)),
            ("-4.031", CGRect(x: 0.74, y: 0.28, width: 0.14, height: 0.013)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 4031, accuracy: 0.5, "dot = thousands in ISK, not cents")
    }

    // US — Jack in the Box. The topmost line is "Drive-Thru Order# 1044"; the
    // merchant is the line below. Total $39.09 (subtotal $36.36 + tax $2.73); the
    // "(4 @ 3.49)" is a unit rate, not the amount.
    func testJackInTheBox_orderNumberLineNotMerchant() {
        let lines: [(text: String, box: CGRect)] = [
            ("Drive-Thru Order# 1044", CGRect(x: 0.24, y: 0.95, width: 0.5, height: 0.013)),
            ("Jack In The Box - #6570", CGRect(x: 0.24, y: 0.935, width: 0.5, height: 0.013)),
            ("1610 Capital Cir NE", CGRect(x: 0.28, y: 0.92, width: 0.42, height: 0.012)),
            ("Tallahassee, FL 32308", CGRect(x: 0.30, y: 0.905, width: 0.38, height: 0.012)),
            ("ULT BRKFST JACK (4 @ 3.49)", CGRect(x: 0.10, y: 0.62, width: 0.5, height: 0.012)),
            ("$36.36", CGRect(x: 0.80, y: 0.62, width: 0.12, height: 0.012)),
            ("Subtotal", CGRect(x: 0.10, y: 0.50, width: 0.2, height: 0.012)),
            ("$36.36", CGRect(x: 0.80, y: 0.50, width: 0.12, height: 0.012)),
            ("FL Sales Tax", CGRect(x: 0.10, y: 0.47, width: 0.25, height: 0.012)),
            ("$2.73", CGRect(x: 0.80, y: 0.47, width: 0.10, height: 0.012)),
            ("Total", CGRect(x: 0.10, y: 0.44, width: 0.15, height: 0.012)),
            ("$39.09", CGRect(x: 0.80, y: 0.44, width: 0.12, height: 0.012)),
            ("Visa Tendered", CGRect(x: 0.10, y: 0.41, width: 0.25, height: 0.012)),
            ("$39.09", CGRect(x: 0.80, y: 0.41, width: 0.12, height: 0.012)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 39.09, accuracy: 0.001)
        XCTAssertNotEqual(result.merchant, "Drive-Thru Order", "the order line is not the merchant")
    }

    // US — Trader Joe's. No "TOTAL" label; the bill is "Balance to pay" / card, both
    // $81.87. The "Tax: $66.63 @ 1.8%" line is a taxable base @ rate, not the total.
    func testTraderJoes_balanceToPay_notTaxBase() {
        let lines: [(text: String, box: CGRect)] = [
            ("TRADER JOE'S", CGRect(x: 0.28, y: 0.94, width: 0.42, height: 0.020)),
            ("Tempe, AZ  85281", CGRect(x: 0.30, y: 0.90, width: 0.38, height: 0.011)),
            ("GRANOLA PROTEIN PEANUT B", CGRect(x: 0.10, y: 0.62, width: 0.5, height: 0.011)),
            ("$3.99", CGRect(x: 0.80, y: 0.62, width: 0.10, height: 0.011)),
            ("Tax: $66.63 @ 1.8%", CGRect(x: 0.10, y: 0.40, width: 0.4, height: 0.011)),
            ("$1.20", CGRect(x: 0.80, y: 0.40, width: 0.10, height: 0.011)),
            ("Balance to pay", CGRect(x: 0.10, y: 0.35, width: 0.3, height: 0.012)),
            ("$81.87", CGRect(x: 0.80, y: 0.35, width: 0.12, height: 0.012)),
            ("MasterCard", CGRect(x: 0.10, y: 0.32, width: 0.25, height: 0.012)),
            ("$81.87", CGRect(x: 0.80, y: 0.32, width: 0.12, height: 0.012)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 81.87, accuracy: 0.001, "balance, not the tax base $66.63")
    }

    // US — Meijer. The savings block up top ("SAVINGS TOTAL 2.00") must not become
    // the amount; the store brand recurs on item lines ("MEIJER MILK/EGGS") but is
    // one word so it can't hijack the merchant. Total 18.80.
    func testMeijer_savingsNotAmount_brandRecurrenceHarmless() {
        let lines: [(text: String, box: CGRect)] = [
            ("meijer", CGRect(x: 0.34, y: 0.95, width: 0.30, height: 0.024)),
            ("SPECIALS", CGRect(x: 0.20, y: 0.80, width: 0.2, height: 0.012)),
            ("2.00", CGRect(x: 0.60, y: 0.80, width: 0.08, height: 0.012)),
            ("SAVINGS TOTAL", CGRect(x: 0.10, y: 0.78, width: 0.3, height: 0.012)),
            ("2.00", CGRect(x: 0.60, y: 0.78, width: 0.08, height: 0.012)),
            ("MEIJER MILK", CGRect(x: 0.20, y: 0.60, width: 0.3, height: 0.012)),
            ("2.69", CGRect(x: 0.60, y: 0.60, width: 0.08, height: 0.012)),
            ("MEIJER EGGS", CGRect(x: 0.20, y: 0.58, width: 0.3, height: 0.012)),
            ("3.99", CGRect(x: 0.60, y: 0.58, width: 0.08, height: 0.012)),
            ("TOTAL", CGRect(x: 0.10, y: 0.40, width: 0.15, height: 0.012)),
            ("18.80", CGRect(x: 0.60, y: 0.40, width: 0.1, height: 0.012)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.amount ?? -1, 18.80, accuracy: 0.001, "total, not the $2.00 savings")
    }

    // US — a store whose city recurs beside a US state code ("NORTH LAS VEGAS NV" in
    // the address and again in the EFTPOS footer) must not beat the wordmark. Proves
    // the recurring-place guard isn't Australia-only.
    func testUSCity_recurringBesideStateCode_wordmarkWins() {
        let lines: [(text: String, box: CGRect)] = [
            ("Walmart", CGRect(x: 0.30, y: 0.94, width: 0.34, height: 0.030)),
            ("5940 LOSEE RD", CGRect(x: 0.28, y: 0.90, width: 0.30, height: 0.012)),
            ("NORTH LAS VEGAS NV 89081", CGRect(x: 0.22, y: 0.885, width: 0.52, height: 0.012)),
            ("TOTAL", CGRect(x: 0.10, y: 0.55, width: 0.12, height: 0.013)),
            ("35.36", CGRect(x: 0.80, y: 0.55, width: 0.10, height: 0.013)),
            ("WALMART", CGRect(x: 0.20, y: 0.40, width: 0.14, height: 0.013)),
            ("NORTH LAS VEGAS", CGRect(x: 0.44, y: 0.40, width: 0.22, height: 0.013)),
            ("NV", CGRect(x: 0.70, y: 0.399, width: 0.05, height: 0.013)),
        ]
        let result = ReceiptOCRService.extractForTesting(lines)
        XCTAssertEqual(result.merchant, "Walmart", "wordmark, not the recurring US city")
        XCTAssertEqual(result.amount ?? -1, 35.36, accuracy: 0.001)
    }
}
