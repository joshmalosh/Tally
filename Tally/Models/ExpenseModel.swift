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
    var tagIds: [String]? = []
    /// IDs of the reports (envelopes/dossiers) this expense is clipped into.
    /// Optional-with-default for a clean additive SwiftData/CloudKit migration —
    /// a report is a non-exclusive label, so an expense keeps its tags and still
    /// appears in the timeline and Insights.
    var reportIds: [String]? = []
    var notes: String?
    /// Names of people the spend was shared with (dinner guests, colleagues).
    /// Free text, remembered across expenses for autocomplete. Optional for a
    /// clean additive SwiftData migration on existing stores.
    var attendees: [String]? = []
    var attachmentKey: String?
    @Attribute(.externalStorage) var attachmentData: Data?
    /// True only when a receipt scan auto-filled the amount, so the AUTO-SCANNED
    /// badge reflects an actual scan rather than any camera/upload expense.
    var wasAutoScanned: Bool = false
    var source: String = "manual"
    var isRecurring: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var syncedAt: Date?

    /// Attendee names, nil-safe for reads.
    var resolvedAttendees: [String] { attendees ?? [] }

    /// Report IDs, nil-safe for reads.
    var resolvedReportIds: [String] { reportIds ?? [] }

    /// Resolved tag IDs — reads from tagIds, falling back to legacy tagId for unmigrated data.
    var resolvedTagIds: [String] {
        let ids = tagIds ?? []
        if !ids.isEmpty { return ids }
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
        attendees: [String] = [],
        attachmentKey: String? = nil,
        attachmentData: Data? = nil,
        source: String = "manual",
        isRecurring: Bool = false,
        wasAutoScanned: Bool = false,
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
        self.attendees = attendees
        self.attachmentKey = attachmentKey
        self.attachmentData = attachmentData
        self.source = source
        self.isRecurring = isRecurring
        self.wasAutoScanned = wasAutoScanned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Currency-safe aggregation

/// The app has no FX, so a total across mixed currencies is meaningless. Every
/// total, chart and summary is scoped to a single currency — usually
/// `appState.activeCurrency`. Use these instead of a raw `reduce` so the whole
/// app agrees on the same number: reports, the home hero, period detail and any
/// on-screen summary all consolidate the same way.
extension Sequence where Element == ExpenseModel {
    /// The subset in one currency.
    func inCurrency(_ currency: String) -> [ExpenseModel] {
        filter { $0.currency == currency }
    }

    /// Sum of minor units in one currency; expenses in other currencies
    /// contribute nothing, never silently added at face value.
    func totalCents(in currency: String) -> Int {
        reduce(0) { $0 + ($1.currency == currency ? $1.amountCents : 0) }
    }
}

// MARK: - Report (envelope / dossier)

/// A report is the envelope you clip expenses into for a trip, a claim, or tax —
/// then export and archive. Distinct from tags, which classify the *nature* of an
/// expense forever; a report is a finite, episodic package. Membership lives on
/// `ExpenseModel.reportIds` (many-to-many, non-exclusive). Grouped by lifecycle
/// (active vs archived), not by "report groups". CloudKit-safe: every stored
/// property has a default or is optional.
@Model
final class ReportModel {
    var id: String = UUID().uuidString
    var name: String = ""
    /// The report's cover emoji (like a labelled manila folder). Editable.
    var emoji: String = "🗂️"
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Non-nil once the report is archived / sent. Active reports have nil.
    var archivedAt: Date?
    /// Soft-delete for undo, mirroring the expense delete pipeline.
    var deletedAt: Date?
    var sortOrder: Int = 0

    var isArchived: Bool { archivedAt != nil }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        emoji: String = "🗂️",
        note: String? = nil,
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sortOrder = sortOrder
    }
}
