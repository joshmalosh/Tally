import Foundation
import SwiftData

@Model
final class ExpenseModel {
    var id: String = UUID().uuidString
    var userId: String = ""
    var amountCents: Int = 0
    var currency: String = "USD"
    var date: Date = Date.now
    var expenseDescription: String?
    var merchant: String?
    var tagId: String = ""
    var tagIds: [String] = []
    var notes: String?
    var attachmentKey: String?
    @Attribute(.externalStorage) var attachmentData: Data?
    var source: String = "manual"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var syncedAt: Date?

    /// Resolved tag IDs — reads from tagIds, falling back to legacy tagId for unmigrated data.
    var resolvedTagIds: [String] {
        if !tagIds.isEmpty { return tagIds }
        if !tagId.isEmpty { return [tagId] }
        return []
    }

    init(
        id: String = UUID().uuidString,
        userId: String = "",
        amountCents: Int = 0,
        currency: String = "USD",
        date: Date = .now,
        description: String? = nil,
        merchant: String? = nil,
        tagIds: [String] = [],
        notes: String? = nil,
        attachmentKey: String? = nil,
        attachmentData: Data? = nil,
        source: String = "manual",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.amountCents = amountCents
        self.currency = currency
        self.date = date
        self.expenseDescription = description
        self.merchant = merchant
        self.tagIds = tagIds
        self.tagId = tagIds.first ?? ""
        self.notes = notes
        self.attachmentKey = attachmentKey
        self.attachmentData = attachmentData
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
