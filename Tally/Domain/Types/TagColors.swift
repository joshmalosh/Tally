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
    // 30 vibrant colours, 6 columns × 5 rows
    static let palette: [TagColor] = [
        // Row 1 — Greens
        TagColor(id: "v1",  primary: "6B7A3A", tint: "F0F2ED"),
        TagColor(id: "v2",  primary: "3D9E6A", tint: "E8F5ED"),   // mint — default for new tags
        TagColor(id: "v3",  primary: "1A7A5E", tint: "E5F1EC"),
        TagColor(id: "v4",  primary: "26C4A0", tint: "E6F7F3"),
        TagColor(id: "v5",  primary: "5BA08A", tint: "EBF4F1"),
        TagColor(id: "v6",  primary: "2D8C8C", tint: "E6F2F2"),
        // Row 2 — Blues & Purples
        TagColor(id: "v7",  primary: "6AABDB", tint: "EEF6FC"),
        TagColor(id: "v8",  primary: "4A7FC1", tint: "EAF1FA"),
        TagColor(id: "v9",  primary: "3A5FA0", tint: "E8EDF6"),
        TagColor(id: "v10", primary: "9B7FD4", tint: "F3EFFA"),
        TagColor(id: "v11", primary: "7B5EA8", tint: "F0ECF6"),
        TagColor(id: "v12", primary: "6C3483", tint: "EDEAF1"),
        // Row 3 — Pinks & Reds
        TagColor(id: "v13", primary: "F48FB1", tint: "FDF2F5"),
        TagColor(id: "v14", primary: "E8789A", tint: "FCEFF3"),
        TagColor(id: "v15", primary: "C2637A", tint: "F9ECEF"),
        TagColor(id: "v16", primary: "A0405A", tint: "F5E8EB"),
        TagColor(id: "v17", primary: "E8786A", tint: "FCEFED"),
        TagColor(id: "v18", primary: "C0392B", tint: "F9EBE9"),
        // Row 4 — Yellows, Oranges & Warm
        TagColor(id: "v19", primary: "F5D000", tint: "FDF9E6"),
        TagColor(id: "v20", primary: "F0C419", tint: "FDF8E8"),
        TagColor(id: "v21", primary: "F0A500", tint: "FDF6E6"),
        TagColor(id: "v22", primary: "E07840", tint: "FBF1EA"),
        TagColor(id: "v23", primary: "C0783A", tint: "F9EFE6"),
        TagColor(id: "v24", primary: "E8A84A", tint: "FCF5E9"),
        // Row 5 — Fun & Accent
        TagColor(id: "v25", primary: "FF6B9D", tint: "FFF0F5"),
        TagColor(id: "v26", primary: "C2185B", tint: "F9E8EE"),
        TagColor(id: "v27", primary: "7C4DFF", tint: "F3EEFC"),
        TagColor(id: "v28", primary: "00BCD4", tint: "E6F8FA"),
        TagColor(id: "v29", primary: "FF7043", tint: "FFF0EB"),
        TagColor(id: "v30", primary: "8BC34A", tint: "F2F8E9"),
    ]

    /// Default colour when creating a new tag — #3D9E6A (Mint)
    static let defaultNewTagColorId = "v2"

    static func forId(_ id: String) -> TagColor {
        palette.first { $0.id == id } ?? palette[1]  // fallback to mint (v2)
    }

    static let defaultTagColors: [String: String] = [
        "Travel": "v7",
        "Petrol": "v2",
        "Meals": "v17",
        "Subscriptions": "v13",
    ]
}
