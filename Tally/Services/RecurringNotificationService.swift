import Foundation
import UserNotifications

/// Schedules a local notification at 10:00am when recurring expenses were auto-logged.
enum RecurringNotificationService {

    /// Schedule notification for today at 10am. Uses summary from processOverdueRecurring.
    static func scheduleIfNeeded(summary: RecurringExpenseService.LoggedSummary) async {
        let items = summary.forNotification
        guard !items.isEmpty else { return }

        let body: String
        if items.count == 1, let first = items.first {
            let amount = CurrencyFormatter.shared.format(cents: first.amountCents, currencyCode: first.currency)
            let merchant = first.merchant ?? "expense"
            body = "Your \(amount) \(merchant) was logged today."
        } else {
            let merchants = items.compactMap(\.merchant).filter { !$0.isEmpty }
            let list = merchants.isEmpty ? "expenses" : Array(Set(merchants)).joined(separator: ", ")
            body = "Your recurring expenses for today have been logged: \(list)."
        }

        let content = UNMutableNotificationContent()
        content.title = "Recurring expenses logged"
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "recurring-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
