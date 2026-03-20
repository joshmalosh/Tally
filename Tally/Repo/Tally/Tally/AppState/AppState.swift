import SwiftUI

@Observable
final class AppState {
    // Navigation
    var showingAddExpense = false
    var showingExport = false
    var showingSettings = false
    var showingTagCreation = false
    var selectedExpenseId: String?

    // Filters
    var selectedTagFilter: String?
    var isGroupFilter = false

    // User
    var subscriptionStatus: SubscriptionStatus = .free
    var isOffline = false

    // Export tracking (free tier — 1 CSV/month)
    private static let csvExportCountKey = "csvExportCount"
    private static let csvExportMonthKey = "csvExportMonth"

    var csvExportsThisMonth: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.csvExportCountKey)
        let storedMonth = UserDefaults.standard.string(forKey: Self.csvExportMonthKey) ?? ""
        return storedMonth == currentMonthKey ? stored : 0
    }

    var canExportCSV: Bool { isPro || csvExportsThisMonth < 1 }

    func recordCSVExport() {
        let month = currentMonthKey
        let storedMonth = UserDefaults.standard.string(forKey: Self.csvExportMonthKey) ?? ""
        if storedMonth != month {
            UserDefaults.standard.set(month, forKey: Self.csvExportMonthKey)
            UserDefaults.standard.set(1, forKey: Self.csvExportCountKey)
        } else {
            let count = UserDefaults.standard.integer(forKey: Self.csvExportCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.csvExportCountKey)
        }
    }

    private var currentMonthKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    // Preferences
    private static let defaultCurrencyKey = "defaultCurrency"
    private static let ocrEnabledKey = "ocrEnabled"

    var defaultCurrency: String {
        didSet { UserDefaults.standard.set(defaultCurrency, forKey: Self.defaultCurrencyKey) }
    }

    var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrEnabled, forKey: Self.ocrEnabledKey) }
    }

    // Expense count (for ad threshold)
    private static let totalExpenseCountKey = "totalExpenseCount"

    var totalExpenseCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.totalExpenseCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.totalExpenseCountKey) }
    }

    // Computed
    var isPro: Bool { subscriptionStatus == .pro }

    enum SubscriptionStatus: String {
        case free, pro, expired, cancelled
    }

    init() {
        self.defaultCurrency = UserDefaults.standard.string(forKey: Self.defaultCurrencyKey) ?? "USD"
        self.ocrEnabled = UserDefaults.standard.object(forKey: Self.ocrEnabledKey) as? Bool ?? true
    }
}
