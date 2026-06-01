import Foundation
import SwiftData

@Model
final class TagModel {
    var id: String = UUID().uuidString
    var userId: String?
    var name: String = ""
    var colorId: String = TagColors.defaultNewTagColorId
    var icon: String?
    var symbolName: String?      // SF Symbol name — nil for user-created tags without a symbol
    var isSystemTag: Bool = false // System tags cannot be deleted by the user
    var sortOrder: Int = 0
    var showOnHome: Bool = false
    var parentId: String?
    var isGroup: Bool = false

    init(
        id: String = UUID().uuidString,
        userId: String? = nil,
        name: String = "",
        colorId: String = TagColors.defaultNewTagColorId,
        icon: String? = nil,
        symbolName: String? = nil,
        isSystemTag: Bool = false,
        sortOrder: Int = 0,
        showOnHome: Bool = false,
        parentId: String? = nil,
        isGroup: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.colorId = colorId
        self.icon = icon
        self.symbolName = symbolName
        self.isSystemTag = isSystemTag
        self.sortOrder = sortOrder
        self.showOnHome = showOnHome
        self.parentId = parentId
        self.isGroup = isGroup
    }

    var tagColor: TagColor {
        TagColors.forId(colorId)
    }

    var isChild: Bool { parentId != nil }

    // Legacy defaults (used by the old seeding path — kept for backward compat)
    static let defaults: [(name: String, colorId: String, sortOrder: Int)] = [
        ("Travel", "v7", 0),
        ("Petrol", "v2", 1),
        ("Meals", "v17", 2),
        ("Subscriptions", "v13", 3),
    ]
}

// MARK: - System tag definitions (Section 7)

extension TagModel {
    struct SystemTagDef {
        let name: String
        let colorId: String
        let symbolName: String
        let showOnHome: Bool
        let sortOrder: Int
    }

    static let systemTags: [SystemTagDef] = [
        SystemTagDef(name: "Groceries",         colorId: "v2",  symbolName: "cart.fill",          showOnHome: true,  sortOrder: 100),
        SystemTagDef(name: "Dining & Takeaway",  colorId: "v21", symbolName: "fork.knife",          showOnHome: true,  sortOrder: 101),
        SystemTagDef(name: "Transport",          colorId: "v7",  symbolName: "car.fill",            showOnHome: true,  sortOrder: 102),
        SystemTagDef(name: "Home",               colorId: "v8",  symbolName: "house.fill",          showOnHome: true,  sortOrder: 103),
        SystemTagDef(name: "Shopping",           colorId: "v10", symbolName: "bag.fill",            showOnHome: false, sortOrder: 104),
        SystemTagDef(name: "Subscriptions",      colorId: "v14", symbolName: "creditcard.fill",     showOnHome: false, sortOrder: 105),
        SystemTagDef(name: "Health & Fitness",   colorId: "v18", symbolName: "heart.fill",          showOnHome: false, sortOrder: 106),
        SystemTagDef(name: "Travel",             colorId: "v4",  symbolName: "airplane",            showOnHome: false, sortOrder: 107),
        SystemTagDef(name: "Work",               colorId: "v12", symbolName: "briefcase.fill",      showOnHome: true,  sortOrder: 108),
        SystemTagDef(name: "Entertainment",      colorId: "v22", symbolName: "ticket.fill",         showOnHome: false, sortOrder: 109),
        SystemTagDef(name: "Bills & Utilities",  colorId: "v19", symbolName: "bolt.fill",           showOnHome: false, sortOrder: 110),
        SystemTagDef(name: "Gifts & Donations",  colorId: "v14", symbolName: "gift.fill",           showOnHome: false, sortOrder: 111),
        SystemTagDef(name: "Education",          colorId: "v9",  symbolName: "book.fill",           showOnHome: false, sortOrder: 112),
        SystemTagDef(name: "Other",              colorId: "v5",  symbolName: "ellipsis.circle.fill",showOnHome: false, sortOrder: 113),
    ]
}
