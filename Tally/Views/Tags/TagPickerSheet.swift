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

    init(selectedTagIds: Binding<[String]>) {
        _selectedTagIds = selectedTagIds
        isHomeVisibilityMode = false
    }

    /// Home: toggles `showOnHome` for root-level tags and groups (`parentId == nil`).
    init(homeVisibilityMode: Void) {
        _selectedTagIds = .constant([])
        isHomeVisibilityMode = true
    }

    private var listTags: [TagModel] {
        if isHomeVisibilityMode {
            return tags
                .filter { $0.parentId == nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return tags
            .filter { !$0.isGroup }
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
                        Text("+ New tag")
                            .font(.system(size: 14, weight: .semibold))
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
                        ForEach(listTags) { tag in
                            tagRow(tag)
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
                    workingIds = tags.filter { $0.showOnHome && $0.parentId == nil }.map(\.id)
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
                })
            }
        }
    }

    private func tagRow(_ tag: TagModel) -> some View {
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
            .frame(height: 44)
            .background(selected ? tag.tagColor.primaryColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func confirmDone() {
        if isHomeVisibilityMode {
            for tag in tags where tag.parentId == nil {
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
