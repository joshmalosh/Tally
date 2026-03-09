import SwiftUI
import SwiftData

struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @Binding var selectedTagIds: [String]

    @State private var isCreating = false
    @State private var isCreatingGroup = false
    @State private var newName = ""
    @State private var newColorId = TagColors.palette[0].id
    @State private var newParentId: String?
    @State private var expandedGroups: Set<String> = []
    @State private var showingGroupPickerSheet = false
    @State private var showingNewGroupFromPicker = false

    private var canSaveNew: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var standaloneTags: [TagModel] {
        tags.filter { $0.parentId == nil && !$0.isGroup }
    }

    private var groupTags: [TagModel] {
        tags.filter { $0.isGroup }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func isSelected(_ tag: TagModel) -> Bool {
        selectedTagIds.contains(tag.id)
    }

    private func toggleTag(_ tag: TagModel) {
        if let idx = selectedTagIds.firstIndex(of: tag.id) {
            selectedTagIds.remove(at: idx)
        } else {
            selectedTagIds.append(tag.id)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isCreating || isCreatingGroup {
                    creationForm
                } else {
                    tagList
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isCreating || isCreatingGroup ? "Back" : "Cancel") {
                        if isCreating || isCreatingGroup {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCreating = false
                                isCreatingGroup = false
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                if isCreating || isCreatingGroup {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if isCreatingGroup { saveNewGroup() }
                            else { saveNewTag() }
                        }
                        .foregroundStyle(canSaveNew ? Color.brandPrimary : Color.textMuted)
                        .disabled(!canSaveNew)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        if isCreatingGroup { return "New Group" }
        if isCreating { return "New Tag" }
        let count = selectedTagIds.count
        if count == 0 { return "Select Tags" }
        return "\(count) tag\(count == 1 ? "" : "s") selected"
    }

    // MARK: - Tag List

    private var tagList: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        resetCreationState(parentId: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { isCreating = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New tag")
                                .font(Fonts.label(14))
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.brandTint)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)

                    Button {
                        resetCreationState(parentId: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { isCreatingGroup = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New group")
                                .font(Fonts.label(14))
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.brandTint)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, Spacing.md)

                if !standaloneTags.isEmpty {
                    ForEach(standaloneTags) { tag in
                        tagRow(tag)
                    }
                }

                if !standaloneTags.isEmpty && !groupTags.isEmpty {
                    Divider()
                        .foregroundStyle(Color.borderColor.opacity(0.5))
                        .padding(.top, Spacing.smd)
                        .padding(.bottom, Spacing.sm)
                }

                if !groupTags.isEmpty {
                    ForEach(groupTags) { group in
                        groupSection(group)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Group Section

    private func groupSection(_ group: TagModel) -> some View {
        let isExpanded = expandedGroups.contains(group.id)
        let children = childrenOf(group)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: Spacing.smd) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 14)

                    Text(group.name)
                        .font(Fonts.body(16))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)

                    if !children.isEmpty {
                        Text("\(children.count)")
                            .font(Fonts.caption(11))
                            .foregroundStyle(Color.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.borderColor.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 44)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(children) { child in
                        tagRow(child, indented: true)
                    }

                    Button {
                        resetCreationState(parentId: group.id)
                        withAnimation(.easeInOut(duration: 0.2)) { isCreating = true }
                    } label: {
                        HStack(spacing: Spacing.smd) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)

                            Text("New tag in \(group.name)")
                                .font(Fonts.body(14))
                                .foregroundStyle(Color.textMuted)

                            Spacer()
                        }
                        .padding(.leading, Spacing.xl + Spacing.smd)
                        .padding(.trailing, Spacing.md)
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tag Row

    private func tagRow(_ tag: TagModel, indented: Bool = false) -> some View {
        let selected = isSelected(tag)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggleTag(tag) }
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 14, height: 14)

                Text(tag.name)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.leading, indented ? Spacing.xl : Spacing.md)
            .padding(.trailing, Spacing.md)
            .frame(height: 43)
            .background(
                selected ? tag.tagColor.primaryColor.opacity(0.06) : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Creation Form

    private var creationForm: some View {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(isCreatingGroup ? "Group name" : "Tag name")
                    .font(Fonts.caption(13))
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: Spacing.smd) {
                    Circle()
                        .fill(TagColors.forId(newColorId).primaryColor)
                        .frame(width: 14, height: 14)

                    TextField(
                        isCreatingGroup ? "e.g. Projects" : "e.g. Office supplies",
                        text: $newName
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

            if isCreating && !isCreatingGroup {
                groupPicker
            }

            colorPicker

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Group (optional)")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            Button { showingGroupPickerSheet = true } label: {
                HStack {
                    if let parentId = newParentId, let group = groupTags.first(where: { $0.id == parentId }) {
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
            .sheet(isPresented: $showingGroupPickerSheet) {
                GroupPickerSheet(
                    groups: groupTags,
                    selectedGroupId: $newParentId,
                    onCreateGroup: {
                        showingGroupPickerSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingNewGroupFromPicker = true
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingNewGroupFromPicker) {
                TagCreationView(isGroupMode: true) { newGroupId in
                    newParentId = newGroupId
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.smd) {
            Text("Color")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.smd), count: 6), spacing: Spacing.smd) {
                ForEach(TagColors.palette) { color in
                    Button { newColorId = color.id } label: {
                        ZStack {
                            Circle()
                                .fill(color.primaryColor)
                                .frame(width: 40, height: 40)

                            if newColorId == color.id {
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

    // MARK: - State Management

    private func resetCreationState(parentId: String?) {
        newName = ""
        newColorId = parentId.flatMap { pid in groupTags.first { $0.id == pid }?.colorId } ?? TagColors.palette[0].id
        newParentId = parentId
    }

    // MARK: - Save

    private func saveNewTag() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<TagModel>())) ?? 0
        let tag = TagModel(
            userId: nil,
            name: trimmed,
            colorId: newColorId,
            sortOrder: count,
            parentId: newParentId
        )
        modelContext.insert(tag)
        do {
            try modelContext.save()
            #if DEBUG
            print("[Tally] Tag saved: \(tag.name) (id: \(tag.id), parent: \(tag.parentId ?? "none"))")
            #endif
        } catch {
            #if DEBUG
            print("[Tally] ERROR saving tag: \(error)")
            #endif
        }

        selectedTagIds.append(tag.id)

        withAnimation(.easeInOut(duration: 0.2)) {
            isCreating = false
        }
    }

    private func saveNewGroup() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<TagModel>())) ?? 0
        let group = TagModel(
            userId: nil,
            name: trimmed,
            colorId: newColorId,
            sortOrder: count,
            parentId: nil,
            isGroup: true
        )
        modelContext.insert(group)
        do {
            try modelContext.save()
            #if DEBUG
            print("[Tally] Group created: \(group.name) (id: \(group.id))")
            #endif
        } catch {
            #if DEBUG
            print("[Tally] ERROR creating group: \(error)")
            #endif
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isCreatingGroup = false
        }
    }
}
