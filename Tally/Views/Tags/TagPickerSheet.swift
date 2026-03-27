import SwiftUI
import SwiftData

/// Shared tag picker: expense multi-select (non-group tags, A–Z) or home row visibility (root tags & groups, A–Z).
struct SharedTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @Binding private var selectedTagIds: [String]
    private let isHomeVisibilityMode: Bool

    @State private var workingIds: [String] = []
    @State private var showingNewTag = false
    @State private var showingNewGroup = false
    @State private var expandedGroupIds: Set<String> = []
    @State private var showingNewTagInGroup: TagModel?

    init(selectedTagIds: Binding<[String]>) {
        _selectedTagIds = selectedTagIds
        isHomeVisibilityMode = false
    }

    /// Home: toggles `showOnHome` for root-level tags and groups (`parentId == nil`).
    init(homeVisibilityMode: Void) {
        _selectedTagIds = .constant([])
        isHomeVisibilityMode = true
    }

    private var standaloneTags: [TagModel] {
        tags
            .filter { !$0.isGroup && $0.parentId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var groups: [TagModel] {
        tags
            .filter { $0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func childTags(of group: TagModel) -> [TagModel] {
        tags
            .filter { $0.parentId == group.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var navigationTitle: String {
        if workingIds.isEmpty { return "Select tags" }
        if workingIds.count == 1 { return "1 tag selected" }
        return "\(workingIds.count) tags selected"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        showingNewTag = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("New tag")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: "346049"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: "E8F0EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingNewGroup = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("New group")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: "346049"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: "E8F0EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Standalone tags (no group)
                        ForEach(standaloneTags) { tag in
                            tagRow(tag, indent: false)
                        }

                        // Groups with expandable children
                        ForEach(groups) { group in
                            groupRow(group)

                            if expandedGroupIds.contains(group.id) {
                                ForEach(childTags(of: group)) { tag in
                                    tagRow(tag, indent: true)
                                }

                                // "New tag in this group" row
                                Button {
                                    showingNewTagInGroup = group
                                } label: {
                                    HStack(spacing: Spacing.smd) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color(hex: "346049"))
                                        Text("New tag in \(group.name)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color(hex: "346049"))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.leading, 20)
                                    .frame(height: 40)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { confirmDone() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: "346049"))
                }
            }
            .onAppear {
                if isHomeVisibilityMode {
                    let ids = Set(
                        standaloneTags.map(\.id)
                            + groups.map(\.id)
                            + groups.flatMap { childTags(of: $0).map(\.id) }
                    )
                    workingIds = tags.filter { $0.showOnHome && ids.contains($0.id) }.map(\.id)
                } else {
                    workingIds = selectedTagIds
                }
            }
            .sheet(isPresented: $showingNewTag) {
                TagCreationView(onSave: { newId in
                    if !workingIds.contains(newId) {
                        workingIds.append(newId)
                    }
                })
            }
            .sheet(isPresented: $showingNewGroup) {
                TagCreationView(isGroupMode: true, onSave: { newId in
                    if !workingIds.contains(newId) {
                        workingIds.append(newId)
                    }
                    expandedGroupIds.insert(newId)
                })
            }
            .sheet(item: $showingNewTagInGroup) { group in
                TagCreationView(initialParentId: group.id, onSave: { newId in
                    if !workingIds.contains(newId) {
                        workingIds.append(newId)
                    }
                    // Keep the group expanded so the new tag is visible
                    expandedGroupIds.insert(group.id)
                })
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: TagModel) -> some View {
        let isExpanded = expandedGroupIds.contains(group.id)
        let children = childTags(of: group)
        let selectedChildCount = children.filter { workingIds.contains($0.id) }.count

        if isHomeVisibilityMode {
            HStack(spacing: Spacing.smd) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedGroupIds.remove(group.id)
                        } else {
                            expandedGroupIds.insert(group.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if let i = workingIds.firstIndex(of: group.id) {
                            workingIds.remove(at: i)
                        } else {
                            workingIds.append(group.id)
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.smd) {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 14))
                            .foregroundStyle(group.tagColor.primaryColor)
                            .frame(width: 14, height: 14)

                        Text(group.name)
                            .font(Fonts.body(16))
                            .foregroundStyle(Color.textPrimary)

                        if selectedChildCount > 0 {
                            Text("\(selectedChildCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(hex: "346049"))
                                .clipShape(Capsule())
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGroupIds.remove(group.id)
                    } else {
                        expandedGroupIds.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: Spacing.smd) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 14))
                        .foregroundStyle(group.tagColor.primaryColor)
                        .frame(width: 14, height: 14)

                    Text(group.name)
                        .font(Fonts.body(16))
                        .foregroundStyle(Color.textPrimary)

                    if selectedChildCount > 0 {
                        Text("\(selectedChildCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(hex: "346049"))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 44)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private func tagRow(_ tag: TagModel, indent: Bool) -> some View {
        let selected = workingIds.contains(tag.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if let i = workingIds.firstIndex(of: tag.id) {
                    workingIds.remove(at: i)
                } else {
                    workingIds.append(tag.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 14, height: 14)

                Text(tag.name)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "346049"))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.leading, indent ? 20 : 0)
            .frame(height: 44)
            .background(selected ? tag.tagColor.primaryColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func confirmDone() {
        if isHomeVisibilityMode {
            let selectableIds = Set(
                standaloneTags.map(\.id)
                    + groups.map(\.id)
                    + groups.flatMap { childTags(of: $0).map(\.id) }
            )
            for tag in tags where selectableIds.contains(tag.id) {
                tag.showOnHome = workingIds.contains(tag.id)
            }
            do {
                try modelContext.save()
            } catch {
                #if DEBUG
                print("[Tally] ERROR saving home tag visibility: \(error)")
                #endif
            }
        } else {
            selectedTagIds = workingIds
        }
        dismiss()
    }
}
