import SwiftUI
import SwiftData

struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @Binding var selectedTagIds: [String]

    @State private var expandedGroups: Set<String> = []

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
            tagList
                .background(Color.bgPrimary)
                .navigationTitle(selectedTagIds.isEmpty ? "Select Tags" : "\(selectedTagIds.count) tag\(selectedTagIds.count == 1 ? "" : "s") selected")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
        }
    }

    // MARK: - Tag List

    private var tagList: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    NavigationLink(destination: TagCreationView(
                        initialParentId: nil,
                        embeddedInNavigation: true
                    ) { newId in
                        selectedTagIds = selectedTagIds + [newId]
                    }) {
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

                    NavigationLink(destination: TagCreationView(
                        initialParentId: nil,
                        isGroupMode: true,
                        embeddedInNavigation: true
                    )) {
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

                    NavigationLink(destination: TagCreationView(
                        initialParentId: group.id,
                        embeddedInNavigation: true
                    ) { newId in
                        selectedTagIds = selectedTagIds + [newId]
                    }) {
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

}
