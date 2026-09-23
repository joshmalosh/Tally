import SwiftUI
import SwiftData

/// Shared tag picker: single selection — one standalone tag, one group, or one
/// of a group's sub-tags. Visual language matches the Tags tab
/// (serif heading, white Add tag / Add folder buttons, white card list).
struct SharedTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]

    @Binding private var selectedTagIds: [String]

    @State private var showingNewTag = false
    @State private var showingNewGroup = false
    // Picker defaults to the tags you reach for most often.
    @State private var sortOrder: TagSortOrder = .recent

    init(selectedTagIds: Binding<[String]>) {
        _selectedTagIds = selectedTagIds
    }

    // Sweep the whole expense history at most ONCE per open — and only when the
    // list is actually ordered by Recent. Reading this as a computed property
    // re-ran the sweep for every peer group and froze the picker on a device
    // with a real (CloudKit-faulted) expense history. Compute it in `body` and
    // thread it into the sort helpers instead.
    private func recency() -> [String: Date] {
        sortOrder == .recent ? tagRecency(from: expenses) : [:]
    }

    private func standaloneTags(_ recency: [String: Date]) -> [TagModel] {
        tags.filter { !$0.isGroup && $0.parentId == nil }
            .sortedForDisplay(sortOrder, recency: recency)
    }

    private func groups(_ recency: [String: Date]) -> [TagModel] {
        tags.filter { $0.isGroup }
            .sortedForDisplay(sortOrder, recency: recency)
    }

    private func childTags(of group: TagModel, recency: [String: Date]) -> [TagModel] {
        tags.filter { $0.parentId == group.id }
            .sortedForDisplay(sortOrder, recency: recency)
    }

    private var selectedId: String? { selectedTagIds.first }

    var body: some View {
        // One sweep per render, shared by every list below.
        let recency = recency()
        let standaloneTags = standaloneTags(recency)
        let groups = groups(recency)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Eyebrow + serif title, matching the Tags & Groups screen so
                    // the picker reads as part of the same platform.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TAG THIS EXPENSE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .tracking(1.2)
                        Text("Select tag")
                            .font(.dmSerifDisplay(30))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // Add tag / Add folder — same style as the Tags tab
                    HStack(spacing: 10) {
                        createButton(icon: "plus.circle", title: "Add tag") {
                            showingNewTag = true
                        }
                        createButton(icon: "folder.badge.plus", title: "Add folder") {
                            showingNewGroup = true
                        }
                        TagSortMenu(order: $sortOrder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    if !tags.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(standaloneTags.enumerated()), id: \.element.id) { index, tag in
                                tagRow(tag)
                                if index < standaloneTags.count - 1 || !groups.isEmpty {
                                    rowDivider
                                }
                            }

                            ForEach(Array(groups.enumerated()), id: \.element.id) { gIndex, group in
                                groupRow(group)

                                ForEach(childTags(of: group, recency: recency), id: \.id) { child in
                                    rowDivider
                                    childRow(child)
                                }

                                if gIndex < groups.count - 1 {
                                    rowDivider
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
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
        Haptics.tap()
        if selectedId == id {
            selectedTagIds = []
        } else {
            selectedTagIds = [id]
        }
        dismiss()
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 44)
    }

    private func createButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
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

    private func tagRow(_ tag: TagModel) -> some View {
        FilterRow(
            title: tag.name,
            titleFont: .system(size: 17),
            isSelected: selectedId == tag.id,
            checkmarkFont: .system(size: 15, weight: .semibold),
            horizontalPadding: 16,
            verticalPadding: 12,
            leading: {
                TagIconBadge(tag: tag)
            }
        ) {
            select(tag.id)
        }
    }

    private func groupRow(_ group: TagModel) -> some View {
        FilterRow(
            title: group.name,
            titleFont: .system(size: 17),
            isSelected: selectedId == group.id,
            checkmarkFont: .system(size: 15, weight: .semibold),
            horizontalPadding: 16,
            verticalPadding: 12,
            leading: {
                TagIconBadge(tag: group)
            }
        ) {
            select(group.id)
        }
    }

    private func childRow(_ child: TagModel) -> some View {
        FilterRow(
            title: child.name,
            titleFont: .system(size: 16),
            titleColor: Color(hex: "4A5E50"),
            isSelected: selectedId == child.id,
            checkmarkFont: .system(size: 14, weight: .semibold),
            horizontalPadding: 16,
            verticalPadding: 10,
            leading: {
                TagIconBadge(tag: child, size: 28)
                    .padding(.leading, 24)
            }
        ) {
            select(child.id)
        }
    }
}
