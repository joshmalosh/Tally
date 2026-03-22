import Foundation
import SwiftData

/// Processes overdue recurring expenses on app launch. Creates logged copies, advances nextDueDate.
enum RecurringExpenseService {

    struct LoggedSummary {
        let expenseIds: [String]
        let templateIds: [String]
        let forNotification: [(amountCents: Int, currency: String, merchant: String?)]
    }

    /// Returns summary of logged expenses for notification scheduling. Must run on main actor.
    @MainActor
    static func processOverdueRecurring(modelContext: ModelContext) async -> LoggedSummary {
        var loggedIds: [String] = []
        var templateIds: [String] = []
        var forNotification: [(Int, String, String?)] = []

        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ExpenseModel>(
            predicate: #Predicate<ExpenseModel> { $0.isRecurring == true }
        )

        guard let all = try? modelContext.fetch(descriptor) else {
            return LoggedSummary(expenseIds: [], templateIds: [], forNotification: [])
        }
        let templates = all.filter { $0.deletedAt == nil && $0.nextDueDate != nil }

        for template in templates {
            guard let nextDue = template.nextDueDate else { continue }

            var dueDate = Calendar.current.startOfDay(for: nextDue)
            let cal = Calendar.current

            while dueDate <= today {
                let logged = ExpenseModel(
                    userId: template.userId,
                    amountCents: template.amountCents,
                    currency: template.currency,
                    date: dueDate,
                    description: template.expenseDescription,
                    merchant: template.merchant,
                    tagIds: template.tagIds ?? [],
                    notes: template.notes,
                    source: "recurring"
                )
                logged.recurrenceTemplateId = template.id
                modelContext.insert(logged)
                loggedIds.append(logged.id)
                forNotification.append((template.amountCents, template.currency, template.merchant))
                if !templateIds.contains(template.id) {
                    templateIds.append(template.id)
                }

                switch template.recurringFrequency {
                case "weekly":
                    dueDate = cal.date(byAdding: .weekOfYear, value: 1, to: dueDate) ?? dueDate
                case "yearly":
                    dueDate = cal.date(byAdding: .year, value: 1, to: dueDate) ?? dueDate
                default:
                    dueDate = cal.date(byAdding: .month, value: 1, to: dueDate) ?? dueDate
                }
            }

            template.nextDueDate = dueDate
        }

        if !loggedIds.isEmpty {
            try? modelContext.save()
        }

        return LoggedSummary(expenseIds: loggedIds, templateIds: templateIds, forNotification: forNotification)
    }

    static func advanceNextDue(from date: Date, frequency: String) -> Date {
        let cal = Calendar.current
        switch frequency {
        case "weekly":
            return cal.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case "yearly":
            return cal.date(byAdding: .year, value: 1, to: date) ?? date
        default:
            return cal.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}
