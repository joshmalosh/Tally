import SwiftUI
import OSLog
import SwiftData
import UIKit

/// Shared tags & groups list rows + sheets (used from Tags tab).
struct TagsAndGroupsManagementRows: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]

    // Management list stays A–Z by default; the filter button can re-sort it.
    @State private var sortOrder: TagSortOrder = .aToZ

    private enum TagSheet: Identifiable {
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

    @State private var activeSheet: TagSheet?

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

    var body: some View {
        Group {
            Text("Tags & Groups")
                .font(.dmSerifDisplay(28))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
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
                        Text("Add tag")
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
                        Text("Add folder")
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

            // Tags — home-bar toggle (own tap target) + tap-anywhere-else-to-edit.
            // Uses onTapGesture (not an outer Button) so it doesn't fight the inner
            // HomeToggle Button for the tap — a real Button always wins hit-testing
            // over an ancestor's onTapGesture, a plain ancestor Button can't guarantee that.
            ForEach(allTagsSorted) { tag in
                HStack(spacing: Spacing.smd) {
                    Circle()
                        .fill(tag.tagColor.primaryColor)
                        .frame(width: 12, height: 12)
                    Text(tag.name)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    HomeToggle(isOn: tag.showOnHome) {
                        tag.showOnHome.toggle()
                        do {
                            try modelContext.save()
                        } catch {
                            Log.data.error("toggling showOnHome failed: \(error.localizedDescription, privacy: .public)")
                        }
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
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
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(group.tagColor.primaryColor)
                            .frame(width: 12, height: 12)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newTag:
                TagCreationView(suppressNameFieldAutofocus: true)
            case .newGroup:
                TagCreationView(isGroupMode: true, suppressNameFieldAutofocus: true)
            case .edit(let tag):
                TagCreationView(editingTag: tag, suppressNameFieldAutofocus: true)
            case .groupDetail(let group):
                // GroupDetailView needs its own NavigationStack because it uses
                // .navigationTitle and toolbar items (push-nav semantics via sheet).
                NavigationStack {
                    GroupDetailView(group: group)
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
