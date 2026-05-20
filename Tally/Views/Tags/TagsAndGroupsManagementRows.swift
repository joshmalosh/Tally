import SwiftUI
import SwiftData

/// Shared tags & groups list rows + sheets (used from Tags tab).
/// Toggle removed — tags are no longer filtered by showOnHome.
struct TagsAndGroupsManagementRows: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    private enum TagSheet: Identifiable {
        case newTag, newGroup, edit(TagModel)
        var id: String {
            switch self {
            case .newTag: return "newTag"
            case .newGroup: return "newGroup"
            case .edit(let t): return t.id
            }
        }
    }

    @State private var activeSheet: TagSheet?

    private var allTagsSorted: [TagModel] {
        tags.filter { !$0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var groupsSorted: [TagModel] {
        tags.filter { $0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Group {
            Text("Tags & Groups")
                .font(.system(size: 28, weight: .bold))
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
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Tags — no toggle
            ForEach(allTagsSorted) { tag in
                Button {
                    activeSheet = .edit(tag)
                } label: {
                    HStack(spacing: Spacing.smd) {
                        Circle()
                            .fill(tag.tagColor.primaryColor)
                            .frame(width: 12, height: 12)
                        Text(tag.name)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { deleteTag(tag) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // Folders — no toggle
            ForEach(groupsSorted) { group in
                NavigationLink {
                    GroupDetailView(group: group)
                } label: {
                    HStack(spacing: Spacing.smd) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(group.tagColor.primaryColor)
                            .frame(width: 12, height: 12)
                        Text(group.name)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                }
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
            #if DEBUG
            print("[Tally] ERROR deleting tag: \(error)")
            #endif
        }
    }
}
