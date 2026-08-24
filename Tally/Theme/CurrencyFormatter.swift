import Foundation

struct SupportedCurrency: Identifiable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }
}

final class CurrencyFormatter {
    static let shared = CurrencyFormatter()

    private var formatterCache: [String: NumberFormatter] = [:]

    static let commonCurrencyCodes: Set<String> = ["USD", "EUR", "GBP", "AUD", "CAD", "JPY"]

    static let supportedCurrencies: [SupportedCurrency] = [
        SupportedCurrency(code: "USD", name: "US Dollar", flag: "🇺🇸"),
        SupportedCurrency(code: "EUR", name: "Euro", flag: "🇪🇺"),
        SupportedCurrency(code: "GBP", name: "British Pound", flag: "🇬🇧"),
        SupportedCurrency(code: "AUD", name: "Australian Dollar", flag: "🇦🇺"),
        SupportedCurrency(code: "CAD", name: "Canadian Dollar", flag: "🇨🇦"),
        SupportedCurrency(code: "JPY", name: "Japanese Yen", flag: "🇯🇵"),
        SupportedCurrency(code: "CHF", name: "Swiss Franc", flag: "🇨🇭"),
        SupportedCurrency(code: "CNY", name: "Chinese Yuan", flag: "🇨🇳"),
        SupportedCurrency(code: "KRW", name: "South Korean Won", flag: "🇰🇷"),
        SupportedCurrency(code: "INR", name: "Indian Rupee", flag: "🇮🇳"),
        SupportedCurrency(code: "NZD", name: "New Zealand Dollar", flag: "🇳🇿"),
        SupportedCurrency(code: "SGD", name: "Singapore Dollar", flag: "🇸🇬"),
        SupportedCurrency(code: "HKD", name: "Hong Kong Dollar", flag: "🇭🇰"),
        SupportedCurrency(code: "SEK", name: "Swedish Krona", flag: "🇸🇪"),
        SupportedCurrency(code: "NOK", name: "Norwegian Krone", flag: "🇳🇴"),
        SupportedCurrency(code: "DKK", name: "Danish Krone", flag: "🇩🇰"),
        SupportedCurrency(code: "BRL", name: "Brazilian Real", flag: "🇧🇷"),
        SupportedCurrency(code: "MXN", name: "Mexican Peso", flag: "🇲🇽"),
        SupportedCurrency(code: "ZAR", name: "South African Rand", flag: "🇿🇦"),
        SupportedCurrency(code: "VND", name: "Vietnamese Dong", flag: "🇻🇳"),
        SupportedCurrency(code: "CLP", name: "Chilean Peso", flag: "🇨🇱"),
    ]

    /// IDR carries two minor units on paper, but no Indonesian price, receipt or
    /// payment terminal has ever shown them — "4,640,000.00" reads as a bug.
    private let currencyCodesWithNoDecimals: Set<String> = ["JPY", "KRW", "VND", "CLP", "IDR", "ISK"]

    private static let currencyLocaleMap: [String: String] = [
        "USD": "en_US", "EUR": "de_DE", "GBP": "en_GB", "JPY": "ja_JP",
        "AUD": "en_AU", "CAD": "en_CA", "CHF": "de_CH", "CNY": "zh_CN",
        "KRW": "ko_KR", "INR": "en_IN", "NZD": "en_NZ", "SGD": "en_SG",
        "HKD": "zh_HK", "SEK": "sv_SE", "NOK": "nb_NO", "DKK": "da_DK",
        "BRL": "pt_BR", "MXN": "es_MX", "ZAR": "en_ZA", "VND": "vi_VN",
        "CLP": "es_CL", "IDR": "id_ID", "THB": "th_TH", "MYR": "ms_MY",
        "PHP": "en_PH", "ISK": "is_IS",
    ]

    private func formatter(for currencyCode: String) -> NumberFormatter {
        if let cached = formatterCache[currencyCode] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        if let localeId = Self.currencyLocaleMap[currencyCode] {
            f.locale = Locale(identifier: localeId)
        } else {
            f.locale = Locale(identifier: "en_US")
        }
        let decimalPlaces = currencyCodesWithNoDecimals.contains(currencyCode) ? 0 : 2
        f.minimumFractionDigits = decimalPlaces
        f.maximumFractionDigits = decimalPlaces
        formatterCache[currencyCode] = f
        return f
    }

    func format(cents: Int, currencyCode: String = "USD") -> String {
        let fmt = formatter(for: currencyCode)
        let divisor = currencyCodesWithNoDecimals.contains(currencyCode) ? 1.0 : 100.0
        let amount = Double(cents) / divisor
        return fmt.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    func formatCompact(cents: Int, currencyCode: String = "USD") -> String {
        let divisor = currencyCodesWithNoDecimals.contains(currencyCode) ? 1.0 : 100.0
        let amount = Double(cents) / divisor

        let fmt = formatter(for: currencyCode)
        let symbol = fmt.currencySymbol ?? "$"

        if amount >= 1_000_000 {
            return String(format: "\(symbol)%.1fM", amount / 1_000_000)
        } else if amount >= 10_000 {
            return String(format: "\(symbol)%.0fK", amount / 1_000)
        }
        return format(cents: cents, currencyCode: currencyCode)
    }

    func symbol(for currencyCode: String) -> String {
        formatter(for: currencyCode).currencySymbol ?? currencyCode
    }

    func usesDecimals(for currencyCode: String) -> Bool {
        !currencyCodesWithNoDecimals.contains(currencyCode)
    }

    /// The whole-number part only (no symbol, no decimals), grouped in the
    /// currency's own locale — e.g. `6,08,600` for INR, `608,600` for USD. Used by
    /// the big split-digit hero/period totals so their grouping matches the rest
    /// of the app. Pass the same `cents` you'd give `format`.
    func groupedWhole(cents: Int, currencyCode: String) -> String {
        let whole = usesDecimals(for: currencyCode) ? cents / 100 : cents
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        if let localeId = Self.currencyLocaleMap[currencyCode] {
            f.locale = Locale(identifier: localeId)
        }
        return f.string(from: NSNumber(value: whole)) ?? "\(whole)"
    }
}
