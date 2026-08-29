import XCTest
@testable import Tally

/// Guards the statement-line parser. Grows like the OCR corpus: every real
/// statement that parses wrong becomes a case here before the fix.
final class StatementParserTests: XCTestCase {

    private func lines(_ text: String) -> [StatementLine] {
        StatementParser.parse(text)
    }

    // A running-balance column must not be mistaken for the transaction amount.
    func testBalanceColumnNotTakenAsAmount() {
        let out = lines("12/03/2026  WOOLWORTHS 1234  38.80  1,204.55")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.amountCents, 3880)
        XCTAssertTrue(out.first?.description.contains("WOOLWORTHS") ?? false)
        XCTAssertTrue(out.first?.isDebit ?? false)
    }

    // The leading date column becomes the row's date, not part of the description.
    func testLeadingDateParsed() {
        let out = lines("03/03/2026  AMAZON MARKETPLACE  -42.50")
        XCTAssertEqual(out.count, 1)
        let cal = Calendar.current
        let d = out[0].date
        XCTAssertEqual(cal.component(.day, from: d), 3)
        XCTAssertEqual(cal.component(.month, from: d), 3)
        XCTAssertEqual(cal.component(.year, from: d), 2026)
        XCTAssertEqual(out[0].amountCents, 4250)
        XCTAssertFalse(out[0].description.contains("03/03"))
        XCTAssertTrue(out[0].isDebit)
    }

    // CR / + mark a credit (money in) — kept as a line but flagged not-debit so
    // the import filter drops it.
    func testCreditIsNotDebit() {
        let cr = lines("05/03/2026  SALARY PAYMENT  2,500.00 CR")
        XCTAssertEqual(cr.count, 1)
        XCTAssertFalse(cr[0].isDebit)

        let plus = lines("06/03/2026  REFUND  15.00+")
        XCTAssertEqual(plus.count, 1)
        XCTAssertFalse(plus[0].isDebit)
    }

    // A plain debit with no per-line balance.
    func testSingleAmountLine() {
        let out = lines("01/03/2026  NETFLIX  15.99")
        XCTAssertEqual(out.first?.amountCents, 1599)
        XCTAssertTrue(out.first?.isDebit ?? false)
    }

    // Header/footer noise is skipped, not parsed as an expense.
    func testNoiseSkipped() {
        let text = """
        Opening Balance  1,000.00
        Statement period 01/03/2026 to 31/03/2026
        02/03/2026  COFFEE HOUSE  6.40
        Closing Balance  993.60
        """
        let out = lines(text)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.amountCents, 640)
    }

    // Textual dates (dd MMM) parse; a missing year rolls to the current year.
    func testTextualDate() {
        let out = lines("15 Aug  BINTANG SUPERMARKET  42.00")
        XCTAssertEqual(out.count, 1)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: out[0].date), 15)
        XCTAssertEqual(cal.component(.month, from: out[0].date), 8)
        // Year-less dates take the current year, not DateFormatter's 2000 default.
        XCTAssertEqual(cal.component(.year, from: out[0].date), cal.component(.year, from: Date()))
        XCTAssertEqual(out[0].amountCents, 4200)
    }

    // A line with no date isn't a transaction.
    func testNonTransactionLineIgnored() {
        XCTAssertTrue(lines("Thank you for banking with us").isEmpty)
    }
}
