import SwiftUI
import SwiftData

struct TagCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var allExpenses: [ExpenseModel]

    @State private var name = ""
    @State private var showingDeleteConfirmation = false
    @State private var selectedColorId = TagColors.defaultNewTagColorId
    @State private var selectedParentId: String?
    @State private var showingGroupPicker = false
    @State private var showingNewGroup = false

    var editingTag: TagModel? = nil
    var initialParentId: String? = nil
    var isGroupMode: Bool = false
    var embeddedInNavigation: Bool = false  // when true, no NavigationStack, Back shows automatically
    var onSave: ((String) -> Void)? = nil

    private var isEditing: Bool { editingTag != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var availableGroups: [TagModel] {
        allTags.filter { $0.isGroup && $0.id != editingTag?.id }
    }

    private var formContent: some View {
        VStack(spacing: Spacing.lg) {
            nameField
            if !isGroupMode { groupPicker }
            colorGrid
            if isEditing && !isGroupMode { deleteTagButton }
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, embeddedInNavigation ? Spacing.xl : Spacing.md)
        .background(Color.bgPrimary)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embeddedInNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
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
        .alert("Delete \(editingTag?.name ?? "tag")?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDeleteTag() }
        } message: {
            Text("This will remove the tag from all expenses. This cannot be undone.")
        }
    }

    var body: some View {
        if embeddedInNavigation {
            formContent
        } else {
            NavigationStack {
                formContent
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

    private var deleteTagButton: some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .padding(.vertical, Spacing.smd)
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Text("Delete tag")
                    .font(Fonts.body(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.plain)
        }
    }

    private func performDeleteTag() {
        guard let tag = editingTag else { return }
        appState.removeFilter(id: tag.id)
        for expense in allExpenses {
            if expense.resolvedTagIds.contains(tag.id) {
                expense.tagIds = (expense.tagIds ?? []).filter { $0 != tag.id }
                if expense.tagId == tag.id {
                    expense.tagId = (expense.tagIds ?? []).first ?? ""
                }
            }
        }
        modelContext.delete(tag)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            #if DEBUG
            print("[Tally] ERROR deleting tag: \(error)")
            #endif
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
                #if DEBUG
                print("[Tally] Tag updated: \(trimmed)")
                #endif
            } catch {
                #if DEBUG
                print("[Tally] ERROR updating tag: \(error)")
                #endif
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
                #if DEBUG
                print("[Tally] Tag created: \(trimmed) (id: \(tag.id), parent: \(tag.parentId ?? "none"))")
                #endif
            } catch {
                #if DEBUG
                print("[Tally] ERROR creating tag: \(error)")
                #endif
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
