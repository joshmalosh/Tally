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

    private let currencyCodesWithNoDecimals: Set<String> = ["JPY", "KRW", "VND", "CLP"]

    private static let currencyLocaleMap: [String: String] = [
        "USD": "en_US", "EUR": "de_DE", "GBP": "en_GB", "JPY": "ja_JP",
        "AUD": "en_AU", "CAD": "en_CA", "CHF": "de_CH", "CNY": "zh_CN",
        "KRW": "ko_KR", "INR": "en_IN", "NZD": "en_NZ", "SGD": "en_SG",
        "HKD": "zh_HK", "SEK": "sv_SE", "NOK": "nb_NO", "DKK": "da_DK",
        "BRL": "pt_BR", "MXN": "es_MX", "ZAR": "en_ZA", "VND": "vi_VN",
        "CLP": "es_CL",
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
}
