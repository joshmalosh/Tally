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
            HStack(spacing: 10) {
                Button {
                    showingTagCreation = true
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
                    showingGroupCreation = true
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
                        }
                    }

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
