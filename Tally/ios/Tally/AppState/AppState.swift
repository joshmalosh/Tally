import SwiftUI
import Security

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

    // Export tracking (free tier — 1 CSV/month).
    //
    // Stored in the Keychain rather than UserDefaults so that the values are
    // encrypted at rest and cannot be trivially reset by clearing app storage
    // or editing a plist. On a non-jailbroken device this prevents users from
    // bypassing the free-tier export limit without a valid Pro subscription.
    private static let csvExportCountKey = "com.tally.csvExportCount"
    private static let csvExportMonthKey = "com.tally.csvExportMonth"

    var csvExportsThisMonth: Int {
        let storedMonth = Keychain.string(forKey: Self.csvExportMonthKey) ?? ""
        guard storedMonth == currentMonthKey else { return 0 }
        return Int(Keychain.string(forKey: Self.csvExportCountKey) ?? "0") ?? 0
    }

    var canExportCSV: Bool { isPro || csvExportsThisMonth < 1 }

    func recordCSVExport() {
        let month = currentMonthKey
        let storedMonth = Keychain.string(forKey: Self.csvExportMonthKey) ?? ""
        if storedMonth != month {
            Keychain.set(month, forKey: Self.csvExportMonthKey)
            Keychain.set("1", forKey: Self.csvExportCountKey)
        } else {
            let count = Int(Keychain.string(forKey: Self.csvExportCountKey) ?? "0") ?? 0
            Keychain.set(String(count + 1), forKey: Self.csvExportCountKey)
        }
    }

    private var currentMonthKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    // Preferences (non-sensitive — UserDefaults is fine here)
    private static let defaultCurrencyKey = "defaultCurrency"
    private static let ocrEnabledKey = "ocrEnabled"

    var defaultCurrency: String {
        didSet { UserDefaults.standard.set(defaultCurrency, forKey: Self.defaultCurrencyKey) }
    }

    var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrEnabled, forKey: Self.ocrEnabledKey) }
    }

    // Expense count (for ad threshold) — non-sensitive, UserDefaults is fine.
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

// MARK: - Keychain helper

/// Minimal wrapper around the Security framework for storing small string
/// values in the default Keychain. Items are protected with
/// `kSecAttrAccessibleAfterFirstUnlock` (readable after the user unlocks the
/// device at least once; survives backgrounding; backed up via encrypted iCloud
/// Backup).
private enum Keychain {
    static func string(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        // Try updating an existing item first.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // No existing item — add a new one.
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
