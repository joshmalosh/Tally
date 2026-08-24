import SwiftUI
import OSLog
import SwiftData
import UIKit

struct TagCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    @State private var name = ""
    @State private var showingDeleteConfirmation = false
    @State private var selectedColorId = TagColors.defaultNewTagColorId
    @State private var selectedParentId: String?
    @State private var showingGroupPicker = false
    @State private var showingNewGroup = false
    @State private var selectedIcon: String? = nil
    @State private var showingColorPicker = false
    @State private var showingDuplicateAlert = false

    var editingTag: TagModel? = nil
    var initialParentId: String? = nil
    var isGroupMode: Bool = false
    var embeddedInNavigation: Bool = false  // when true, no NavigationStack, Back shows automatically
    var onSave: ((String) -> Void)? = nil
    /// When true (e.g. nested sheet from tag picker), do not auto-activate the name field — avoids keyboard resizing the parent sheet.
    var suppressNameFieldAutofocus: Bool = true

    @FocusState private var isNameFieldFocused: Bool

    private var isEditing: Bool { editingTag != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var accentColor: Color { TagColors.forId(selectedColorId).primaryColor }

    private var availableGroups: [TagModel] {
        allTags.filter { $0.isGroup && $0.id != editingTag?.id }
    }

    private var eyebrowText: String {
        if isGroupMode { return isEditing ? "EDIT GROUP" : "NEW GROUP" }
        return isEditing ? "EDIT TAG" : "NEW TAG"
    }

    private var saveButtonLabel: String {
        if isGroupMode { return isEditing ? "Save changes" : "Create group" }
        return isEditing ? "Save changes" : "Create tag"
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                nameCard

                if !isGroupMode {
                    groupCard
                }

                HStack(spacing: Spacing.sm) {
                    colorCard
                    iconCard
                }

                if isEditing && !isGroupMode { deleteTagButton }

                saveButton
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.md)
            .padding(.top, embeddedInNavigation ? Spacing.xl : Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .ignoresSafeArea(.keyboard)
        .onTapGesture {
            isNameFieldFocused = false
        }
        .background(Color.bgPrimary)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embeddedInNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Text(eyebrowText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.6))
                    .tracking(1.5)
            }
        }
        .onAppear {
            if let tag = editingTag {
                name = tag.name
                selectedColorId = tag.colorId
                selectedParentId = tag.parentId
                // Only keep the stored icon if it's already an emoji; legacy
                // SF-symbol icons start empty so the field never shows a raw name.
                selectedIcon = (tag.icon?.isSingleEmoji == true) ? tag.icon : nil
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
        .alert("Already exists", isPresented: $showingDuplicateAlert) {
            Button("OK") {}
        } message: {
            Text("A \(isGroupMode ? "group" : "tag") named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.")
        }
        .sheet(isPresented: $showingColorPicker) {
            TagColorPickerSheet(selectedColorId: $selectedColorId)
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

    // MARK: - Name card
    // Mirrors Quick Add's MERCHANT card: caps label inside the card, serif input below.

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isGroupMode ? "GROUP NAME" : "TAG NAME")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                .tracking(1.0)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            TextField(
                isGroupMode ? "e.g. Projects" : "e.g. Office supplies",
                text: $name
            )
            .id("tagCreationNameField")
            .font(Font.dmSerifDisplay(22))
            .foregroundStyle(Color(hex: "1C1C1E"))
            .autocorrectionDisabled()
            .focused($isNameFieldFocused)
            .tint(accentColor)
            .padding(.horizontal, 14)
            .onAppear {
                // Only focus if explicitly allowed — prevents keyboard from
                // pushing up the sheet content when opened from tag picker.
                if !suppressNameFieldAutofocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isNameFieldFocused = true
                    }
                }
            }
        }
        .padding(.bottom, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
    }

    // MARK: - Group card
    // Mirrors Quick Add's compact DATE card: icon chip + stacked caps label/value.

    private var selectedGroup: TagModel? {
        selectedParentId.flatMap { id in allTags.first(where: { $0.id == id }) }
    }

    private var groupCard: some View {
        Button { showingGroupPicker = true } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "F0EDEA"))
                        .frame(width: 30, height: 30)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedGroup?.tagColor.primaryColor ?? Color(hex: "8F9E94"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("GROUP")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                        .tracking(0.6)
                    Text(selectedGroup?.name ?? "None")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedGroup == nil ? Color(hex: "9CA3AF") : Color(hex: "1C1C1E"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
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

    // MARK: - Color / Icon cards
    // Mirror Quick Add's compact DATE + Add Receipt row: two half-width cards, side by side.

    private var colorCard: some View {
        Button { showingColorPicker = true } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 22, height: 22)
                Text("Color")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.75))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var iconCard: some View {
        HStack(spacing: 8) {
            Text("Icon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "2F402E").opacity(0.75))
            Text("Tap to pick an emoji")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "8F9E94"))
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                EmojiInput(emoji: Binding(
                    get: { selectedIcon ?? "" },
                    set: { selectedIcon = $0.isEmpty ? nil : $0 }
                ))
                .frame(width: 34, height: 34)
                if (selectedIcon ?? "").isEmpty {
                    Text("🏷️").font(.system(size: 15)).opacity(0.35).allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
    }

    // MARK: - Delete + Save

    private var deleteTagButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Text("Delete tag")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.danger.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            save()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                Text(saveButtonLabel)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSave ? Color(hex: "2F402E") : Color(hex: "2F402E").opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.top, Spacing.xs)
    }

    private func performDeleteTag() {
        guard let tag = editingTag else { return }
        appState.removeFilter(id: tag.id)
        let descriptor = FetchDescriptor<ExpenseModel>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        for expense in expenses {
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
            Log.data.error("delete tag failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Block duplicates: same name (case-insensitive) at the same level — a
        // group, or a tag under the same parent. Different groups can each hold a
        // "Groceries", so parent and isGroup are part of the identity.
        let parent = isGroupMode ? nil : selectedParentId
        let isDuplicate = allTags.contains { other in
            other.id != editingTag?.id
                && other.isGroup == isGroupMode
                && other.parentId == parent
                && other.name.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isDuplicate else { showingDuplicateAlert = true; return }

        if let tag = editingTag {
            tag.name = trimmed
            tag.colorId = selectedColorId
            tag.icon = selectedIcon
            if !isGroupMode {
                tag.parentId = selectedParentId
            }
            do {
                try modelContext.save()
                Log.data.debug("tag updated id=\(tag.id, privacy: .public) name=\(trimmed, privacy: .private)")
            } catch {
                Log.data.error("update tag failed: \(error.localizedDescription, privacy: .public)")
            }
            dismiss()
        } else {
            let count = (try? modelContext.fetch(FetchDescriptor<TagModel>()))?.count ?? 0
            let tag = TagModel(
                userId: nil,
                name: trimmed,
                colorId: selectedColorId,
                icon: selectedIcon,
                sortOrder: count,
                showOnHome: false,
                parentId: isGroupMode ? nil : selectedParentId,
                isGroup: isGroupMode
            )
            modelContext.insert(tag)
            do {
                try modelContext.save()
                Log.data.debug("tag created id=\(tag.id, privacy: .public) name=\(trimmed, privacy: .private)")
            } catch {
                Log.data.error("create tag failed: \(error.localizedDescription, privacy: .public)")
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

// MARK: - Color Picker Sheet

struct TagColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedColorId: String

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.smd), count: 6), spacing: Spacing.smd) {
                    ForEach(TagColors.palette) { color in
                        Button {
                            selectedColorId = color.id
                            dismiss()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color.primaryColor)
                                    .frame(width: 44, height: 44)
                                if selectedColorId == color.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Icon Picker Sheet

struct TagIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String?
    let accentColor: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.smd), count: 6), spacing: Spacing.smd) {
                    Button {
                        selectedIcon = nil
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "F0EDEA"))
                                .frame(width: 44, height: 44)
                            Image(systemName: "xmark")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(hex: "8F9E94"))
                            if selectedIcon == nil {
                                Circle()
                                    .stroke(Color.brandPrimary, lineWidth: 2)
                                    .frame(width: 44, height: 44)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(TagIconPicker.icons, id: \.self) { iconName in
                        Button {
                            selectedIcon = iconName
                            dismiss()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == iconName ? accentColor.opacity(0.15) : Color(hex: "F0EDEA"))
                                    .frame(width: 44, height: 44)
                                Image(systemName: iconName)
                                    .font(.system(size: 17))
                                    .foregroundStyle(selectedIcon == iconName ? accentColor : Color(hex: "4A5E50"))
                                if selectedIcon == iconName {
                                    Circle()
                                        .stroke(accentColor, lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Native emoji picker

/// A text field that only offers the system emoji keyboard, so tapping it lets
/// the user pick any native iOS emoji. Captures a single emoji and dismisses.
private struct EmojiInput: UIViewRepresentable {
    @Binding var emoji: String

    func makeUIView(context: Context) -> UITextField {
        let tf = EmojiOnlyTextField()
        tf.delegate = context.coordinator
        tf.textAlignment = .center
        tf.font = .systemFont(ofSize: 24)
        tf.tintColor = .clear                 // hide the caret
        tf.backgroundColor = .clear
        tf.text = emoji
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != emoji { uiView.text = emoji }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: EmojiInput
        init(_ parent: EmojiInput) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if string.isEmpty {                // backspace clears it
                parent.emoji = ""
                textField.text = ""
                return false
            }
            let picked = String(string.suffix(1))   // keep only the last emoji
            parent.emoji = picked
            textField.text = picked
            textField.resignFirstResponder()
            return false
        }
    }
}

/// UITextField subclass that forces the emoji keyboard.
private final class EmojiOnlyTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
    }
}
