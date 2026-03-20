import XCTest
@testable import Tally

final class ExpenseCalculationsTests: XCTestCase {

    // MARK: - Monthly Total

    func testMonthlyTotal_emptyExpenses_returnsZero() {
        let result = ExpenseCalculations.monthlyTotal(expenses: [], month: Date(), currency: "USD")
        XCTAssertEqual(result.totalCents, 0)
        XCTAssertEqual(result.expenseCount, 0)
        XCTAssertEqual(result.currency, "USD")
    }

    func testMonthlyTotal_singleExpense() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 15)
        let expenses = [TestData.expense(amountCents: 5000, date: feb2026)]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 5000)
        XCTAssertEqual(result.expenseCount, 1)
    }

    func testMonthlyTotal_multipleExpenses_sumsCorrectly() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 10)
        let expenses = [
            TestData.expense(id: "1", amountCents: 1000, date: TestData.date(year: 2026, month: 2, day: 1)),
            TestData.expense(id: "2", amountCents: 2500, date: TestData.date(year: 2026, month: 2, day: 15)),
            TestData.expense(id: "3", amountCents: 3000, date: TestData.date(year: 2026, month: 2, day: 28)),
        ]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 6500)
        XCTAssertEqual(result.expenseCount, 3)
    }

    func testMonthlyTotal_excludesDifferentMonth() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 10)
        let expenses = [
            TestData.expense(id: "1", amountCents: 1000, date: TestData.date(year: 2026, month: 2, day: 5)),
            TestData.expense(id: "2", amountCents: 2000, date: TestData.date(year: 2026, month: 3, day: 1)),
            TestData.expense(id: "3", amountCents: 3000, date: TestData.date(year: 2026, month: 1, day: 31)),
        ]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 1000)
        XCTAssertEqual(result.expenseCount, 1)
    }

    func testMonthlyTotal_excludesDeletedExpenses() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 10)
        let expenses = [
            TestData.expense(id: "1", amountCents: 1000, date: feb2026),
            TestData.expense(id: "2", amountCents: 2000, date: feb2026, deletedAt: Date()),
        ]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 1000)
        XCTAssertEqual(result.expenseCount, 1)
    }

    func testMonthlyTotal_excludesDifferentCurrency() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 10)
        let expenses = [
            TestData.expense(id: "1", amountCents: 1000, currency: "USD", date: feb2026),
            TestData.expense(id: "2", amountCents: 2000, currency: "EUR", date: feb2026),
        ]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 1000)
        XCTAssertEqual(result.expenseCount, 1)
    }

    func testMonthlyTotal_zeroAmount_counted() {
        let feb2026 = TestData.date(year: 2026, month: 2, day: 10)
        let expenses = [TestData.expense(amountCents: 0, date: feb2026)]
        let result = ExpenseCalculations.monthlyTotal(expenses: expenses, month: feb2026, currency: "USD")
        XCTAssertEqual(result.totalCents, 0)
        XCTAssertEqual(result.expenseCount, 1)
    }

    // MARK: - Group By Tag

    func testGroupByTag_empty() {
        let result = ExpenseCalculations.groupByTag(expenses: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testGroupByTag_singleTag() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-1"]),
            TestData.expense(id: "2", tagIds: ["tag-1"]),
        ]
        let result = ExpenseCalculations.groupByTag(expenses: expenses)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["tag-1"]?.count, 2)
    }

    func testGroupByTag_multipleTags() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-1"]),
            TestData.expense(id: "2", tagIds: ["tag-2"]),
            TestData.expense(id: "3", tagIds: ["tag-1"]),
        ]
        let result = ExpenseCalculations.groupByTag(expenses: expenses)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["tag-1"]?.count, 2)
        XCTAssertEqual(result["tag-2"]?.count, 1)
    }

    func testGroupByTag_multipleTagsPerExpense() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-a", "tag-b"]),
        ]
        let result = ExpenseCalculations.groupByTag(expenses: expenses)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["tag-a"]?.count, 1)
        XCTAssertEqual(result["tag-b"]?.count, 1)
    }

    func testGroupByTag_excludesDeleted() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-1"]),
            TestData.expense(id: "2", tagIds: ["tag-1"], deletedAt: Date()),
        ]
        let result = ExpenseCalculations.groupByTag(expenses: expenses)
        XCTAssertEqual(result["tag-1"]?.count, 1)
    }

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

    // MARK: - Filter By Date Range

    func testFilterByDateRange_inclusive() {
        let start = TestData.date(year: 2026, month: 2, day: 1)
        let end = TestData.date(year: 2026, month: 2, day: 28)
        let expenses = [
            TestData.expense(id: "before", date: TestData.date(year: 2026, month: 1, day: 31)),
            TestData.expense(id: "start", date: start),
            TestData.expense(id: "mid", date: TestData.date(year: 2026, month: 2, day: 15)),
            TestData.expense(id: "end", date: end),
            TestData.expense(id: "after", date: TestData.date(year: 2026, month: 3, day: 1)),
        ]
        let result = ExpenseCalculations.filterByDateRange(expenses: expenses, start: start, end: end)
        let ids = Set(result.map(\.id))
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(ids.contains("start"))
        XCTAssertTrue(ids.contains("mid"))
        XCTAssertTrue(ids.contains("end"))
        XCTAssertFalse(ids.contains("before"))
        XCTAssertFalse(ids.contains("after"))
    }

    func testFilterByDateRange_excludesDeleted() {
        let start = TestData.date(year: 2026, month: 2, day: 1)
        let end = TestData.date(year: 2026, month: 2, day: 28)
        let expenses = [
            TestData.expense(id: "1", date: TestData.date(year: 2026, month: 2, day: 10)),
            TestData.expense(id: "2", date: TestData.date(year: 2026, month: 2, day: 15), deletedAt: Date()),
        ]
        let result = ExpenseCalculations.filterByDateRange(expenses: expenses, start: start, end: end)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }

    // MARK: - Filter By Tag

    func testFilterByTag() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-a"]),
            TestData.expense(id: "2", tagIds: ["tag-b"]),
            TestData.expense(id: "3", tagIds: ["tag-a", "tag-b"]),
        ]
        let result = ExpenseCalculations.filterByTag(expenses: expenses, tagId: "tag-a")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.tagIds.contains("tag-a") })
    }

    func testFilterByTag_noMatch() {
        let expenses = [TestData.expense(tagIds: ["tag-a"])]
        let result = ExpenseCalculations.filterByTag(expenses: expenses, tagId: "tag-x")
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterByTag_matchesMultiTagExpense() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["tag-a", "tag-b"]),
        ]
        let resultA = ExpenseCalculations.filterByTag(expenses: expenses, tagId: "tag-a")
        let resultB = ExpenseCalculations.filterByTag(expenses: expenses, tagId: "tag-b")
        XCTAssertEqual(resultA.count, 1)
        XCTAssertEqual(resultB.count, 1)
    }

    // MARK: - Filter By Group

    func testFilterByGroup_matchesChildTags() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["child-a"]),
            TestData.expense(id: "2", tagIds: ["child-b"]),
            TestData.expense(id: "3", tagIds: ["other"]),
        ]
        let tags = [
            TestData.tag(id: "group-1", name: "Projects"),
            TestData.tag(id: "child-a", name: "Office Renovation", parentId: "group-1"),
            TestData.tag(id: "child-b", name: "Website Redesign", parentId: "group-1"),
            TestData.tag(id: "other", name: "Travel"),
        ]
        let result = ExpenseCalculations.filterByGroup(expenses: expenses, groupId: "group-1", tags: tags)
        XCTAssertEqual(result.count, 2)
        let ids = Set(result.map(\.id))
        XCTAssertTrue(ids.contains("1"))
        XCTAssertTrue(ids.contains("2"))
        XCTAssertFalse(ids.contains("3"))
    }

    func testFilterByGroup_noChildren_returnsEmpty() {
        let expenses = [TestData.expense(id: "1", tagIds: ["tag-1"])]
        let tags = [
            TestData.tag(id: "group-1", name: "Empty Group"),
            TestData.tag(id: "tag-1", name: "Travel"),
        ]
        let result = ExpenseCalculations.filterByGroup(expenses: expenses, groupId: "group-1", tags: tags)
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterByGroup_excludesDeletedExpenses() {
        let expenses = [
            TestData.expense(id: "1", tagIds: ["child-a"]),
            TestData.expense(id: "2", tagIds: ["child-a"], deletedAt: Date()),
        ]
        let tags = [
            TestData.tag(id: "group-1", name: "Projects"),
            TestData.tag(id: "child-a", name: "Office Renovation", parentId: "group-1"),
        ]
        let result = ExpenseCalculations.filterByGroup(expenses: expenses, groupId: "group-1", tags: tags)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
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
        XCTAssertTrue(lines[1].contains("manual"))
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
