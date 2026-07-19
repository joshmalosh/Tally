import XCTest
@testable import Tally

/// Pins the free-tier limits. These numbers are commercial decisions recorded in
/// MONETISATION_BRIEF.md — the tests exist so a refactor can't quietly move them
/// again, which is exactly how the CSV allowance ended up meaning 2, 1, or 0
/// depending on which button the user pressed.
final class MonetisationGatingTests: XCTestCase {

    private let keys = [
        "csvExportCount", "csvExportMonth",
        "ocrScanCount", "ocrScanMonth",
        "debugForcePro", "upgradePromptLastShown", "firstLaunchDate"
    ]

    private func makeFreeAppState() -> AppState {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        let state = AppState()
        state.subscriptionStatus = .free
        #if DEBUG
        state.debugForcePro = false
        #endif
        return state
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - CSV export

    func testFreeTierGetsExactlyOneCSVExportPerMonth() {
        let state = makeFreeAppState()

        XCTAssertTrue(state.canExportCSV)
        state.recordCSVExport()
        XCTAssertFalse(state.canExportCSV, "Free tier is 1 CSV export per month, not 2")
    }

    func testProHasUnlimitedCSVExports() {
        let state = makeFreeAppState()
        state.subscriptionStatus = .pro

        for _ in 0..<5 { state.recordCSVExport() }
        XCTAssertTrue(state.canExportCSV)
    }

    // MARK: - OCR scan quota

    func testFreeTierGetsTenUsableScansAndIsBlockedOnTheEleventh() {
        let state = makeFreeAppState()

        for i in 0..<10 {
            XCTAssertTrue(state.canUseOCR, "Scan \(i + 1) of 10 should be allowed")
            state.recordOCRScan(extractedAmount: true)
        }
        XCTAssertFalse(state.canUseOCR, "The 11th scan is the one that gets blocked")
        XCTAssertEqual(state.ocrScansThisMonth, 10)
    }

    func testFailedScanDoesNotConsumeQuota() {
        let state = makeFreeAppState()

        // A scan that couldn't read an amount left the user typing the number
        // themselves — charging for it would make the allowance feel like a scam.
        for _ in 0..<20 { state.recordOCRScan(extractedAmount: false) }

        XCTAssertEqual(state.ocrScansThisMonth, 0)
        XCTAssertTrue(state.canUseOCR)
        XCTAssertEqual(state.ocrScansRemaining, 10)
    }

    func testScansRemainingCountsDown() {
        let state = makeFreeAppState()

        XCTAssertEqual(state.ocrScansRemaining, 10)
        state.recordOCRScan(extractedAmount: true)
        XCTAssertEqual(state.ocrScansRemaining, 9)
    }

    func testProScansAreNeverMetered() {
        let state = makeFreeAppState()
        state.subscriptionStatus = .pro

        for _ in 0..<50 { state.recordOCRScan(extractedAmount: true) }

        XCTAssertTrue(state.canUseOCR)
        XCTAssertEqual(state.ocrScansThisMonth, 0, "Pro scans shouldn't even be counted")
    }

    // MARK: - Daily upgrade prompt

    func testUpgradePromptSuppressedDuringFirstThreeDays() {
        let state = makeFreeAppState()
        UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")

        XCTAssertFalse(state.shouldShowUpgradePrompt,
                       "Prompting before the app has proved itself taints the first impression")
    }

    func testUpgradePromptShowsAfterGraceThenEveryThreeDays() {
        let state = makeFreeAppState()
        let cal = Calendar.current
        UserDefaults.standard.set(cal.date(byAdding: .day, value: -4, to: Date())!,
                                  forKey: "firstLaunchDate")

        XCTAssertTrue(state.shouldShowUpgradePrompt)

        state.recordUpgradePromptShown()
        XCTAssertFalse(state.shouldShowUpgradePrompt, "Not again the same day")

        UserDefaults.standard.set(cal.date(byAdding: .day, value: -3, to: Date())!,
                                  forKey: "upgradePromptLastShown")
        XCTAssertTrue(state.shouldShowUpgradePrompt, "Due again after 3 days")
    }

    func testProNeverSeesUpgradePrompt() {
        let state = makeFreeAppState()
        state.subscriptionStatus = .pro
        UserDefaults.standard.set(Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
                                  forKey: "firstLaunchDate")

        XCTAssertFalse(state.shouldShowUpgradePrompt)
    }
}
