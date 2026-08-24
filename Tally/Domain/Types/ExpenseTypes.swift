import Foundation

enum ExpenseSource: String, Codable, CaseIterable {
    case camera
    case upload
    case manual
}

struct Expense: Identifiable, Codable {
    let id: String
    let userId: String
    var amountCents: Int
    var currency: String
    var date: Date
    var description: String?
    var merchant: String?
    var tagIds: [String]
    var notes: String?
    var attachmentKey: String?
    var source: ExpenseSource
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct Tag: Identifiable, Codable {
    let id: String
    let userId: String?
    var name: String
    var colorId: String
    var icon: String?
    var sortOrder: Int
    var parentId: String?
}
