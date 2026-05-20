import SwiftUI

// MARK: - Colors

extension Color {
    // Brand
    static let brandPrimary = Color(hex: "2F402E")
    static let brandSecondary = Color(hex: "4A7D62")
    static let brandTint = Color(hex: "E8EFE9")
    static let brandBorder = Color(hex: "8BBF9E")
    static let brandPressed = Color(hex: "2A4E3B")

    // UI action green — matches brand primary for interactive elements
    static let actionGreen = Color(hex: "2F402E")
    static let actionGreenPressed = Color(hex: "2A4E3B")

    // Surfaces
    static let bgPrimary = Color(hex: "F6F5F3")
    static let surface = Color.white
    static let borderColor = Color(hex: "E3E8E5")

    // Text
    static let textPrimary = Color(hex: "111417")
    static let textSecondary = Color(hex: "6B7280")
    static let textMuted = Color(hex: "9CA3AF")
    static let textBody = Color(hex: "4B5563")

    // Semantic
    static let danger = Color(hex: "C84646")
    static let success = Color(hex: "2E7D5B")

    // Chip states (neutral — no multicolored backgrounds)
    static let chipInactiveBg = Color(hex: "EEEDEB")
    static let chipInactiveText = Color(hex: "111417")
    static let chipActiveBg = Color(hex: "2F402E")
    static let chipActiveText = Color.white
    static let chipActiveBorder = Color.clear
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Custom Fonts

extension Font {
    /// Editorial serif font for date headers and section titles.
    /// Uses iOS built-in New York (design: .serif) — no additional font file required.
    static func dmSerifDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

// MARK: - Typography

struct Fonts {
    // Brand serif (New York) — for totals, section headers, brand moments
    static func brand(_ size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // UI sans-serif (SF Pro) — for all functional text
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold)
    }

    static func headline(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular)
    }

    static func label(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular)
    }

    static func mono(_ size: CGFloat = 16) -> Font {
        .system(size: size, design: .monospaced).weight(.medium)
    }
}

// MARK: - Spacing (consistent 4-point scale)

struct Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let smd: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Radius

struct Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let pill: CGFloat = 16
}
