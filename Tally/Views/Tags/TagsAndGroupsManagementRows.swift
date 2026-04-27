import SwiftUI
import SwiftData

/// Shared tags & groups list rows + sheets (used from Settings and Tags tab).
struct TagsAndGroupsManagementRows: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingTagCreation = false
    @State private var showingGroupCreation = false
    @State private var editingTag: TagModel?

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
            ForEach(allTagsSorted) { tag in
                HStack(spacing: Spacing.smd) {
                    Button {
                        editingTag = tag
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
                    }
                    .buttonStyle(.plain)
                    Toggle("", isOn: Binding(
                        get: { tag.showOnHome },
                        set: { tag.showOnHome = $0 }
                    ))
                    .labelsHidden()
                    .tint(Color.brandPrimary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { deleteTag(tag) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                showingTagCreation = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brandPrimary)
                    Text("Add tag")
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            ForEach(groupsSorted) { group in
                HStack(spacing: Spacing.smd) {
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: Binding(
                        get: { group.showOnHome },
                        set: { group.showOnHome = $0 }
                    ))
                    .labelsHidden()
                    .tint(Color.brandPrimary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleteTag(group) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                showingGroupCreation = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brandPrimary)
                    Text("Add group")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .sheet(isPresented: $showingTagCreation) {
            TagCreationView()
        }
        .sheet(isPresented: $showingGroupCreation) {
            TagCreationView(isGroupMode: true)
        }
        .sheet(item: $editingTag) { tag in
            TagCreationView(editingTag: tag)
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
