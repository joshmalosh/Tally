import SwiftUI
import OSLog

/// Central, categorised logging built on Apple's unified logging.
///
/// Filter to just Tally by subsystem `com.asimplelife.tally` in Xcode's console
/// or Console.app. Levels: `.debug` (verbose, DEBUG only, never persisted),
/// `.info` (transient), `.error`/`.fault` (persisted, visible in release).
///
/// Privacy: interpolate user data as `\(value, privacy: .private)` so amounts,
/// merchants, notes, receipt text and IDs are redacted as `<private>` in release
/// and any sysdiagnose. Only non-identifying diagnostics use `.public`.
enum Log {
    private static let sub = "com.asimplelife.tally"
    static let app          = Logger(subsystem: sub, category: "app")
    static let sync         = Logger(subsystem: sub, category: "sync")
    static let data         = Logger(subsystem: sub, category: "data")
    static let ocr          = Logger(subsystem: sub, category: "ocr")
    static let subscription = Logger(subsystem: sub, category: "subscription")
    static let ads          = Logger(subsystem: sub, category: "ads")
    static let attachments  = Logger(subsystem: sub, category: "attachments")
}

@Observable
final class AppState {
    // Navigation
    var showingAddExpense = false
    var showingExport = false
    var showingSettings = false
    /// Global upsell trigger (e.g. the "upgrade now" link under an ad); presented
    /// from the app root so it works from any tab.
    var showingSubscription = false
    var showingTagCreation = false
    var selectedExpenseId: String?

    // Filters (multi-select, AND logic)
    var activeFilterIds: Set<String> = []
    var groupFilterIds: Set<String> = []
    /// Show only expenses marked recurring (subscriptions etc.).
    var filterRecurringOnly = false
    /// When set, totals and lists are scoped to this currency; otherwise the
    /// default currency is used. Only currencies the user actually has appear as
    /// filter options.
    var filterCurrency: String? = nil

    /// Currency that totals/lists resolve to right now.
    var activeCurrency: String { filterCurrency ?? defaultCurrency }

    var hasTagFilters: Bool { !activeFilterIds.isEmpty }
    var hasAnyFilter: Bool { !activeFilterIds.isEmpty || filterRecurringOnly || filterCurrency != nil }

    func clearFilters() {
        activeFilterIds.removeAll()
        groupFilterIds.removeAll()
        filterRecurringOnly = false
        filterCurrency = nil
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
    private static let freeTierCSVExportsPerMonth = 1

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

    // MARK: - OCR scan quota (free tier)
    //
    // Free users get a fixed number of *successful* receipt scans per calendar
    // month, across every entry point — camera, photo library, file/PDF upload,
    // share extension, bulk import. Pro is unlimited.
    //
    // The quota counts scans that actually returned an amount. A scan that
    // failed to read the amount left the user typing the number themselves, so
    // charging for it would make the allowance feel like a scam. See
    // `recordOCRScan(extractedAmount:)`.
    private static let ocrScanCountKey = "ocrScanCount"
    private static let ocrScanMonthKey = "ocrScanMonth"
    static let freeTierOCRScansPerMonth = 10

    var ocrScansThisMonth: Int {
        let storedMonth = UserDefaults.standard.string(forKey: Self.ocrScanMonthKey) ?? ""
        return storedMonth == currentMonthKey
            ? UserDefaults.standard.integer(forKey: Self.ocrScanCountKey)
            : 0
    }

    /// Remaining free scans this month. Always `.max` for Pro.
    var ocrScansRemaining: Int {
        if isPro { return .max }
        return max(0, Self.freeTierOCRScansPerMonth - ocrScansThisMonth)
    }

    /// Gate checked *before* running OCR. 10 usable scans; the 11th is blocked.
    var canUseOCR: Bool {
        if isPro { return true }
        return ocrScansThisMonth < Self.freeTierOCRScansPerMonth
    }

    /// Call after every OCR attempt. Only a scan that produced an amount is
    /// charged — a failed read costs the user nothing.
    func recordOCRScan(extractedAmount: Bool) {
        guard !isPro, extractedAmount else { return }
        let month = currentMonthKey
        let storedMonth = UserDefaults.standard.string(forKey: Self.ocrScanMonthKey) ?? ""
        if storedMonth != month {
            UserDefaults.standard.set(month, forKey: Self.ocrScanMonthKey)
            UserDefaults.standard.set(1, forKey: Self.ocrScanCountKey)
        } else {
            let count = UserDefaults.standard.integer(forKey: Self.ocrScanCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.ocrScanCountKey)
        }
    }

    // MARK: - Daily upgrade prompt
    //
    // Shown on first open of the day, at most every 3 days, and never in the
    // user's first 3 days — a prompt before the app has proved itself converts
    // badly and taints the first impression.
    private static let upgradePromptLastShownKey = "upgradePromptLastShown"
    private static let firstLaunchDateKey = "firstLaunchDate"
    private static let upgradePromptIntervalDays = 3
    private static let upgradePromptGraceDays = 3

    /// Stamped on first ever launch so the grace period has an anchor.
    func recordFirstLaunchIfNeeded() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstLaunchDateKey)
        }
    }

    var shouldShowUpgradePrompt: Bool {
        guard !isPro else { return false }
        let cal = Calendar.current
        let now = Date()

        let firstLaunch = UserDefaults.standard.object(forKey: Self.firstLaunchDateKey) as? Date ?? now
        let daysSinceFirstLaunch = cal.dateComponents([.day], from: cal.startOfDay(for: firstLaunch),
                                                      to: cal.startOfDay(for: now)).day ?? 0
        guard daysSinceFirstLaunch >= Self.upgradePromptGraceDays else { return false }

        guard let lastShown = UserDefaults.standard.object(forKey: Self.upgradePromptLastShownKey) as? Date else {
            return true
        }
        let daysSinceShown = cal.dateComponents([.day], from: cal.startOfDay(for: lastShown),
                                                to: cal.startOfDay(for: now)).day ?? 0
        return daysSinceShown >= Self.upgradePromptIntervalDays
    }

    func recordUpgradePromptShown() {
        UserDefaults.standard.set(Date(), forKey: Self.upgradePromptLastShownKey)
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

    private static let financialYearStartMonthKey = "financialYearStartMonth"

    /// 1–12; persisted under the same key as `@AppStorage("financialYearStartMonth")` would use.
    var financialYearStartMonth: Int {
        get {
            if let v = UserDefaults.standard.object(forKey: Self.financialYearStartMonthKey) as? Int,
               (1...12).contains(v) {
                return v
            }
            return Self.defaultFinancialYearStartMonth()
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.financialYearStartMonthKey)
        }
    }

    static func defaultFinancialYearStartMonth() -> Int {
        let regionCode = Locale.current.region?.identifier ?? "US"
        switch regionCode {
        case "AU", "NZ": return 7
        case "GB", "IN", "PK", "BD": return 4
        case "JP": return 4
        case "CA": return 4
        default: return 1
        }
    }

    var currentFinancialYearStart: Date {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let startYear = month >= financialYearStartMonth ? year : year - 1
        return cal.date(from: DateComponents(year: startYear, month: financialYearStartMonth, day: 1)) ?? now
    }

    // Expense count (for ad threshold)
    private static let totalExpenseCountKey = "totalExpenseCount"

    var totalExpenseCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.totalExpenseCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.totalExpenseCountKey) }
    }

    // Computed
    #if DEBUG
    /// Debug-only Pro override. Pro can't be purchased until the subscription
    /// product exists in App Store Connect, so without this there is no way to
    /// exercise Pro-gated features (OCR merchant/notes auto-fill, PDF export,
    /// advanced filters, ad-free) on device. Persisted so it survives launches
    /// and isn't clobbered by a subscription refresh. Never ships — DEBUG only.
    private static let debugForceProKey = "debugForcePro"
    /// Stored (not computed) so @Observable tracks it and Pro-dependent UI —
    /// ads, paywalls, OCR gating — updates the moment it's toggled.
    var debugForcePro: Bool = UserDefaults.standard.bool(forKey: "debugForcePro") {
        didSet { UserDefaults.standard.set(debugForcePro, forKey: Self.debugForceProKey) }
    }
    var isPro: Bool { debugForcePro || subscriptionStatus == .pro }
    #else
    var isPro: Bool { subscriptionStatus == .pro }
    #endif

    enum SubscriptionStatus: String {
        case free, pro, expired, cancelled
    }

    init() {
        self.defaultCurrency = UserDefaults.standard.string(forKey: Self.defaultCurrencyKey) ?? "USD"
        self.ocrEnabled = UserDefaults.standard.object(forKey: Self.ocrEnabledKey) as? Bool ?? true
    }
}
