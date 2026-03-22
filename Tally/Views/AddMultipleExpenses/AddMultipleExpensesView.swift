import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct AddMultipleExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var step: Step = .input
    @State private var showingCamera = false
    @State private var pastedText = ""
    @State private var showingPasteEditor = false
    @State private var isExtractingOCR = false
    @State private var parsedExpenses: [ParsedExpense] = []
    @State private var linkedTagIds: [String: String] = [:] // suggestedTagName -> existing tag id
    @State private var showingTagLinkPickerFor: TagLinkPickerTag?
    @State private var showingPhotoSourcePicker = false
    @State private var showingPhotoLibrary = false
    @State private var photoForOCR: UIImage?
    @FocusState private var isPasteFieldFocused: Bool

    private var existingTagNames: [String] { tags.map(\.name) }

    private enum Step {
        case input
        case review
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == .input {
                    inputStep
                } else {
                    reviewStep
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle(step == .input ? "Add from notes" : "Review expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .confirmationDialog("Add from photo", isPresented: $showingPhotoSourcePicker) {
            Button("Take Photo") { showingCamera = true }
            Button("Choose from Library") { showingPhotoLibrary = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Extract expenses from a receipt or notes photo")
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            PhotosPicker(image: $photoForOCR, onCancel: { showingPhotoLibrary = false })
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $photoForOCR)
                .ignoresSafeArea()
        }
        .onChange(of: photoForOCR) { _, new in
            if let new {
                showingCamera = false
                showingPhotoLibrary = false
                runOCR(on: new)
                photoForOCR = nil
            }
        }
        .sheet(isPresented: $showingPasteEditor) {
            pasteTextSheet
        }
        .sheet(item: $showingTagLinkPickerFor) { tagTag in
            TagLinkPickerSheet(
                tags: tags,
                allowsCreateNew: true,
                onSelect: { tagId in
                    handleTagPickerSelection(contextId: tagTag.id, tagId: tagId)
                    showingTagLinkPickerFor = nil
                }
            )
        }
    }

    // MARK: - Input Step

    private var inputStep: some View {
        VStack(spacing: Spacing.lg) {
            Text("Have a list of expenses somewhere else already? Upload or type them, we'll handle the rest.")
                .font(Fonts.caption(14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            VStack(spacing: Spacing.md) {
                inputCard(
                    icon: "camera.fill",
                    title: "Take or upload a photo",
                    subtitle: "Upload a photo or screenshot of your notes"
                ) {
                    showingPhotoSourcePicker = true
                }

                inputCard(
                    icon: "doc.text",
                    title: "Paste text",
                    subtitle: "Paste or type your expenses"
                ) {
                    showingPasteEditor = true
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            Spacer()
        }
        .overlay {
            if isExtractingOCR {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Extracting text...")
                            .font(Fonts.caption(14))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func inputCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 48, height: 48)
                    .background(Color.brandTint)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Fonts.headline(16))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(Spacing.lg)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var pasteTextSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $pastedText)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surface)
                    .focused($isPasteFieldFocused)

                PrimaryButton(title: "Continue") {
                    proceedWithText(pastedText)
                    showingPasteEditor = false
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Paste text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPasteEditor = false }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func runOCR(on image: UIImage) {
        isExtractingOCR = true
        Task {
            let text = await ReceiptOCRService.extractFullText(from: image)
            await MainActor.run {
                isExtractingOCR = false
                if text.isEmpty {
                    proceedWithText("")
                } else {
                    proceedWithText(text)
                }
            }
        }
    }

    private func loadFileContents(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
              ?? String(data: data, encoding: .utf16)
              ?? String(data: data, encoding: .ascii) else {
            return
        }
        proceedWithText(text)
    }

    private func proceedWithText(_ text: String) {
        let parsed = BulkExpenseParser.parse(text)
        if parsed.isEmpty {
            dismiss()
            return
        }
        parsedExpenses = parsed
        step = .review
    }

    // MARK: - Review Step

    private var reviewStep: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groupedExpenseSections, id: \.tagKey) { section in
                    Section {
                        ForEach(section.expenses) { exp in
                            reviewExpenseRow(exp, onTagTap: {
                                showingTagLinkPickerFor = TagLinkPickerTag("expense:\(exp.id)")
                            })
                            .listRowBackground(Color.surface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeExpenseFromPending(exp)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: Spacing.sm) {
                            Text(section.tagDisplayName)
                                .font(Fonts.headline(15))
                                .foregroundStyle(Color.textPrimary)

                            if section.isNew {
                                Text("New")
                                    .font(Fonts.caption(11))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color(hex: "D4872A"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "D4872A").opacity(0.2))
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            if section.tagKey != "__untagged__" {
                                Button("Link to existing tag") {
                                    showingTagLinkPickerFor = TagLinkPickerTag("group:\(section.tagKey)")
                                }
                                .font(Fonts.label(13))
                                .foregroundStyle(Color.brandPrimary)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .animation(.easeInOut(duration: 0.25), value: parsedExpenses.map { "\($0.id):\($0.suggestedTagName ?? "")" }.joined())
            .background(Color.bgPrimary)

            PrimaryButton(title: "Import \(parsedExpenses.count) expenses") {
                performImport()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }

    private func removeExpenseFromPending(_ exp: ParsedExpense) {
        withAnimation(.easeInOut(duration: 0.25)) {
            parsedExpenses.removeAll { $0.id == exp.id }
        }
    }

    private var groupedExpenseSections: [(tagKey: String, tagDisplayName: String, isNew: Bool, linkedTagId: String?, expenses: [ParsedExpense])] {
        let groups = Dictionary(grouping: parsedExpenses) { exp -> String in
            exp.suggestedTagName ?? "__untagged__"
        }
        var result: [(String, String, Bool, String?, [ParsedExpense])] = []
        let tagNames = groups.keys.filter { $0 != "__untagged__" }.sorted()
        for name in tagNames {
            let exps = groups[name] ?? []
            let linkedId = linkedTagIds[name]
            let matched = BulkExpenseParser.findMatchingTag(suggested: name, existingTags: existingTagNames)
            let isNew = linkedId == nil && matched == nil
            let displayName = linkedId.flatMap { id in tags.first { $0.id == id }?.name } ?? matched ?? name
            result.append((name, displayName, isNew, linkedId ?? (matched.flatMap { m in tags.first { $0.name == m }?.id }), exps))
        }
        if let untagged = groups["__untagged__"], !untagged.isEmpty {
            result.append(("__untagged__", "Untagged", false, nil, untagged))
        }
        return result
    }

    private func handleTagPickerSelection(contextId: String, tagId: String) {
        let tagName: String? = tags.first(where: { $0.id == tagId })?.name
            ?? (try? modelContext.fetch(FetchDescriptor<TagModel>(predicate: #Predicate { $0.id == tagId })).first)?.name
        guard let tagName else { return }

        if contextId.hasPrefix("group:") {
            let tagKey = String(contextId.dropFirst(6))
            linkedTagIds[tagKey] = tagId
        } else if contextId.hasPrefix("expense:") {
            let expenseId = String(contextId.dropFirst(8))
            guard let idx = parsedExpenses.firstIndex(where: { $0.id == expenseId }) else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                parsedExpenses[idx].suggestedTagName = tagName
                linkedTagIds[tagName] = tagId
            }
        }
    }

    private func reviewExpenseRow(_ exp: ParsedExpense, onTagTap: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(exp.description)
                .font(Fonts.body(16))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            TextField("Amount", value: Binding(
                get: { Double(exp.amountCents) / 100 },
                set: { newVal in
                    guard let idx = parsedExpenses.firstIndex(where: { $0.id == exp.id }) else { return }
                    let roundedToCents = (newVal * 100).rounded() / 100
                    parsedExpenses[idx].amountCents = max(0, Int(round(roundedToCents * 100)))
                }
            ), format: .currency(code: appState.defaultCurrency))
            .keyboardType(.decimalPad)
            .font(Fonts.mono(16))
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)

            Button(action: onTagTap) {
                Image(systemName: "tag")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func performImport() {
        let currency = appState.defaultCurrency
        let today = Date()

        for section in groupedExpenseSections {
            var tagId: String?
            if section.tagKey == "__untagged__" {
                tagId = nil
            } else if let linked = section.linkedTagId {
                tagId = linked
            } else if let matched = BulkExpenseParser.findMatchingTag(suggested: section.tagKey, existingTags: existingTagNames),
                      let t = tags.first(where: { $0.name == matched }) {
                tagId = t.id
            } else {
                let count = (try? modelContext.fetchCount(FetchDescriptor<TagModel>())) ?? 0
                let newTag = TagModel(
                    userId: nil,
                    name: section.tagDisplayName,
                    colorId: TagColors.palette[count % TagColors.palette.count].id,
                    sortOrder: count
                )
                modelContext.insert(newTag)
                tagId = newTag.id
            }

            for exp in section.expenses where exp.amountCents > 0 {
                let model = ExpenseModel(
                    amountCents: exp.amountCents,
                    currency: currency,
                    date: today,
                    description: exp.description,
                    tagIds: tagId.map { [$0] } ?? [],
                    source: "bulk_import"
                )
                modelContext.insert(model)
            }
        }

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[Tally] ERROR saving bulk import: \(error)")
            #endif
        }

        dismiss()
    }
}

// MARK: - Bulk Import File Picker

struct BulkImportFilePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .spreadsheet,
            .commaSeparatedText,
            .plainText,
            UTType(filenameExtension: "xlsx") ?? .spreadsheet,
            UTType(filenameExtension: "xls") ?? .spreadsheet
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: BulkImportFilePicker

        init(_ parent: BulkImportFilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
            parent.dismiss()
        }
    }
}

struct TagLinkPickerTag: Identifiable {
    let id: String
    init(_ id: String) { self.id = id }
}

struct TagLinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tags: [TagModel]
    var allowsCreateNew: Bool = true
    let onSelect: (String) -> Void

    @State private var showingTagCreation = false

    private var standaloneTags: [TagModel] { tags.filter { $0.parentId == nil && !$0.isGroup } }
    private var groupTags: [TagModel] { tags.filter { $0.isGroup } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if allowsCreateNew {
                        Button {
                            showingTagCreation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Create new tag")
                                    .font(Fonts.label(14))
                            }
                            .foregroundStyle(Color.brandPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.brandTint)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .background(Color.borderColor.opacity(0.6))
                            .padding(.vertical, Spacing.sm)
                    }

                    ForEach(standaloneTags) { tag in
                        tagRow(tag)
                    }
                    ForEach(groupTags) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(Fonts.caption(13))
                                .foregroundStyle(Color.textSecondary)
                            ForEach(tags.filter { $0.parentId == group.id }) { child in
                                tagRow(child)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Select tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingTagCreation) {
                TagCreationView { newTagId in
                    showingTagCreation = false
                    onSelect(newTagId)
                    dismiss()
                }
            }
        }
    }

    private func tagRow(_ tag: TagModel) -> some View {
        Button {
            onSelect(tag.id)
            dismiss()
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 14, height: 14)
                Text(tag.name)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}
