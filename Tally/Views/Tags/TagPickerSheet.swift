import SwiftUI
import SwiftData

/// Shared tag picker: single selection — one standalone tag, one group, or one
/// of a group's sub-tags. Visual language matches the Home filter sheet
/// (white card, dividers, full-row press-flash via the shared FilterRow).
struct SharedTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @Binding private var selectedTagIds: [String]

    @State private var showingNewTag = false
    @State private var showingNewGroup = false

    init(selectedTagIds: Binding<[String]>) {
        _selectedTagIds = selectedTagIds
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

    private var selectedId: String? { selectedTagIds.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    createButtons

                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags & groups")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(standaloneTags.enumerated()), id: \.element.id) { index, tag in
                                    tagRow(tag)
                                    if index < standaloneTags.count - 1 || !groups.isEmpty {
                                        Divider().padding(.horizontal, 20)
                                    }
                                }

                                ForEach(Array(groups.enumerated()), id: \.element.id) { gIndex, group in
                                    FilterRow(
                                        title: group.name,
                                        titleFont: .system(size: 16),
                                        isSelected: selectedId == group.id,
                                        checkmarkFont: .system(size: 14, weight: .semibold),
                                        verticalPadding: 13,
                                        leading: {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(group.tagColor.primaryColor)
                                        }
                                    ) {
                                        select(group.id)
                                    }

                                    let children = childTags(of: group)
                                    ForEach(children, id: \.id) { child in
                                        Divider().padding(.horizontal, 20)
                                        FilterRow(
                                            title: child.name,
                                            titleFont: .system(size: 15),
                                            titleColor: Color(hex: "4A5E50"),
                                            isSelected: selectedId == child.id,
                                            checkmarkFont: .system(size: 13, weight: .semibold),
                                            horizontalPadding: 20,
                                            verticalPadding: 11,
                                            leading: {
                                                Circle()
                                                    .fill(child.tagColor.primaryColor)
                                                    .frame(width: 8, height: 8)
                                                    .padding(.leading, 16)
                                            }
                                        ) {
                                            select(child.id)
                                        }
                                    }

                                    if gIndex < groups.count - 1 {
                                        Divider().padding(.horizontal, 20)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .navigationTitle("Select tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingNewTag) {
                TagCreationView(onSave: { newId in
                    selectedTagIds = [newId]
                    dismiss()
                }, suppressNameFieldAutofocus: true)
            }
            .sheet(isPresented: $showingNewGroup) {
                TagCreationView(isGroupMode: true, onSave: { newId in
                    selectedTagIds = [newId]
                    dismiss()
                }, suppressNameFieldAutofocus: true)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .ignoresSafeArea(.keyboard)
    }

    /// Single selection: tapping a row selects it exclusively and dismisses;
    /// tapping the current selection clears it.
    private func select(_ id: String) {
        if selectedId == id {
            selectedTagIds = []
        } else {
            selectedTagIds = [id]
        }
        dismiss()
    }

    private var createButtons: some View {
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
                .foregroundStyle(Color(hex: "2F402E"))
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
                .foregroundStyle(Color(hex: "2F402E"))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "E8F0EA"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func tagRow(_ tag: TagModel) -> some View {
        FilterRow(
            title: tag.name,
            titleFont: .system(size: 16),
            isSelected: selectedId == tag.id,
            checkmarkFont: .system(size: 14, weight: .semibold),
            verticalPadding: 13,
            leading: {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 10, height: 10)
            }
        ) {
            select(tag.id)
        }
    }
}
