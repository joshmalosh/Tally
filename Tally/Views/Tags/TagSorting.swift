import SwiftUI

/// Shared ordering for every tag list. The expense tag picker defaults to
/// `.recent`; the management list (Tags tab + Settings) defaults to `.aToZ`.
/// The filter button lets either be re-sorted.
enum TagSortOrder: String, CaseIterable {
    case recent, aToZ, zToA

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .aToZ:   return "A–Z"
        case .zToA:   return "Z–A"
        }
    }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .aToZ:   return "arrow.up"
        case .zToA:   return "arrow.down"
        }
    }
}

extension Array where Element == TagModel {
    /// Order this peer group (standalone tags, groups, or one group's children).
    /// `recency` is the latest expense date per tag id; a tag never applied to an
    /// expense sorts after used ones, then alphabetically, so the list is never
    /// arbitrary.
    func sortedForDisplay(_ order: TagSortOrder, recency: [String: Date]) -> [TagModel] {
        switch order {
        case .aToZ:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .zToA:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .recent:
            return sorted { a, b in
                switch (recency[a.id], recency[b.id]) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }
    }
}

/// Latest expense date per tag id, for `.recent` ordering. Derived from
/// expenses, so there is no `lastUsedAt` field to migrate or keep in sync.
func tagRecency(from expenses: [ExpenseModel]) -> [String: Date] {
    var map: [String: Date] = [:]
    for expense in expenses {
        for id in expense.resolvedTagIds {
            map[id] = Swift.max(map[id] ?? .distantPast, expense.date)
        }
    }
    return map
}

/// The A–Z / Z–A / Recent control. Sized to sit beside the Add tag / Add folder
/// buttons, shrinking them to make room.
struct TagSortMenu: View {
    @Binding var order: TagSortOrder

    var body: some View {
        Menu {
            Picker("Sort", selection: $order) {
                ForEach(TagSortOrder.allCases, id: \.self) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "2F402E"))
                .frame(width: 44)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        }
    }
}
