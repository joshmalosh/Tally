import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct AddMultipleExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var allExpenses: [ExpenseModel]

    @State private var step: Step = .input
    @State private var showingCamera = false
    @State private var pastedText = ""
    @State private var showingPasteEditor = false
    @State private var isExtractingOCR = false
    @State private var parsedExpenses: [ParsedExpense] = []
    @State private var linkedTagIds: [String: String] = [:] // suggestedTagName -> existing tag id
    @State private var showingTagLinkPickerFor: TagLinkPickerTag?
    @State private var showingPhotoSourcePicker = false
    @State private var showingMonthlyLimitSheet = false
    @State private var showingPhotoLibrary = false
    @State private var photoForOCR: UIImage?
    @State private var bulkEditExpenseId: String?
    @FocusState private var isPasteFieldFocused: Bool

    private var existingTagNames: [String] { tags.map(\.name) }

    private func unsavedImportTagNames() -> [String] {
        let names = Set(parsedExpenses.compactMap(\.suggestedTagName))
        return names.filter { name in
            if linkedTagIds[name] != nil { return false }
            if BulkExpenseParser.findMatchingTag(suggested: name, existingTags: existingTagNames) != nil { return false }
            return true
        }.sorted()
    }

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
            .navigationTitle(step == .input ? "Import from notes" : "Review & import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBackFromReview()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .accessibilityLabel("Back")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .keyboardDoneToolbar()
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
        .sheet(isPresented: $showingMonthlyLimitSheet) {
            MonthlyLimitSheet(onProUnlocked: {
                performImport()
            })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $showingTagLinkPickerFor) { tagTag in
            TagLinkPickerSheet(
                tags: tags,
                importTagNames: tagTag.id.hasPrefix("group:") ? [] : unsavedImportTagNames(),
                allowsCreateNew: true,
                onSelect: { tagId in
                    handleTagPickerSelection(contextId: tagTag.id, tagId: tagId)
                    showingTagLinkPickerFor = nil
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { bulkEditExpenseId != nil },
            set: { if !$0 { bulkEditExpenseId = nil } }
        )) {
            if let id = bulkEditExpenseId,
               let exp = parsedExpenses.first(where: { $0.id == id }) {
                BulkExpenseRowEditSheet(
                    tags: tags,
                    importTagNames: unsavedImportTagNames(),
                    existingTagNames: existingTagNames,
                    currencyCode: appState.defaultCurrency,
                    initial: exp,
                    linkedTagIds: $linkedTagIds,
                    onSave: { updated in
                        if let i = parsedExpenses.firstIndex(where: { $0.id == updated.id }) {
                            parsedExpenses[i] = updated
                        }
                        bulkEditExpenseId = nil
                    },
                    onCancel: {
                        bulkEditExpenseId = nil
                    }
                )
                .id(id)
            }
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
                    subtitle: "Paste from Notes, Messages, anywhere"
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
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $pastedText)
                            .font(Fonts.body(16))
                            .foregroundStyle(Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .focused($isPasteFieldFocused)
                            .frame(minHeight: 280)
                            .padding(Spacing.md)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                        if pastedText.isEmpty {
                            Text("Paste or type your expenses here — we'll sort and tag them for you.")
                                .foregroundStyle(Color(hex: "C4BFB9"))
                                .font(.system(size: 16))
                                .padding(.horizontal, 5 + Spacing.md)
                                .padding(.vertical, 8 + Spacing.md)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, 100)
                }

                VStack {
                    Spacer(minLength: 0)
                    PrimaryButton(title: "Continue") {
                        proceedWithText(pastedText)
                        showingPasteEditor = false
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationTitle("Paste expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPasteEditor = false }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear { isPasteFieldFocused = true }
            .keyboardDoneToolbar()
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

    /// Returns to the input step, keeping `pastedText` unchanged and clearing all review-only state.
    private func goBackFromReview() {
        parsedExpenses = []
        linkedTagIds = [:]
        showingTagLinkPickerFor = nil
        step = .input
    }

    // MARK: - Review Step

    private var reviewStep: some View {
        let importCount = parsedExpenses.filter { $0.amountCents > 0 }.count
        let importEnabled = importCount > 0

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(groupedExpenseSections, id: \.tagKey) { section in
                        reviewTagGroupSection(section)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .animation(.easeInOut(duration: 0.25), value: parsedExpenses.map { "\($0.id):\($0.suggestedTagName ?? "")" }.joined())

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.clear, Color(hex: "F6F5F3")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                    .allowsHitTesting(false)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        performImport()
                    } label: {
                        Text("Import \(parsedExpenses.count) expenses")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BulkImportStickyCTAStyle(isEnabled: importEnabled))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .disabled(!importEnabled)
                }
                .background(Color(hex: "F6F5F3"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private func headerDotColor(for section: (tagKey: String, tagDisplayName: String, isNew: Bool, linkedTagId: String?, expenses: [ParsedExpense])) -> Color {
        if let lid = section.linkedTagId, let t = tags.first(where: { $0.id == lid }) {
            return t.tagColor.primaryColor
        }
        if section.tagKey != "__untagged__",
           let matched = BulkExpenseParser.findMatchingTag(suggested: section.tagKey, existingTags: existingTagNames),
           let t = tags.first(where: { $0.name == matched }) {
            return t.tagColor.primaryColor
        }
        return Color(hex: "8F9E94")
    }

    @ViewBuilder
    private func reviewTagGroupSection(_ section: (tagKey: String, tagDisplayName: String, isNew: Bool, linkedTagId: String?, expenses: [ParsedExpense])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(headerDotColor(for: section))
                    .frame(width: 8, height: 8)

                Text(section.tagDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))

                if section.isNew {
                    Text("New")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "F5A623"))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 8)

                if section.tagKey != "__untagged__" {
                    Button("Link to existing tag") {
                        showingTagLinkPickerFor = TagLinkPickerTag("group:\(section.tagKey)")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "346049"))
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(section.expenses.enumerated()), id: \.element.id) { idx, exp in
                    reviewExpenseRow(exp)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                removeExpenseFromPending(exp)
                            }
                        }
                    if idx < section.expenses.count - 1 {
                        Rectangle()
                            .fill(Color(hex: "DEDAD2"))
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
            )
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
            result.append(("__untagged__", "No tag", false, nil, untagged))
        }
        return result
    }

    private func handleTagPickerSelection(contextId: String, tagId: String) {
        if tagId.hasPrefix(TagLinkPickerSheet.importSelectionPrefix) {
            let name = String(tagId.dropFirst(TagLinkPickerSheet.importSelectionPrefix.count))
            if contextId.hasPrefix("group:") { return }
            if contextId.hasPrefix("expense:") {
                let expenseId = String(contextId.dropFirst(8))
                guard let idx = parsedExpenses.firstIndex(where: { $0.id == expenseId }) else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    parsedExpenses[idx].suggestedTagName = name
                }
            }
            return
        }

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

    private func reviewExpenseRow(_ exp: ParsedExpense) -> some View {
        let amountStr = CurrencyFormatter.shared.format(cents: exp.amountCents, currencyCode: appState.defaultCurrency)

        return HStack(alignment: .center, spacing: 12) {
            Text(exp.description)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Text(amountStr)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, alignment: .trailing)

            Button {
                bulkEditExpenseId = exp.id
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func expenseCountInMonth(of d: Date) -> Int {
        let cal = Calendar.current
        let (y, m) = (cal.component(.year, from: d), cal.component(.month, from: d))
        return allExpenses.filter {
            cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == m
        }.count
    }

    private func performImport() {
        let currency = appState.defaultCurrency
        let today = Date()

        if !appState.isPro {
            let existingCount = expenseCountInMonth(of: today)
            let toAdd = groupedExpenseSections.flatMap(\.expenses).filter { $0.amountCents > 0 }.count
            if existingCount + toAdd > 15 {
                showingMonthlyLimitSheet = true
                return
            }
        }

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
                    notes: exp.description,
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

// MARK: - Import sticky CTA (matches AddExpense save button)

private struct BulkImportStickyCTAStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background(isPressed: configuration.isPressed))
            )
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color(hex: "346049").opacity(0.4)
        }
        return isPressed ? Color(hex: "2D5A3F") : Color(hex: "346049")
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
    static let importSelectionPrefix = "import:"

    @Environment(\.dismiss) private var dismiss
    let tags: [TagModel]
    var importTagNames: [String] = []
    var allowsCreateNew: Bool = true
    let onSelect: (String) -> Void

    @State private var showingTagCreation = false

    private var standaloneTags: [TagModel] { tags.filter { $0.parentId == nil && !$0.isGroup } }
    private var groupTags: [TagModel] { tags.filter { $0.isGroup } }

    private func importTagDotColor(for name: String) -> Color {
        let palette = TagColors.palette
        let idx = abs(name.hashValue) % max(palette.count, 1)
        return palette[idx].primaryColor
    }

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
                                Text("+ New tag")
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

                    if !importTagNames.isEmpty {
                        Text("From this import")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .padding(.top, Spacing.xs)

                        ForEach(importTagNames, id: \.self) { name in
                            importTagRow(name)
                        }

                        Divider()
                            .background(Color.borderColor.opacity(0.6))
                            .padding(.vertical, Spacing.sm)
                    }

                    if !standaloneTags.isEmpty || !groupTags.isEmpty {
                        Text("Your tags")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .padding(.top, importTagNames.isEmpty ? Spacing.xs : 0)
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
            .keyboardDoneToolbar()
        }
    }

    private func importTagRow(_ name: String) -> some View {
        Button {
            onSelect(Self.importSelectionPrefix + name)
            dismiss()
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(importTagDotColor(for: name))
                    .frame(width: 14, height: 14)
                Text(name)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("New")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "F5A623"))
                    .clipShape(Capsule())
            }
            .padding(Spacing.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
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

// MARK: - Bulk review row edit sheet

private struct BulkExpenseRowEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tags: [TagModel]
    let importTagNames: [String]
    let existingTagNames: [String]
    let currencyCode: String
    @Binding var linkedTagIds: [String: String]
    let onSave: (ParsedExpense) -> Void
    let onCancel: () -> Void

    @State private var draft: ParsedExpense
    @State private var amountText: String
    @State private var showingTagPicker = false

    init(
        tags: [TagModel],
        importTagNames: [String],
        existingTagNames: [String],
        currencyCode: String,
        initial: ParsedExpense,
        linkedTagIds: Binding<[String: String]>,
        onSave: @escaping (ParsedExpense) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.tags = tags
        self.importTagNames = importTagNames
        self.existingTagNames = existingTagNames
        self.currencyCode = currencyCode
        _linkedTagIds = linkedTagIds
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: initial)
        let uses = CurrencyFormatter.shared.usesDecimals(for: currencyCode)
        let cents = initial.amountCents
        if uses {
            _amountText = State(initialValue: String(format: "%.2f", Double(cents) / 100.0))
        } else {
            _amountText = State(initialValue: String(format: "%.0f", Double(cents)))
        }
    }

    private var navigationTitleText: String {
        let t = draft.description
        guard t.count > 36 else { return t }
        return String(t.prefix(35)) + "…"
    }

    private var displayTagLabel: String {
        if let name = draft.suggestedTagName {
            if let linked = linkedTagIds[name], let t = tags.first(where: { $0.id == linked }) {
                return t.name
            }
            if let matched = BulkExpenseParser.findMatchingTag(suggested: name, existingTags: existingTagNames),
               let t = tags.first(where: { $0.name == matched }) {
                return t.name
            }
            return name
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    amountCard
                    tagCard
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.bgPrimary)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyAmountFromText()
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "346049"))
                }
            }
            .sheet(isPresented: $showingTagPicker) {
                TagLinkPickerSheet(
                    tags: tags,
                    importTagNames: importTagNames,
                    allowsCreateNew: true,
                    onSelect: { selection in
                        applyTagSelection(selection)
                    }
                )
            }
            .keyboardDoneToolbar()
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMOUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.6)
                .textCase(.uppercase)
            HStack(spacing: 6) {
                Text(CurrencyFormatter.shared.symbol(for: currencyCode))
                    .font(Fonts.mono(20))
                    .foregroundStyle(Color(hex: "346049").opacity(0.5))
                TextField("", text: $amountText)
                    .font(Fonts.mono(20))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .keyboardType(CurrencyFormatter.shared.usesDecimals(for: currencyCode) ? .decimalPad : .numberPad)
                    .textFieldStyle(.plain)
                    .onChange(of: amountText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1
                            ? parts[0] + "." + parts.dropFirst().joined()
                            : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
    }

    private var tagCard: some View {
        Button {
            showingTagPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("TAG")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.6)
                    .textCase(.uppercase)
                HStack(spacing: Spacing.smd) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandPrimary)
                    if displayTagLabel.isEmpty {
                        Text("Add tag")
                            .font(Fonts.body(16))
                            .foregroundStyle(Color(hex: "C4BFB9"))
                    } else {
                        Text(displayTagLabel)
                            .font(Fonts.body(16))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyAmountFromText() {
        guard let v = Double(amountText), v >= 0 else { return }
        let uses = CurrencyFormatter.shared.usesDecimals(for: currencyCode)
        if uses {
            let rounded = (v * 100).rounded() / 100
            draft.amountCents = max(0, Int(round(rounded * 100)))
        } else {
            draft.amountCents = max(0, Int(round(v)))
        }
    }

    private func applyTagSelection(_ selection: String) {
        if selection.hasPrefix(TagLinkPickerSheet.importSelectionPrefix) {
            let name = String(selection.dropFirst(TagLinkPickerSheet.importSelectionPrefix.count))
            draft.suggestedTagName = name
            linkedTagIds.removeValue(forKey: name)
            return
        }
        guard let tag = tags.first(where: { $0.id == selection }) else { return }
        draft.suggestedTagName = tag.name
        linkedTagIds[tag.name] = tag.id
    }
}
