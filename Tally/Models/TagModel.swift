import Foundation
import SwiftData

@Model
final class TagModel {
    var id: String = UUID().uuidString
    var userId: String?
    var name: String = ""
    var colorId: String = "primaryGreen"
    var icon: String?
    var sortOrder: Int = 0
    var showOnHome: Bool = false
    var parentId: String?
    var isGroup: Bool = false

    init(
        id: String = UUID().uuidString,
        userId: String? = nil,
        name: String = "",
        colorId: String = "primaryGreen",
        icon: String? = nil,
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
        self.sortOrder = sortOrder
        self.showOnHome = showOnHome
        self.parentId = parentId
        self.isGroup = isGroup
    }

    var tagColor: TagColor {
        TagColors.forId(colorId)
    }

    var isChild: Bool { parentId != nil }

    static let defaults: [(name: String, colorId: String, sortOrder: Int)] = [
        ("Travel", "softBlue", 0),
        ("Petrol", "primaryGreen", 1),
        ("Meals", "terracotta", 2),
        ("Subscriptions", "softCoral", 3),
    ]
}
