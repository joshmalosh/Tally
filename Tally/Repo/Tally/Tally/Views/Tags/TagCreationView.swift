import SwiftUI
import SwiftData

struct TagCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    @State private var name = ""
    @State private var selectedColorId = TagColors.palette[0].id
    @State private var selectedParentId: String?
    @State private var showingGroupPicker = false
    @State private var showingNewGroup = false

    var editingTag: TagModel? = nil
    var initialParentId: String? = nil
    var isGroupMode: Bool = false
    var onSave: ((String) -> Void)? = nil

    private var isEditing: Bool { editingTag != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var availableGroups: [TagModel] {
        allTags.filter { $0.isGroup && $0.id != editingTag?.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                nameField
                if !isGroupMode { groupPicker }
                colorGrid
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .background(Color.bgPrimary)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color.brandPrimary : Color.textMuted)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let tag = editingTag {
                    name = tag.name
                    selectedColorId = tag.colorId
                    selectedParentId = tag.parentId
                } else {
                    selectedParentId = initialParentId
                }
            }
        }
    }

    private var navigationTitle: String {
        if isGroupMode {
            return isEditing ? "Edit Group" : "New Group"
        }
        return isEditing ? "Edit Tag" : "New Tag"
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(isGroupMode ? "Group name" : "Tag name")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(TagColors.forId(selectedColorId).primaryColor)
                    .frame(width: 12, height: 12)

                TextField(
                    isGroupMode ? "e.g. Projects" : "e.g. Office supplies",
                    text: $name
                )
                .font(Fonts.body(16))
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 48)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.borderColor, lineWidth: 1)
            )
        }
    }

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Group (optional)")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            Button { showingGroupPicker = true } label: {
                HStack {
                    if let parentId = selectedParentId,
                       let group = allTags.first(where: { $0.id == parentId }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(group.tagColor.primaryColor)
                            Text(group.name)
                                .font(Fonts.body(15))
                                .foregroundStyle(Color.textPrimary)
                        }
                    } else {
                        Text("None")
                            .font(Fonts.body(15))
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 48)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingGroupPicker) {
                GroupPickerSheet(
                    groups: availableGroups,
                    selectedGroupId: $selectedParentId,
                    onCreateGroup: {
                        showingGroupPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingNewGroup = true
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingNewGroup) {
                TagCreationView(isGroupMode: true) { newGroupId in
                    selectedParentId = newGroupId
                }
            }
        }
    }

    private var colorGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.smd) {
            Text("Color")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.smd), count: 6), spacing: Spacing.smd) {
                ForEach(TagColors.palette) { color in
                    Button { selectedColorId = color.id } label: {
                        ZStack {
                            Circle()
                                .fill(color.primaryColor)
                                .frame(width: 40, height: 40)

                            if selectedColorId == color.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let tag = editingTag {
            tag.name = trimmed
            tag.colorId = selectedColorId
            if !isGroupMode { tag.parentId = selectedParentId }
            do {
                try modelContext.save()
                print("[Tally] Tag updated: \(trimmed)")
            } catch {
                print("[Tally] ERROR updating tag: \(error)")
            }
            dismiss()
        } else {
            let count = (try? modelContext.fetchCount(FetchDescriptor<TagModel>())) ?? 0
            let tag = TagModel(
                userId: nil,
                name: trimmed,
                colorId: selectedColorId,
                sortOrder: count,
                parentId: isGroupMode ? nil : selectedParentId,
                isGroup: isGroupMode
            )
            modelContext.insert(tag)
            do {
                try modelContext.save()
                print("[Tally] Tag created: \(trimmed) (id: \(tag.id), parent: \(tag.parentId ?? "none"))")
            } catch {
                print("[Tally] ERROR creating tag: \(error)")
            }
            let savedId = tag.id
            dismiss()
            onSave?(savedId)
        }
    }
}

// MARK: - Group Picker Sheet

struct GroupPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let groups: [TagModel]
    @Binding var selectedGroupId: String?
    var onCreateGroup: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedGroupId = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .font(Fonts.body(15))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if selectedGroupId == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                    }

                    ForEach(groups) { group in
                        Button {
                            selectedGroupId = group.id
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.smd) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(group.tagColor.primaryColor)
                                Text(group.name)
                                    .font(Fonts.body(15))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if selectedGroupId == group.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.brandPrimary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        onCreateGroup()
                    } label: {
                        HStack(spacing: Spacing.smd) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Create new group")
                                .font(Fonts.body(15))
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Select Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
    }
}
