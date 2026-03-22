import XCTest
@testable import Tally

final class ExpenseTypesTests: XCTestCase {

    // MARK: - Expense

    func testExpense_identifiable() {
        let e = TestData.expense(id: "test-id")
        XCTAssertEqual(e.id, "test-id")
    }

    func testExpense_defaultsOptionalFieldsToNil() {
        let e = TestData.expense()
        XCTAssertNil(e.description)
        XCTAssertNil(e.merchant)
        XCTAssertNil(e.notes)
        XCTAssertNil(e.attachmentKey)
        XCTAssertNil(e.deletedAt)
    }

    func testExpense_codable() throws {
        let original = TestData.expense(
            id: "enc-1",
            amountCents: 4250,
            currency: "EUR",
            description: "Hotel",
            merchant: "Marriott",
            source: .upload
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Expense.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.amountCents, 4250)
        XCTAssertEqual(decoded.currency, "EUR")
        XCTAssertEqual(decoded.description, "Hotel")
        XCTAssertEqual(decoded.merchant, "Marriott")
        XCTAssertEqual(decoded.source, .upload)
    }

    // MARK: - ExpenseSource

    func testExpenseSource_allCases() {
        XCTAssertEqual(ExpenseSource.allCases.count, 3)
        XCTAssertTrue(ExpenseSource.allCases.contains(.camera))
        XCTAssertTrue(ExpenseSource.allCases.contains(.upload))
        XCTAssertTrue(ExpenseSource.allCases.contains(.manual))
    }

    func testExpenseSource_rawValues() {
        XCTAssertEqual(ExpenseSource.camera.rawValue, "camera")
        XCTAssertEqual(ExpenseSource.upload.rawValue, "upload")
        XCTAssertEqual(ExpenseSource.manual.rawValue, "manual")
    }

    func testExpenseSource_decodable() throws {
        let json = Data(#""camera""#.utf8)
        let source = try JSONDecoder().decode(ExpenseSource.self, from: json)
        XCTAssertEqual(source, .camera)
    }

    // MARK: - Tag

    func testTag_codable() throws {
        let original = TestData.tag(id: "t1", name: "Travel", colorId: "teal", sortOrder: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Tag.self, from: data)
        XCTAssertEqual(decoded.id, "t1")
        XCTAssertEqual(decoded.name, "Travel")
        XCTAssertEqual(decoded.colorId, "teal")
        XCTAssertEqual(decoded.sortOrder, 3)
    }

    // MARK: - TagModel Defaults

    func testTagModel_defaultsHaveFourEntries() {
        XCTAssertEqual(TagModel.defaults.count, 4)
    }

    func testTagModel_defaultNames() {
        let names = TagModel.defaults.map(\.name)
        XCTAssertEqual(names, ["Travel", "Petrol", "Meals", "Subscriptions"])
    }

    func testTagModel_defaultSortOrderSequential() {
        let orders = TagModel.defaults.map(\.sortOrder)
        XCTAssertEqual(orders, Array(0..<4))
    }

    // MARK: - TagColors

    func testTagColors_paletteHas30Colors() {
        XCTAssertEqual(TagColors.palette.count, 30)
    }

    func testTagColors_forId_returnsCorrectColor() {
        let mint = TagColors.forId("v2")
        XCTAssertEqual(mint.primary, "3D9E6A")
    }

    func testTagColors_forId_fallsBackToMint() {
        let fallback = TagColors.forId("nonexistent")
        XCTAssertEqual(fallback.id, "v2")
    }

    func testTagColors_defaultTagColors_hasFourEntries() {
        XCTAssertEqual(TagColors.defaultTagColors.count, 4)
        XCTAssertEqual(TagColors.defaultTagColors["Travel"], "v7")
        XCTAssertEqual(TagColors.defaultTagColors["Subscriptions"], "v13")
    }
}
