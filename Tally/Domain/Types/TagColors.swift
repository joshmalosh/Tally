import SwiftUI

struct TagColor: Identifiable, Codable, Hashable {
    let id: String
    let primary: String
    let tint: String

    var primaryColor: Color { Color(hex: primary) }
    var tintColor: Color { Color(hex: tint) }
    var pressedColor: Color { primaryColor.opacity(0.8) }
}

enum TagColors {
    static let palette: [TagColor] = [
        // Greens
        TagColor(id: "primaryGreen", primary: "346049", tint: "E6EBE9"),
        TagColor(id: "deepForest",   primary: "1B3D2A", tint: "E3E8E5"),
        TagColor(id: "moss",         primary: "6B8F3E", tint: "EEF3E8"),
        TagColor(id: "softSage",     primary: "8BBF9E", tint: "F0F7F3"),

        // Teals
        TagColor(id: "teal",         primary: "2A8C89", tint: "E5F1F0"),
        TagColor(id: "lightAqua",    primary: "5CB8B2", tint: "EDF7F6"),
        TagColor(id: "deepTeal",     primary: "1B6B6B", tint: "E4EDED"),

        // Blues
        TagColor(id: "indigoBlue",   primary: "4A5FAF", tint: "EAEDF6"),
        TagColor(id: "softBlue",     primary: "5B9BD5", tint: "ECF2F9"),
        TagColor(id: "steelBlue",    primary: "3D6B8F", tint: "E8EDF1"),
        TagColor(id: "navySlate",    primary: "263855", tint: "E5E8ED"),

        // Purples
        TagColor(id: "mutedPurple",  primary: "7B5EA7", tint: "EFEDF5"),
        TagColor(id: "softLavender", primary: "A88FC8", tint: "F3F0F8"),
        TagColor(id: "deepPlum",     primary: "5A3D73", tint: "EBEBF0"),

        // Pinks & warm reds
        TagColor(id: "terracotta",   primary: "C4604A", tint: "F7ECE9"),
        TagColor(id: "softCoral",    primary: "E0736B", tint: "FAEEEC"),
        TagColor(id: "dustyRose",    primary: "C47088", tint: "F7EDF0"),

        // Oranges & yellows
        TagColor(id: "burntOrange",  primary: "D4872A", tint: "F9F0E5"),
        TagColor(id: "warmAmber",    primary: "C4A030", tint: "F7F1E5"),
        TagColor(id: "goldenOchre",  primary: "8F7A2E", tint: "F1EDE5"),

        // Neutrals
        TagColor(id: "warmGrey",     primary: "8F897E", tint: "F1F0EF"),
        TagColor(id: "coolGrey",     primary: "6B7580", tint: "EDEEEF"),
        TagColor(id: "deepGrey",     primary: "4B4F54", tint: "EAEAEB"),
        TagColor(id: "taupe",        primary: "A39080", tint: "F3F1EF"),
    ]

    static func forId(_ id: String) -> TagColor {
        palette.first { $0.id == id } ?? palette[0]
    }

    static let defaultTagColors: [String: String] = [
        "Travel": "softBlue",
        "Petrol": "moss",
        "Meals": "burntOrange",
        "Subscriptions": "mutedPurple",
    ]
}
