import XCTest
@testable import Tally

// Only `sortedByDate` and `generateCSV` remain on `ExpenseCalculations`; the
// monthlyTotal / groupByTag / filterByDateRange / filterByTag / filterByGroup
// helpers (and the `MonthlyTotal` struct) were unused dead code and were removed
// in the 2026-08-25 ponytail audit, so their tests are gone with them.
final class ExpenseCalculationsTests: XCTestCase {

    // MARK: - Sort By Date

    func testSortedByDate_descendingDefault() {
        let early = TestData.date(year: 2026, month: 1, day: 1)
        let late = TestData.date(year: 2026, month: 3, day: 1)
        let expenses = [
            TestData.expense(id: "1", date: early),
            TestData.expense(id: "2", date: late),
        ]
        let result = ExpenseCalculations.sortedByDate(expenses: expenses)
        XCTAssertEqual(result.first?.id, "2")
        XCTAssertEqual(result.last?.id, "1")
    }

    func testSortedByDate_ascending() {
        let early = TestData.date(year: 2026, month: 1, day: 1)
        let late = TestData.date(year: 2026, month: 3, day: 1)
        let expenses = [
            TestData.expense(id: "2", date: late),
            TestData.expense(id: "1", date: early),
        ]
        let result = ExpenseCalculations.sortedByDate(expenses: expenses, ascending: true)
        XCTAssertEqual(result.first?.id, "1")
        XCTAssertEqual(result.last?.id, "2")
    }

    func testSortedByDate_excludesDeleted() {
        let expenses = [
            TestData.expense(id: "1", date: TestData.date(year: 2026, month: 1, day: 1)),
            TestData.expense(id: "2", date: TestData.date(year: 2026, month: 2, day: 1), deletedAt: Date()),
        ]
        let result = ExpenseCalculations.sortedByDate(expenses: expenses)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }

    func testSortedByDate_emptyInput() {
        XCTAssertTrue(ExpenseCalculations.sortedByDate(expenses: []).isEmpty)
    }

    // MARK: - CSV Generation

    func testGenerateCSV_headerOnly_whenEmpty() {
        let csv = ExpenseCalculations.generateCSV(expenses: [], tags: [])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("groups,tags"))
    }

    func testGenerateCSV_singleExpense() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            amountCents: 4999,
            date: date,
            description: "Lunch",
            merchant: "Cafe",
            tagIds: ["tag-1"],
            source: .manual,
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("49.99"))
        XCTAssertTrue(lines[1].contains("Meals"))
        XCTAssertTrue(lines[1].contains("Lunch"))
        XCTAssertTrue(lines[1].contains("Cafe"))
        XCTAssertFalse(lines[0].contains("source"))
        XCTAssertFalse(lines[0].contains("attachment_filename"))
        XCTAssertTrue(lines[0].contains("receipt"))
    }

    func testGenerateCSV_sortsByDateAscending() {
        let early = TestData.date(year: 2026, month: 1, day: 1)
        let late = TestData.date(year: 2026, month: 3, day: 1)
        let expenses = [
            TestData.expense(id: "late", date: late, description: "Late", tagIds: ["tag-1"], createdAt: late),
            TestData.expense(id: "early", date: early, description: "Early", tagIds: ["tag-1"], createdAt: early),
        ]
        let tags = [TestData.tag(id: "tag-1", name: "Travel")]
        let csv = ExpenseCalculations.generateCSV(expenses: expenses, tags: tags)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[1].contains("Early"))
        XCTAssertTrue(lines[2].contains("Late"))
    }

    func testGenerateCSV_excludesDeleted() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expenses = [
            TestData.expense(id: "1", date: date, description: "Keep", tagIds: ["tag-1"], createdAt: date),
            TestData.expense(id: "2", date: date, description: "Deleted", tagIds: ["tag-1"], createdAt: date, deletedAt: Date()),
        ]
        let tags = [TestData.tag(id: "tag-1", name: "Other")]
        let csv = ExpenseCalculations.generateCSV(expenses: expenses, tags: tags)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Keep"))
    }

    func testGenerateCSV_escapesCommasInFields() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            date: date,
            description: "Food, drinks, and tips",
            tagIds: ["tag-1"],
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        XCTAssertTrue(csv.contains("\"Food, drinks, and tips\""))
    }

    func testGenerateCSV_escapesQuotesInFields() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            date: date,
            description: "The \"best\" lunch",
            tagIds: ["tag-1"],
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        XCTAssertTrue(csv.contains("\"The \"\"best\"\" lunch\""))
    }

    func testGenerateCSV_missingTag_showsUntagged() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(date: date, tagIds: ["nonexistent"], createdAt: date)
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: [])
        XCTAssertTrue(csv.contains("Untagged"))
    }

    func testGenerateCSV_includesGroupColumn() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            amountCents: 2500,
            date: date,
            description: "Printer ink",
            tagIds: ["child-1"],
            source: .manual,
            createdAt: date
        )
        let tags = [
            TestData.tag(id: "group-1", name: "Projects"),
            TestData.tag(id: "child-1", name: "Office Renovation", parentId: "group-1"),
        ]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].contains("groups,tags"))
        XCTAssertTrue(lines[1].contains("Projects"))
        XCTAssertTrue(lines[1].contains("Office Renovation"))
    }

    func testGenerateCSV_noGroup_emptyGroupColumn() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            amountCents: 1000,
            date: date,
            description: "Lunch",
            tagIds: ["tag-1"],
            source: .manual,
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[1].contains(",Meals,"))
    }

    func testGenerateCSV_multipleTagsPerExpense() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            amountCents: 3000,
            date: date,
            description: "Conference booking",
            tagIds: ["child-1", "tag-travel"],
            source: .manual,
            createdAt: date
        )
        let tags = [
            TestData.tag(id: "group-1", name: "Projects"),
            TestData.tag(id: "child-1", name: "Office Renovation", parentId: "group-1"),
            TestData.tag(id: "tag-travel", name: "Travel"),
        ]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        XCTAssertTrue(csv.contains("Office Renovation; Travel"))
        XCTAssertTrue(csv.contains("Projects"))
    }

    func testGenerateCSV_receiptFilenameMapping() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            id: "exp-1",
            amountCents: 1500,
            date: date,
            description: "Coffee",
            tagIds: ["tag-1"],
            attachmentKey: "exp-1.jpg",
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let receiptFilenames = ["exp-1": "receipts/001_coffee.jpg"]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags, receiptFilenames: receiptFilenames)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[1].contains("receipts/001_coffee.jpg"))
    }

    func testGenerateCSV_noReceiptMapping_emptyColumn() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expense = TestData.expense(
            id: "exp-1",
            amountCents: 1500,
            date: date,
            description: "Coffee",
            tagIds: ["tag-1"],
            createdAt: date
        )
        let tags = [TestData.tag(id: "tag-1", name: "Meals")]
        let csv = ExpenseCalculations.generateCSV(expenses: [expense], tags: tags)
        let lines = csv.components(separatedBy: "\n")
        let columns = lines[1].components(separatedBy: ",")
        let receiptIndex = lines[0].components(separatedBy: ",").firstIndex(of: "receipt")!
        XCTAssertEqual(columns[receiptIndex], "")
    }

    func testGenerateCSV_amountFormatting() {
        let date = TestData.date(year: 2026, month: 2, day: 15)
        let expenses = [
            TestData.expense(id: "1", amountCents: 100, date: date, tagIds: ["tag-1"], createdAt: date),
            TestData.expense(id: "2", amountCents: 0, date: date, tagIds: ["tag-1"], createdAt: date),
            TestData.expense(id: "3", amountCents: 99999, date: date, tagIds: ["tag-1"], createdAt: date),
        ]
        let tags = [TestData.tag(id: "tag-1", name: "Other")]
        let csv = ExpenseCalculations.generateCSV(expenses: expenses, tags: tags)
        XCTAssertTrue(csv.contains("1.00"))
        XCTAssertTrue(csv.contains("0.00"))
        XCTAssertTrue(csv.contains("999.99"))
    }
}
