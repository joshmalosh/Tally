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

// MARK: - TagSuggestionEngine Tests

final class TagSuggestionEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a non-persistent TagModel for testing without a ModelContainer.
    private func makeTag(name: String, isSystem: Bool = false) -> TagModel {
        let t = TagModel(name: name)
        t.isSystemTag = isSystem
        return t
    }

    // MARK: - No match

    func testSuggest_emptyCorpus_returnsNil() {
        let tags = [makeTag(name: "Dining")]
        XCTAssertNil(TagSuggestionEngine.suggest(merchant: "", notes: "", tags: tags))
    }

    func testSuggest_noMatchingTag_returnsNil() {
        // "coffee" should match dining rule, but no matching tag exists
        let tags = [makeTag(name: "Travel")]
        XCTAssertNil(TagSuggestionEngine.suggest(merchant: "Starbucks Coffee", notes: "", tags: tags))
    }

    func testSuggest_noTags_returnsNil() {
        XCTAssertNil(TagSuggestionEngine.suggest(merchant: "Uber", notes: "", tags: []))
    }

    // MARK: - Dining / Food

    func testSuggest_restaurantMerchant_matchesDiningTag() {
        let tags = [makeTag(name: "Dining"), makeTag(name: "Travel")]
        let result = TagSuggestionEngine.suggest(merchant: "Thai restaurant", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Dining")
    }

    func testSuggest_coffeeShop_matchesMealsTag() {
        let tags = [makeTag(name: "Meals"), makeTag(name: "Work")]
        let result = TagSuggestionEngine.suggest(merchant: "Bluestone Lane Coffee", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Meals")
    }

    func testSuggest_uberEats_matchesFoodTag() {
        let tags = [makeTag(name: "Food"), makeTag(name: "Shopping")]
        let result = TagSuggestionEngine.suggest(merchant: "UberEats order", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Food")
    }

    // MARK: - Transport

    func testSuggest_uberRide_matchesTransportTag() {
        let tags = [makeTag(name: "Transport"), makeTag(name: "Dining")]
        let result = TagSuggestionEngine.suggest(merchant: "Uber", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Transport")
    }

    func testSuggest_petrolStation_matchesTransportTag() {
        let tags = [makeTag(name: "Dining"), makeTag(name: "Travel")]
        let result = TagSuggestionEngine.suggest(merchant: "BP Petrol Station", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Travel")
    }

    // MARK: - Subscriptions

    func testSuggest_netflixNote_matchesSubscriptionsTag() {
        let tags = [makeTag(name: "Subscriptions"), makeTag(name: "Dining")]
        let result = TagSuggestionEngine.suggest(merchant: "", notes: "Netflix monthly subscription", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Subscriptions")
    }

    func testSuggest_spotifyMerchant_matchesStreamingTag() {
        let tags = [makeTag(name: "Streaming"), makeTag(name: "Work")]
        let result = TagSuggestionEngine.suggest(merchant: "Spotify", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Streaming")
    }

    // MARK: - Groceries

    func testSuggest_woolworths_matchesGroceriesTag() {
        let tags = [makeTag(name: "Groceries"), makeTag(name: "Dining")]
        let result = TagSuggestionEngine.suggest(merchant: "Woolworths", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Groceries")
    }

    // MARK: - Reason string

    func testSuggest_reasonIsNonEmpty() {
        let tags = [makeTag(name: "Dining")]
        let result = TagSuggestionEngine.suggest(merchant: "pizza place", notes: "", tags: tags)
        XCTAssertFalse(result?.reason.isEmpty ?? true)
    }

    // MARK: - System tag preference

    func testSuggest_prefersNonSystemTagOverSystemTag() {
        // System tag should be used as fallback only; non-system tag with same hint wins
        let systemTag  = makeTag(name: "Dining", isSystem: true)
        let userTag    = makeTag(name: "My Dining", isSystem: false)
        let tags = [systemTag, userTag]
        let result = TagSuggestionEngine.suggest(merchant: "cafe brunch", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.tag.isSystemTag ?? true, "Should prefer non-system tag")
    }

    // MARK: - Corpus merging

    func testSuggest_matchFromNotes_whenMerchantIsEmpty() {
        let tags = [makeTag(name: "Health")]
        let result = TagSuggestionEngine.suggest(merchant: "", notes: "dentist appointment payment", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Health")
    }

    func testSuggest_matchFromMerchant_whenNotesIsEmpty() {
        let tags = [makeTag(name: "Utilities")]
        let result = TagSuggestionEngine.suggest(merchant: "Electricity bill", notes: "", tags: tags)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tag.name, "Utilities")
    }
}
