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
        // Greens (brand family)
        TagColor(id: "primaryGreen", primary: "346049", tint: "E6EBE9"),
        TagColor(id: "deepForest",   primary: "2B4E3B", tint: "E5E9E7"),
        TagColor(id: "moss",         primary: "6F7F5E", tint: "EDEFEB"),
        TagColor(id: "softSage",     primary: "8FA38A", tint: "F0F4F0"),

        // Teals
        TagColor(id: "teal",         primary: "3F8F8C", tint: "E7F1F1"),
        TagColor(id: "lightAqua",    primary: "6AA9A6", tint: "EDF5F4"),
        TagColor(id: "deepTeal",     primary: "2F6F6C", tint: "E6EDED"),

        // Blues
        TagColor(id: "indigoBlue",   primary: "5B6FA8", tint: "EBEDF4"),
        TagColor(id: "softBlue",     primary: "7F96C4", tint: "F0F3F8"),
        TagColor(id: "steelBlue",    primary: "4F6A7F", tint: "E9EDEF"),
        TagColor(id: "navySlate",    primary: "2E3E52", tint: "E6E9ED"),

        // Purples
        TagColor(id: "mutedPurple",  primary: "7A6F9A", tint: "EFEDF2"),
        TagColor(id: "softLavender", primary: "9B8FB8", tint: "F2F0F6"),
        TagColor(id: "deepPlum",     primary: "5C4E73", tint: "ECEBF0"),

        // Warm tones
        TagColor(id: "terracotta",   primary: "C46A4A", tint: "F7EDE9"),
        TagColor(id: "softCoral",    primary: "D97973", tint: "FAEEEE"),
        TagColor(id: "dustyRose",    primary: "E3A09A", tint: "FAF2F1"),

        // Oranges & ambers
        TagColor(id: "burntOrange",  primary: "C97A2C", tint: "F8EFE5"),
        TagColor(id: "warmAmber",    primary: "E3A24A", tint: "FAF2E8"),
        TagColor(id: "goldenOchre",  primary: "A67C2E", tint: "F4EFE5"),

        // Neutrals
        TagColor(id: "warmGrey",     primary: "8A8F8B", tint: "F0F1F1"),
        TagColor(id: "coolGrey",     primary: "6F757C", tint: "EDEEEF"),
        TagColor(id: "deepGrey",     primary: "4B4F54", tint: "EAEAEB"),
        TagColor(id: "taupe",        primary: "9A9187", tint: "F2F1F0"),
    ]

    static func forId(_ id: String) -> TagColor {
        palette.first { $0.id == id } ?? palette[0]
    }

    static let defaultTagColors: [String: String] = [
        "Travel": "softBlue",
        "Petrol": "primaryGreen",
        "Meals": "terracotta",
        "Subscriptions": "softCoral",
    ]
}
