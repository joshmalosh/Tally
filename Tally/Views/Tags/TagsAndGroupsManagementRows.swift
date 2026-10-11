import SwiftUI
import OSLog
import SwiftData
import UIKit

/// Which tag/group sheet is open. Owned by `TagsTabView` and presented from the
/// List container (not from inside a row) — a `.sheet` attached to a recycling
/// List row opened and then immediately dismissed on the first tap.
enum TagSheet: Identifiable {
    case newTag, newGroup, edit(TagModel), groupDetail(TagModel)
    var id: String {
        switch self {
        case .newTag: return "newTag"
        case .newGroup: return "newGroup"
        case .edit(let t): return "edit_\(t.id)"
        case .groupDetail(let g): return "group_\(g.id)"
        }
    }
}

/// Shared tags & groups list rows (used from the Tags tab). The sheet it drives
/// is presented by the parent `TagsTabView`, not here.
struct TagsAndGroupsManagementRows: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]

    // Management list stays A–Z by default; the filter button can re-sort it.
    @State private var sortOrder: TagSortOrder = .aToZ

    @Binding var activeSheet: TagSheet?

    private var recency: [String: Date] { tagRecency(from: expenses) }

    private var allTagsSorted: [TagModel] {
        tags.filter { !$0.isGroup }.sortedForDisplay(sortOrder, recency: recency)
    }

    private var groupsSorted: [TagModel] {
        tags.filter { $0.isGroup }.sortedForDisplay(sortOrder, recency: recency)
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Circular colour swatch with the tag's emoji — shared `TagIconBadge` so the
    /// Tags tab, pin-to-home sheet and filter sheet always match.
    private func colorBadge(for tag: TagModel) -> some View {
        TagIconBadge(tag: tag)
    }

    var body: some View {
        Group {
          Section {
            // Plain serif title, no eyebrow — matches Insights and Reports, which
            // both dropped their mini-heading.
            VStack(alignment: .leading, spacing: 4) {
                Text("Tags & Groups")
                    .font(.dmSerifDisplay(30))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Add tag / Add folder buttons
            HStack(spacing: 10) {
                Button {
                    activeSheet = .newTag
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                        Text("Add Tag")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .foregroundStyle(Color(hex: "2F402E"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button {
                    activeSheet = .newGroup
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                        Text("Add Group")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .foregroundStyle(Color(hex: "2F402E"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                TagSortMenu(order: $sortOrder)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }

          // The tags & groups themselves, as one rounded white card.
          Section {
            // Tags — home-bar toggle (own tap target) + tap-anywhere-else-to-edit.
            // Uses onTapGesture (not an outer Button) so it doesn't fight the inner
            // HomeToggle Button for the tap — a real Button always wins hit-testing
            // over an ancestor's onTapGesture, a plain ancestor Button can't guarantee that.
            ForEach(allTagsSorted) { tag in
                HStack(spacing: Spacing.smd) {
                    colorBadge(for: tag)
                    Text(tag.name)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    HomeToggle(isOn: tag.showOnHome) {
                        // Mutate only; SwiftData autosave coalesces the write (and
                        // flushes on backgrounding). No per-tap disk write + export.
                        tag.showOnHome.toggle()
                        Haptics.crisp()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeSheet = .edit(tag)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { deleteTag(tag) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // Folders — present as sheet (no NavigationStack in parent overlay)
            ForEach(groupsSorted) { group in
                Button {
                    activeSheet = .groupDetail(group)
                } label: {
                    HStack(spacing: Spacing.smd) {
                        colorBadge(for: group)
                        Text(group.name)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleteTag(group) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
          }
        }
    }

    private func deleteTag(_ tag: TagModel) {
        appState.removeFilter(id: tag.id)
        if tag.isGroup {
            for child in childrenOf(tag) {
                appState.removeFilter(id: child.id)
                child.parentId = nil
            }
        }
        modelContext.delete(tag)
        do {
            try modelContext.save()
        } catch {
            Log.data.error("deleting tag failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
