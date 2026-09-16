import SwiftUI
import OSLog
import SwiftData
import UIKit

struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    let expenseId: String

    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingDeleteConfirmation = false
    @State private var showingLeaveConfirmation = false
    @State private var attachmentImage: UIImage?
    @State private var showingFullImage = false

    @State private var amountText = ""
    @State private var currency = ""
    @State private var date = Date()
    @State private var merchant = ""
    @State private var notes = ""
    @State private var selectedTagIds: [String] = []
    @State private var source: ExpenseSource = .manual
    @State private var attachedFileURL: URL?
    @State private var attachmentKey: String?

    @State private var showingTagPicker = false
    @State private var showingDatePickerSheet = false
    @State private var showingCurrencyPicker = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var showingReplaceReceiptSources = false
    @State private var pendingReplaceSource: ReplaceSource?

    private enum ReplaceSource { case camera, photos, file }
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    @State private var tallySuggestion: TagSuggestionEngine.Suggestion? = nil
    @State private var tallySuggestionDismissed = false
    /// Debounces the tag suggestion off the keystroke path. Recomputing it on
    /// every character (scan all expenses + run the keyword engine + animate) hogs
    /// the main thread and times out the keyboard's autocorrection accumulator
    /// (`Result accumulator timeout`), which is what froze the field on fast input.
    @State private var suggestionTask: Task<Void, Never>?
    /// Past merchant names, built once on open for the autocomplete chips.
    @State private var knownMerchants: [String] = []

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount, merchant, notes
    }

    private var expense: ExpenseModel? {
        activeExpenses.first { $0.id == expenseId }
    }

    private var parsedAmountCents: Int? {
        guard let amount = Double(amountText), amount > 0 else { return nil }
        if CurrencyFormatter.shared.usesDecimals(for: currency) {
            return Int(round(amount * 100))
        }
        return Int(round(amount))
    }

    private var currencySymbol: String {
        CurrencyFormatter.shared.symbol(for: currency)
    }

    private func formatAmountField() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else {
            amountText = ""
            return
        }
        if CurrencyFormatter.shared.usesDecimals(for: currency) {
            amountText = String(format: "%.2f", value)
        } else {
            amountText = String(format: "%.0f", value)
        }
    }

    private var canSaveEdits: Bool {
        parsedAmountCents != nil && !isSaving
    }

    private var selectedTags: [TagModel] {
        selectedTagIds.compactMap { id in tags.first { $0.id == id } }
    }

    /// "Group · Child" for a group's sub-tag, plain name otherwise.
    private func chipTitle(for tag: TagModel) -> String {
        if let parentId = tag.parentId, let parent = tags.first(where: { $0.id == parentId }) {
            return "\(parent.name) · \(tag.name)"
        }
        return tag.name
    }

    private static let datePillFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            if let expense {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 8) {
                            receiptObject

                            tallySuggestsCard

                            if let url = attachedFileURL {
                                pdfCard(url: url)
                            }

                            deleteButton

                            if !appState.isPro {
                                BannerAdView()
                                    .padding(.top, Spacing.sm)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.bottom, Spacing.xl)
                    }
                    // Native keyboard handling: the scroll view insets itself for the
                    // keyboard and scrolls the focused field into view on its own, and
                    // a downward drag dismisses it — no manual scroll animation, no
                    // window-level gesture.
                    .scrollDismissesKeyboard(.interactively)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // < Back
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if hasUnsavedChanges(expense) {
                                showingLeaveConfirmation = true
                            } else {
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                        }
                    }
                    // Done pill
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await saveEdits(expense: expense) }
                        } label: {
                            Text("Done")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(canSaveEdits ? Color(hex: "2F402E") : Color(hex: "2F402E").opacity(0.35))
                        }
                        .disabled(!canSaveEdits)
                    }
                }
                .alert("Delete expense?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { deleteExpense(expense) }
                } message: {
                    Text("This action cannot be undone.")
                }
                .alert("Error", isPresented: $showingError) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
                .sheet(isPresented: $showingTagPicker) {
                    SharedTagPickerSheet(selectedTagIds: $selectedTagIds)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingDatePickerSheet) {
                    NavigationStack {
                        DatePicker(
                            "Date of transaction",
                            selection: $date,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingDatePickerSheet = false }
                                    .foregroundStyle(Color(hex: "2F402E"))
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showingCurrencyPicker) {
                    CurrencyPickerSheet(selectedCode: $currency)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingReplaceReceiptSources, onDismiss: presentPendingReplace) {
                    replaceReceiptSheet
                }
                .fullScreenCover(isPresented: $showingCamera) {
                    CameraPicker(image: $attachmentImage).ignoresSafeArea()
                }
                .sheet(isPresented: $showingPhotoPicker) {
                    PhotosPicker(image: $attachmentImage, onCancel: {})
                }
                .sheet(isPresented: $showingDocumentPicker) {
                    DocumentPicker(selectedFileURL: $attachedFileURL, selectedImage: $attachmentImage)
                }
                .fullScreenCover(isPresented: $showingFullImage) {
                    if let image = attachmentImage {
                        FullImageView(image: image)
                    }
                }
                .onAppear {
                    syncFromExpense(expense)
                    knownMerchants = buildKnownMerchants()
                }
                // Deliberately NO reaction to expense.updatedAt. While the user is
                // in an expense we never let a background CloudKit sync reload or
                // reorder their edits — the screen loads once and stays put. It
                // dismisses on save, so the user's own change never needs re-syncing.
                .onChange(of: merchant)     { _, _ in scheduleTagSuggestion() }
                .onChange(of: notes)        { _, _ in scheduleTagSuggestion() }
                .onChange(of: selectedTagIds) { _, newVal in
                    if !newVal.isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) { tallySuggestion = nil }
                    }
                }
                .task { loadAttachment(expense) }   // once on open, not on every sync
                .alert("Save your changes?", isPresented: $showingLeaveConfirmation) {
                    Button("Save changes") { Task { await saveEdits(expense: expense) } }
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes to this expense.")
                }

            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Expense not found",
                    message: "This expense may have been deleted.",
                    actionTitle: "Dismiss",
                    action: { dismiss() }
                )
            }
        }
    }

    // MARK: - Receipt hero

    /// The whole expense as one physical-receipt object: a tag-tinted frame around
    /// the photo (or a hero amount), a perforated DETAILS tear line, a textured
    /// white body and a torn bottom edge, lifted off the page with a soft shadow.
    private var receiptObject: some View {
        VStack(spacing: 0) {
            topRegion
                .padding(16)   // thicker tag-coloured border, wrapping all four sides
            whiteBody
        }
        .background(frameColor)
        .clipShape(ReceiptShape())
        .overlay(alignment: .topLeading) {
            // Tag pill riding the top edge of the frame.
            if let tag = selectedTags.first {
                tagRidingChip(tag)
                    .padding(.leading, 22)
                    .offset(y: -11)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    // Only the frame border takes the expense's tag colour (Tally green when
    // untagged); the row icons stay a neutral green.
    private var frameColor: Color { selectedTags.first?.tagColor.primaryColor ?? Color(hex: "2F402E") }

    @ViewBuilder
    private var topRegion: some View {
        if let image = attachmentImage {
            receiptPhoto(image)
        } else {
            heroAmountBlock
        }
    }

    private func receiptPhoto(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { showingFullImage = true }
            .overlay(alignment: .bottom) {
                HStack(spacing: 14) {
                    Spacer()
                    Button { showingReplaceReceiptSources = true } label: {
                        Text("Replace").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).underline()
                    }
                    .buttonStyle(.plain)
                    Button {
                        attachmentImage = nil
                        attachedFileURL = nil
                        attachmentKey   = nil
                        source          = .manual
                    } label: {
                        Text("Remove").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 30)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // No receipt: a hero amount framed in the tag colour (shorter than the photo).
    private var heroAmountBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AMOUNT")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { showingCurrencyPicker = true } label: {
                    HStack(spacing: 2) {
                        Text(currencySymbol)
                            .font(.system(size: 24, weight: .regular, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                TextField("0", text: $amountText)
                    .keyboardType(CurrencyFormatter.shared.usesDecimals(for: currency) ? .decimalPad : .numberPad)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let filtered  = newValue.filter { $0.isNumber || $0 == "." }
                        let parts     = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1 ? parts[0] + "." + parts.dropFirst().joined() : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmountField() }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .id(Field.amount)
    }

    // MARK: - Receipt paper body

    private var whiteBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 6)   // small breathing room under the frame

            if attachmentImage != nil {
                amountDetailRow
                dashedRowDivider
            }
            merchantDetailRow
            dashedRowDivider
            dateDetailRow
            dashedRowDivider
            noteDetailRow
            dashedRowDivider
            tagDetailRow

            Spacer().frame(height: 18)   // clearance above the torn edge
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color.white
                ReceiptTexture()
            }
        )
    }

    private var dashedRowDivider: some View {
        ReceiptLine()
            .stroke(Color(hex: "2F402E").opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .frame(height: 1)
            .padding(.leading, 74)
            .padding(.trailing, 18)
    }

    private func tagRidingChip(_ tag: TagModel) -> some View {
        HStack(spacing: 5) {
            if tag.isGroup {
                Image(systemName: "folder.fill").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tag.tagColor.primaryColor)
            } else {
                Circle().fill(tag.tagColor.primaryColor).frame(width: 7, height: 7)
            }
            Text(selectedTags.count == 1 ? chipTitle(for: tag) : "\(tag.name) +\(selectedTags.count - 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    // MARK: - Detail rows

    private var amountDetailRow: some View {
        HStack(spacing: 14) {
            // Currency symbol is the leading square (tap to change currency) — the
            // single currency indicator, not repeated inside the field.
            Button { focusedField = nil; showingCurrencyPicker = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(hex: "E8F0EA"))
                        .frame(width: 40, height: 40)
                    Text(currencySymbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E"))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                rowLabel("AMOUNT")
                TextField("0.00", text: $amountText)
                    .keyboardType(CurrencyFormatter.shared.usesDecimals(for: currency) ? .decimalPad : .numberPad)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let filtered  = newValue.filter { $0.isNumber || $0 == "." }
                        let parts     = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1 ? parts[0] + "." + parts.dropFirst().joined() : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmountField() }
                    }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .id(Field.amount)
    }

    /// Previously-used merchant names for the autocomplete chips, filtered by what
    /// is typed. Filters the cached `knownMerchants` (built once on open) so each
    /// keystroke isn't re-sorting the whole expense list.
    private var merchantSuggestions: [String] {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Array(knownMerchants.prefix(6)) }
        let q = trimmed.lowercased()
        return knownMerchants.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
    }

    private func buildKnownMerchants() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for e in activeExpenses.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let raw = e.merchant?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, seen.insert(raw.lowercased()).inserted else { continue }
            names.append(raw)
        }
        return names
    }

    private var merchantDetailRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                tintedIconSquare("bag.fill")
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel("MERCHANT")
                    TextField("Add merchant", text: $merchant)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .focused($focusedField, equals: .merchant)
                        .textInputAutocapitalization(.words)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            // Autocomplete chips from past merchants, aligned under the value.
            if focusedField == .merchant && !merchantSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(merchantSuggestions, id: \.self) { name in
                            Button {
                                merchant = name
                                focusedField = nil
                            } label: {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: "2F402E").opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "F0EDE6"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 74)
                    .padding(.trailing, 18)
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .id(Field.merchant)
    }

    private var dateDetailRow: some View {
        Button { focusedField = nil; showingDatePickerSheet = true } label: {
            HStack(spacing: 14) {
                tintedIconSquare("calendar")
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel("DATE")
                    Text(Self.datePillFormatter.string(from: date))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noteDetailRow: some View {
        HStack(alignment: .top, spacing: 14) {
            tintedIconSquare("doc.text")
            VStack(alignment: .leading, spacing: 2) {
                rowLabel("NOTE")
                TextField("Add a note...", text: $notes, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .focused($focusedField, equals: .notes)
                    .lineLimit(1...4)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .id(Field.notes)
    }

    private var tagDetailRow: some View {
        Button { focusedField = nil; showingTagPicker = true } label: {
            HStack(spacing: 14) {
                tintedIconSquare("tag.fill")
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel("TAG")
                    if selectedTags.isEmpty {
                        Text("Add tag...")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "C4BFB9"))
                    } else {
                        HStack(spacing: 6) {
                            ForEach(selectedTags.prefix(2)) { tag in
                                HStack(spacing: 5) {
                                    if tag.isGroup {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(tag.tagColor.primaryColor)
                                    } else {
                                        Circle()
                                            .fill(tag.tagColor.primaryColor)
                                            .frame(width: 7, height: 7)
                                    }
                                    Text(chipTitle(for: tag))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(hex: "1C1C1E"))
                                }
                            }
                            if selectedTags.count > 2 {
                                Text("+\(selectedTags.count - 2)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Neutral light-green rounded square with a dark-green icon (all detail rows).
    private func tintedIconSquare(_ systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: "E8F0EA"))
                .frame(width: 40, height: 40)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "2F402E"))
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "8F9E94"))
            .tracking(1.0)
    }

    // MARK: - Tally Suggests

    @ViewBuilder
    private var tallySuggestsCard: some View {
        if let suggestion = tallySuggestion,
           !tallySuggestionDismissed,
           selectedTagIds.isEmpty {
            TallySuggestsCard(suggestion: suggestion) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagIds = [suggestion.tag.id]
                    tallySuggestion = nil
                }
            } onDismiss: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tallySuggestionDismissed = true
                }
            }
        }
    }

    // MARK: - PDF card

    private func pdfCard(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: "2F402E"))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Text("PDF document")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            Spacer()
            Button("Remove") {
                attachedFileURL  = nil
                attachmentImage  = nil
                attachmentKey    = nil
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: "2F402E"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button { showingDeleteConfirmation = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete expense")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.danger)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, Spacing.md)
    }

    // MARK: - Helpers

    /// Whether the local edits differ from the saved expense — drives the
    /// save/discard prompt on back. Covers field edits, a removed receipt
    /// (attachmentKey cleared), and a newly attached file.
    private func hasUnsavedChanges(_ expense: ExpenseModel) -> Bool {
        if parsedAmountCents != expense.amountCents { return true }
        if currency != expense.currency { return true }
        if date != expense.date { return true }
        if merchant.trimmingCharacters(in: .whitespacesAndNewlines) != (expense.merchant ?? "") { return true }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines) != (expense.notes ?? "") { return true }
        if selectedTagIds != expense.resolvedTagIds { return true }
        if attachmentKey != expense.attachmentKey { return true }
        if attachedFileURL != nil { return true }
        return false
    }

    // MARK: - Replace receipt sheet

    private var replaceReceiptSheet: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(hex: "DEDAD2"))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("Replace receipt")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                replaceOption(icon: "camera.fill", title: "Camera") { pickReplace(.camera) }
                replaceOption(icon: "photo.fill", title: "Photos") { pickReplace(.photos) }
                replaceOption(icon: "doc.fill", title: "File") { pickReplace(.file) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "F0EDE6"))
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }

    // Card rows matching the Add-expense receipt-source sheet, for consistency.
    private func replaceOption(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "E8F0EA"))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "2F402E"))
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // Set the choice and dismiss; the picker is presented in the sheet's
    // onDismiss so two presentations never fight.
    private func pickReplace(_ source: ReplaceSource) {
        pendingReplaceSource = source
        showingReplaceReceiptSources = false
    }

    private func presentPendingReplace() {
        guard let source = pendingReplaceSource else { return }
        pendingReplaceSource = nil
        switch source {
        case .camera: showingCamera = true
        case .photos: showingPhotoPicker = true
        case .file:   showingDocumentPicker = true
        }
    }

    private func syncFromExpense(_ expense: ExpenseModel) {
        currency = expense.currency
        let usesDecimals = CurrencyFormatter.shared.usesDecimals(for: expense.currency)
        if usesDecimals {
            amountText = String(format: "%.2f", Double(expense.amountCents) / 100.0)
        } else {
            amountText = String(format: "%.0f", Double(expense.amountCents))
        }
        date          = expense.date
        merchant      = expense.merchant ?? ""
        notes         = expense.notes   ?? ""
        selectedTagIds = expense.resolvedTagIds
        source         = ExpenseSource(rawValue: expense.source) ?? .manual
        attachmentKey  = expense.attachmentKey
    }

    private func deleteExpense(_ expense: ExpenseModel) {
        expense.deletedAt  = Date()
        expense.updatedAt  = Date()
        do {
            try modelContext.save()
            // Fire after dismiss so the shred plays on the Home screen underneath.
            NotificationCenter.default.post(name: .expenseDeleted, object: nil)
        } catch {
            Log.data.error("deleting expense failed: \(error.localizedDescription, privacy: .public)")
        }
        if let key = expense.attachmentKey {
            Task { await AttachmentService.shared.deleteAttachment(key: key) }
        }
        dismiss()
    }

    private func loadAttachment(_ expense: ExpenseModel) {
        let key = expense.attachmentKey
        let data = expense.attachmentData
        Task {
            // Decode/render off the main thread. A PDF page render is expensive,
            // and this re-fires on every updatedAt bump (CloudKit sync) — doing it
            // synchronously on the main thread was freezing the detail screen.
            let image = await Task.detached(priority: .userInitiated) {
                Self.resolveAttachmentImage(key: key, data: data)
            }.value
            // Don't blank an already-shown receipt on a transient miss (e.g. a
            // mid-write reload); only clear when there's genuinely no attachment.
            if image != nil || (key == nil && data == nil) {
                attachmentImage = image
            }
        }
    }

    /// Resolve an attachment to a display image. PDF-aware so a raw-PDF key isn't
    /// fed to `UIImage(data:)` (which fails noisily) before falling back.
    private static func resolveAttachmentImage(key: String?, data: Data?) -> UIImage? {
        if let key {
            if key.lowercased().hasSuffix(".pdf") {
                if let d = AttachmentService.shared.loadImageData(key: key),
                   let img = AttachmentService.firstPageImage(fromPDF: d) { return img }
            } else if let img = AttachmentService.shared.loadImage(key: key) {
                return img
            }
        }
        if let data {
            if let img = UIImage(data: data) { return img }
            if let img = AttachmentService.firstPageImage(fromPDF: data) { return img }
        }
        return nil
    }

    /// Wait for a short pause in typing, then compute the suggestion once — off the
    /// per-keystroke path. Cancels the previous pending run so only the last edit
    /// computes. Keyboard input stays on the main thread unblocked while typing.
    private func scheduleTagSuggestion() {
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            updateTagSuggestion()
        }
    }

    private func updateTagSuggestion() {
        guard selectedTagIds.isEmpty, !tallySuggestionDismissed else { return }
        // Prefer the user's own history — a tag they used on this merchant before —
        // and only fall back to the keyword engine when there's no such history.
        let suggestion = merchantHistorySuggestion() ?? TagSuggestionEngine.suggest(
            merchant: merchant,
            notes:    notes,
            tags:     Array(tags)
        )
        guard suggestion?.tag.id != tallySuggestion?.tag.id else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tallySuggestion = suggestion
        }
    }

    /// The tag most recently applied to another expense from the same merchant.
    private func merchantHistorySuggestion() -> TagSuggestionEngine.Suggestion? {
        let m = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard m.count >= 2 else { return nil }
        let match = activeExpenses
            .filter {
                $0.id != expenseId
                    && ($0.merchant?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == m)
                    && !$0.resolvedTagIds.isEmpty
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        guard let match,
              let tagId = match.resolvedTagIds.first,
              let tag = tags.first(where: { $0.id == tagId }) else { return nil }
        return TagSuggestionEngine.Suggestion(tag: tag, reason: "repeat purchase")
    }

    @MainActor
    private func saveEdits(expense: ExpenseModel) async {
        guard let amountCents = parsedAmountCents else {
            errorMessage = "Please enter a valid amount."
            showingError = true
            return
        }

        isSaving = true
        let expenseId = expense.id

        var savedKey: String?     = expense.attachmentKey
        var rawAttachmentData: Data? = expense.attachmentData

        if let image = attachmentImage {
            do {
                savedKey          = try await AttachmentService.shared.saveImage(image, id: expenseId)
                rawAttachmentData = image.jpegData(compressionQuality: 0.8)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving     = false
                return
            }
        } else if let url = attachedFileURL {
            do {
                savedKey          = try await AttachmentService.shared.saveFile(from: url, id: expenseId)
                rawAttachmentData = try? Data(contentsOf: url)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving     = false
                return
            }
        } else if let oldKey = expense.attachmentKey, attachmentKey == nil {
            await AttachmentService.shared.deleteAttachment(key: oldKey)
            savedKey          = nil
            rawAttachmentData = nil
        } else {
            savedKey          = expense.attachmentKey
            rawAttachmentData = expense.attachmentData
        }

        expense.amountCents   = amountCents
        expense.currency      = currency
        expense.date          = date
        expense.merchant      = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : merchant
        expense.tagIds        = selectedTagIds
        expense.tagId         = selectedTagIds.first ?? ""
        expense.notes         = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        expense.attachmentKey  = savedKey
        expense.attachmentData = rawAttachmentData
        expense.source         = source.rawValue
        expense.updatedAt      = Date()

        do {
            try modelContext.save()
        } catch {
            Log.data.error("save expense edits failed: \(error.localizedDescription, privacy: .public)")
        }
        isSaving = false
        // Same save feedback as a new add: the coin sound, success haptic, row
        // landing animation and celebration all hang off .expenseLogged, so an
        // edit save posts it too (before dismiss, so Home marks the row before it
        // reappears — matching the add path).
        NotificationCenter.default.post(
            name: .expenseLogged,
            object: nil,
            userInfo: [
                "expenseId": expense.id,
                "amountCents": amountCents,
                "currency": currency
            ]
        )
        dismiss()
    }
}

// MARK: - Receipt object shapes & texture

/// Rounded top corners with a torn (zig-zag) bottom edge, so the detail body
/// reads like a physically torn receipt.
// Shared with AddExpenseView's scoped receipt hero — internal, not private.
struct ReceiptShape: Shape {
    var cornerRadius: CGFloat = 24
    var toothWidth: CGFloat = 13
    var toothDepth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, rect.width / 2)
        let base = rect.height - toothDepth
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: base))
        // Zig-zag from right to left along the bottom.
        var x = rect.width
        var down = true
        while x > 0 {
            let nextX = max(0, x - toothWidth / 2)
            p.addLine(to: CGPoint(x: nextX, y: down ? rect.height : base))
            x = nextX
            down.toggle()
        }
        p.addLine(to: CGPoint(x: 0, y: r))
        p.closeSubpath()
        return p
    }
}

/// A horizontal line, for the dashed row dividers. Shared with AddExpenseView.
struct ReceiptLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

/// Faint, evenly-spaced dots — a subtle "receipt paper" texture. Static, so it
/// adds no per-keystroke cost while editing.
struct ReceiptTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 15
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.4, height: 1.4))
            let color = Color(hex: "2F402E").opacity(0.05)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Full Image View

struct FullImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture.simultaneously(with: panGesture))
                .onTapGesture(count: 2) { toggleZoom() }

            // White x on a translucent dark circle — visible on any receipt,
            // including white paper that fills the screen behind it.
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .padding(Spacing.lg)
        }
    }

    // Pinch to zoom (1×–6×), clamped.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                }
            }
    }

    // When zoomed: pan the image. When not zoomed: drag down to dismiss.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else if value.translation.height > 0 {
                    offset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if value.translation.height > 100 {
                    dismiss()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { offset = .zero }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if scale > 1 { resetZoom() } else { scale = 2.5; lastScale = 2.5 }
        }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}
