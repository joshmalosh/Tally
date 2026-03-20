import XCTest
@testable import Tally

final class CurrencyFormatterTests: XCTestCase {

    let formatter = CurrencyFormatter.shared

    // MARK: - Basic Formatting

    func testFormat_zeroCents() {
        let result = formatter.format(cents: 0, currencyCode: "USD")
        XCTAssertTrue(result.contains("0"), "Expected result to contain 0, got: \(result)")
    }

    func testFormat_oneDollar() {
        let result = formatter.format(cents: 100, currencyCode: "USD")
        XCTAssertTrue(result.contains("1.00") || result.contains("1,00"), "Expected 1.00, got: \(result)")
    }

    func testFormat_centsOnly() {
        let result = formatter.format(cents: 50, currencyCode: "USD")
        XCTAssertTrue(result.contains("0.50") || result.contains("0,50"), "Expected 0.50, got: \(result)")
    }

    func testFormat_largeAmount() {
        let result = formatter.format(cents: 999999, currencyCode: "USD")
        XCTAssertTrue(result.contains("9,999.99") || result.contains("9.999,99") || result.contains("9999.99"),
                       "Expected ~9999.99, got: \(result)")
    }

    func testFormat_singleCent() {
        let result = formatter.format(cents: 1, currencyCode: "USD")
        XCTAssertTrue(result.contains("0.01") || result.contains("0,01"), "Expected 0.01, got: \(result)")
    }

    // MARK: - No-Decimal Currencies

    func testFormat_JPY_noDecimals() {
        let result = formatter.format(cents: 500, currencyCode: "JPY")
        XCTAssertTrue(result.contains("500"), "JPY should show 500, got: \(result)")
        XCTAssertFalse(result.contains(".00"), "JPY should not have decimals, got: \(result)")
    }

    func testFormat_KRW_noDecimals() {
        let result = formatter.format(cents: 10000, currencyCode: "KRW")
        XCTAssertTrue(result.contains("10,000") || result.contains("10000"), "KRW should show 10000, got: \(result)")
    }

    // MARK: - Compact Formatting

    func testFormatCompact_smallAmount_usesFullFormat() {
        let result = formatter.formatCompact(cents: 5000, currencyCode: "USD")
        XCTAssertTrue(result.contains("50"), "Small amount should use full format, got: \(result)")
    }

    func testFormatCompact_tenThousandPlus_showsK() {
        let result = formatter.formatCompact(cents: 1_500_000, currencyCode: "USD")
        XCTAssertTrue(result.contains("15") && result.contains("K"),
                       "Expected 15K for $15,000, got: \(result)")
    }

    func testFormatCompact_millionPlus_showsM() {
        let result = formatter.formatCompact(cents: 250_000_000, currencyCode: "USD")
        XCTAssertTrue(result.contains("2.5") && result.contains("M"),
                       "Expected 2.5M for $2.5M, got: \(result)")
    }

    func testFormatCompact_justUnderTenK_usesFullFormat() {
        let result = formatter.formatCompact(cents: 999_999, currencyCode: "USD")
        XCTAssertFalse(result.contains("K"), "Under 10K should not show K, got: \(result)")
    }

    // MARK: - Default Currency

    func testFormat_defaultCurrencyIsUSD() {
        let result = formatter.format(cents: 100)
        XCTAssertTrue(result.contains("1"), "Default should format as USD, got: \(result)")
    }

    // MARK: - Edge Cases

    func testFormat_veryLargeAmount() {
        let result = formatter.format(cents: 99_999_999, currencyCode: "USD")
        XCTAssertTrue(result.contains("999,999.99") || result.contains("999999.99") || result.contains("999.999,99"),
                       "Large amount formatting failed, got: \(result)")
    }
}
