import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    let group: TagModel

    @State private var showingTagPicker = false
    @State private var showingTagCreation = false
    @State private var showingGroupRename = false

    private var groupTags: [TagModel] {
        allTags.filter { $0.parentId == group.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var availableTagsToAdd: [TagModel] {
        allTags.filter { !$0.isGroup && $0.parentId != group.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Toggle("Show on home screen", isOn: Binding(
                    get: { group.showOnHome },
                    set: { group.showOnHome = $0; try? modelContext.save() }
                ))
                .tint(Color.brandPrimary)
            }

            Section {
                ForEach(groupTags) { tag in
                    HStack(spacing: Spacing.smd) {
                        Circle()
                            .fill(tag.tagColor.primaryColor)
                            .frame(width: 12, height: 12)
                        Text(tag.name)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            tag.parentId = nil
                            try? modelContext.save()
                        } label: {
                            Label("Remove from group", systemImage: "minus.circle")
                        }
                    }
                }

                Button {
                    showingTagPicker = true
                } label: {
                    HStack(spacing: Spacing.smd) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandPrimary)
                        Text("Add existing tag")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }

                Button {
                    showingTagCreation = true
                } label: {
                    HStack(spacing: Spacing.smd) {
                        Image(systemName: "tag.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandPrimary)
                        Text("New tag")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingGroupRename = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .sheet(isPresented: $showingTagPicker) {
            AddTagToGroupPicker(
                group: group,
                availableTags: availableTagsToAdd,
                onSelect: { tag in
                    tag.parentId = group.id
                    try? modelContext.save()
                    showingTagPicker = false
                },
                onDismiss: { showingTagPicker = false }
            )
        }
        .sheet(isPresented: $showingTagCreation) {
            TagCreationView(initialParentId: group.id, onSave: { _ in
                showingTagCreation = false
            })
        }
        .sheet(isPresented: $showingGroupRename) {
            TagCreationView(editingTag: group, isGroupMode: true)
        }
    }
}

// MARK: - Add Tag to Group Picker

struct AddTagToGroupPicker: View {
    @Environment(\.dismiss) private var dismiss

    let group: TagModel
    let availableTags: [TagModel]
    let onSelect: (TagModel) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableTags) { tag in
                    Button {
                        onSelect(tag)
                    } label: {
                        HStack(spacing: Spacing.smd) {
                            Circle()
                                .fill(tag.tagColor.primaryColor)
                                .frame(width: 12, height: 12)
                            Text(tag.name)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Add tag to \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .overlay {
                if availableTags.isEmpty {
                    ContentUnavailableView {
                        Label("No tags to add", systemImage: "tag")
                    } description: {
                        Text("All tags are already in this group.")
                    }
                }
            }
        }
    }
}
