import Foundation
@testable import Tally

enum TestData {
    static let now = Date()
    static let calendar = Calendar.current

    static func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func expense(
        id: String = UUID().uuidString,
        userId: String = "user-1",
        amountCents: Int = 1000,
        currency: String = "USD",
        date: Date = Date(),
        description: String? = nil,
        merchant: String? = nil,
        tagIds: [String] = ["tag-1"],
        notes: String? = nil,
        attachmentKey: String? = nil,
        source: ExpenseSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) -> Expense {
        Expense(
            id: id,
            userId: userId,
            amountCents: amountCents,
            currency: currency,
            date: date,
            description: description,
            merchant: merchant,
            tagIds: tagIds,
            notes: notes,
            attachmentKey: attachmentKey,
            source: source,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    static func tag(
        id: String = "tag-1",
        userId: String? = nil,
        name: String = "Travel",
        colorId: String = "teal",
        icon: String? = nil,
        sortOrder: Int = 0,
        parentId: String? = nil
    ) -> Tag {
        Tag(id: id, userId: userId, name: name, colorId: colorId, icon: icon, sortOrder: sortOrder, parentId: parentId)
    }
}
