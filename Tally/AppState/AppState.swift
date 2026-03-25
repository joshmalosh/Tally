import SwiftUI

@Observable
final class AppState {
    // Navigation
    var showingAddExpense = false
    var showingExport = false
    var showingSettings = false
    var showingTagCreation = false
    var selectedExpenseId: String?

    // Filters (multi-select, AND logic)
    var activeFilterIds: Set<String> = []
    var groupFilterIds: Set<String> = []

    var hasTagFilters: Bool { !activeFilterIds.isEmpty }

    func clearFilters() {
        activeFilterIds.removeAll()
        groupFilterIds.removeAll()
    }

    func toggleFilter(id: String, isGroup: Bool) {
        if activeFilterIds.contains(id) {
            activeFilterIds.remove(id)
            groupFilterIds.remove(id)
        } else {
            activeFilterIds.insert(id)
            if isGroup { groupFilterIds.insert(id) }
        }
    }

    func removeFilter(id: String) {
        activeFilterIds.remove(id)
        groupFilterIds.remove(id)
    }

    // User
    var subscriptionStatus: SubscriptionStatus = .free
    var isOffline = false

    // Export tracking (free tier — capped CSV exports per calendar month; Pro unlimited)
    private static let csvExportCountKey = "csvExportCount"
    private static let csvExportMonthKey = "csvExportMonth"
    private static let freeTierCSVExportsPerMonth = 2

    var csvExportsThisMonth: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.csvExportCountKey)
        let storedMonth = UserDefaults.standard.string(forKey: Self.csvExportMonthKey) ?? ""
        return storedMonth == currentMonthKey ? stored : 0
    }

    var canExportCSV: Bool {
        if isPro { return true }
        return csvExportsThisMonth < Self.freeTierCSVExportsPerMonth
    }

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

    // Pro benefits prompt (every 3rd expense, max 3/month)
    private static let proPromptShownCountKey = "proPromptShownCount"
    private static let proPromptShownMonthKey = "proPromptShownMonth"

    var proPromptShownThisMonth: Int {
        let storedMonth = UserDefaults.standard.string(forKey: Self.proPromptShownMonthKey) ?? ""
        return storedMonth == currentMonthKey
            ? UserDefaults.standard.integer(forKey: Self.proPromptShownCountKey)
            : 0
    }

    func recordProPromptShown() {
        let month = currentMonthKey
        let storedMonth = UserDefaults.standard.string(forKey: Self.proPromptShownMonthKey) ?? ""
        if storedMonth != month {
            UserDefaults.standard.set(month, forKey: Self.proPromptShownMonthKey)
            UserDefaults.standard.set(1, forKey: Self.proPromptShownCountKey)
        } else {
            let count = UserDefaults.standard.integer(forKey: Self.proPromptShownCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.proPromptShownCountKey)
        }
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
        if UserDefaults.standard.bool(forKey: SubscriptionService.proCacheKey) {
            subscriptionStatus = .pro
        }
    }
}
