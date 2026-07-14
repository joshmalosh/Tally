import SwiftUI
import SwiftData
import UIKit
import PDFKit

/// Pre-filled values applied when `AddExpenseView` is opened from `MultiReceiptReviewView`.
struct BatchDraftPrefill {
    var amountText: String = ""
    var merchant: String = ""
    var date: Date = Date()
    var notes: String = ""
}

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AdManager.self) private var adManager
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @State private var allExpenses: [ExpenseModel] = []

    var initialMode: AddEntryMode = .manual
    var initialImage: UIImage? = nil
    var initialFileURL: URL? = nil
    var editingExpense: ExpenseModel? = nil

    /// Pre-fills form fields when opened from MultiReceiptReviewView.
    var batchPrefill: BatchDraftPrefill? = nil
    /// Called just before dismiss when saving succeeds in batch mode.
    var onSaved: (() -> Void)? = nil
    /// When provided, multiple-image selections are handed off to the caller instead
    /// of being handled internally. The caller is responsible for presentation.
    var onMultiReceiptImages: (([UIImage]) -> Void)? = nil

    @State private var amountText = ""
    @State private var currency = ""
    @State private var date = Date()
    @State private var merchant = ""
    @State private var descriptionText = ""
    @State private var notes = ""
    @State private var selectedTagIds: [String] = []
    @State private var source: ExpenseSource = .manual

    @State private var attachedImage: UIImage?
    @State private var attachedFileURL: URL?
    @State private var attachmentKey: String?
    @State private var enteredViaPhotoFlow = false

    /// True while we are waiting for the multi-image review to appear —
    /// suppresses the formReady restore that would flash the form briefly.
    @State private var multiImagesInProgress = false
    @State private var reviewHostingController: UIViewController? = nil

    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var showingPDFPreview = false
    @State private var lastImageSource: ExpenseSource = .manual
    @State private var showingTagPicker = false
    @State private var showingCurrencyPicker = false
    @State private var showingFullImage = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var formReady = true
    @State private var isRunningOCR = false
    @State private var showingProBenefitsCard = false
    @State private var showingGoProFromOcrBanner = false

    @State private var tallySuggestion: TagSuggestionEngine.Suggestion? = nil
    @State private var tallySuggestionDismissed = false

    @State private var showingDatePickerSheet = false
    @State private var showingAddReceiptSources = false
    @State private var showingReplaceReceiptSources = false
    @State private var notesExpanded = false
    @State private var ocrPopulatedAnyField = false
    @State private var amountFocusRequested: Bool = false
    @State private var keyboardVisible = false
    @State private var quickAddPrompt: String = ""
    @State private var amountCursorVisible: Bool = true

    @State private var dateManuallyEdited = false
    @State private var merchantReturnMessage: String? = nil
    @State private var tagAutoAppliedByHistory = false
    @State private var isRecurring = false
    @State private var recurringInterval: RecurringInterval = .monthly

    @FocusState private var focusedField: Field?

    private var isEditing: Bool { editingExpense != nil }

    private enum Field: Hashable {
        case amount, merchant, notes
    }

    private enum RecurringInterval: String, CaseIterable {
        case weekly = "Weekly"
        case fortnightly = "Fortnightly"
        case monthly = "Monthly"
        case annually = "Annually"

        var adverb: String {
            switch self {
            case .weekly: return "weekly"
            case .fortnightly: return "fortnightly"
            case .monthly: return "monthly"
            case .annually: return "annually"
            }
        }
    }

    /// Two-state UI: receipt image attached vs not (PDF-only stays in “no image” layout with file card).
    private var receiptImageAttached: Bool { attachedImage != nil }

    private var parsedAmountCents: Int? {
        guard let amount = Double(amountText), amount > 0 else { return nil }
        if CurrencyFormatter.shared.usesDecimals(for: currency) {
            return Int(round(amount * 100))
        }
        return Int(round(amount))
    }

    private var usesDecimalCurrency: Bool {
        CurrencyFormatter.shared.usesDecimals(for: currency)
    }

    private var zeroAmountPlaceholder: String {
        usesDecimalCurrency ? "0.00" : "0"
    }

    private func formatAmount() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else {
            amountText = ""
            return
        }
        if usesDecimalCurrency {
            amountText = String(format: "%.2f", value)
        } else {
            amountText = String(format: "%.0f", value)
        }
    }

    private func sanitizeAmountInput(_ newValue: String) -> String {
        let filtered = newValue.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count > 1 {
            return String(parts[0]) + "." + parts.dropFirst().joined()
        }
        return String(filtered)
    }

    private var currencySymbol: String {
        CurrencyFormatter.shared.symbol(for: currency)
    }

    private var canSave: Bool {
        parsedAmountCents != nil && !isSaving
    }

    private var hasAttachment: Bool {
        attachedImage != nil || attachedFileURL != nil
    }

    /// Save ~56pt + vertical padding, optional ad ~52pt, safe bottom ~34, margin 16.
    private var formBottomChromeClearance: CGFloat {
        let saveChrome: CGFloat = 56 + 36
        let banner: CGFloat = !appState.isPro ? 52 : 0
        let safeBottom: CGFloat = 34
        let margin: CGFloat = 16
        return saveChrome + banner + safeBottom + margin
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

    private var shouldShowOcrFilledBanner: Bool {
        receiptImageAttached && ocrPopulatedAnyField && !isRunningOCR
    }

    private static let heroDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private var heroDateLabel: String {
        Self.heroDateFormatter.string(from: date).uppercased()
    }

    private var autoScannedBadgeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
            Text("AUTO-SCANNED")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(Color(hex: "2F402E"))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "B8D9C0"))
        .clipShape(Capsule())
    }

    @State private var cachedKnownMerchants: [String] = []

    private static let compactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private var datePillLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today · \(Self.compactDateFormatter.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(Self.compactDateFormatter.string(from: date))" }
        return Self.compactDateFormatter.string(from: date)
    }

    private var quickAddAmountParts: (whole: String, decimal: String?) {
        let text = amountText
        if text.isEmpty { return usesDecimalCurrency ? ("0", "00") : ("0", nil) }
        if text.hasSuffix(".") {
            let whole = String(text.dropLast())
            return (whole.isEmpty ? "0" : whole, "")
        }
        if let dotIdx = text.firstIndex(of: ".") {
            let whole = String(text[text.startIndex..<dotIdx])
            let dec   = String(text[text.index(after: dotIdx)...])
            return (whole.isEmpty ? "0" : whole, dec)
        }
        return (text, usesDecimalCurrency ? "00" : nil)
    }

    // Typed cents digits and how many greyed placeholder zeros remain.
    // e.g. "100.5" → typed="5", placeholder="0"  →  displays as .5[0]
    //      "100."  → typed="",  placeholder="00" →  displays as .[00]
    //      "100"   → typed="",  placeholder="00" →  decimal separator is greyed too
    private var decimalDisplayParts: (typed: String, placeholder: String) {
        guard usesDecimalCurrency else { return ("", "") }
        guard amountText.contains("."), !amountText.hasSuffix(".") else { return ("", "00") }
        if let dotIdx = amountText.firstIndex(of: ".") {
            let typed = String(amountText[amountText.index(after: dotIdx)...])
            return (typed, String(repeating: "0", count: max(0, 2 - typed.count)))
        }
        return ("", "00")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            addExpenseNavigationRoot
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = true }
            formatAmount()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = false }
        }
    }

    /// Split from `body` so the type checker can infer `NavigationStack` without timing out.
    private var addExpenseNavigationRoot: some View {
        addExpenseFormWithSheets
            .onChange(of: attachedImage) { _, newValue in
                if newValue == nil {
                    ocrPopulatedAnyField = false
                    dateManuallyEdited = false
                    tallySuggestion = nil
                    tallySuggestionDismissed = false
                }
                if let image = newValue {
                    if AttachmentService.exceedsMaxSize(image) {
                        attachedImage = nil
                        attachedFileURL = nil
                        errorMessage = "This image is too large. Maximum size is 20 MB."
                        showingError = true
                        return
                    }
                    source = lastImageSource
                    ocrPopulatedAnyField = false
                    dateManuallyEdited = false
                    focusedField = nil
                    amountFocusRequested = false
                    if !isEditing {
                        runOCR(on: image)
                    }
                }
            }
            .onChange(of: showingCamera) { _, showing in
                if showing { lastImageSource = .camera }
                if !showing && !formReady {
                    withAnimation(.easeIn(duration: 0.2)) { formReady = true }
                }
                if !showing && attachedImage == nil && enteredViaPhotoFlow {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if attachedImage == nil { dismiss() }
                    }
                }
            }
            .onChange(of: showingPhotoPicker) { _, showing in
                if showing { lastImageSource = .upload }
                // Only restore formReady when NOT entering multi-image review;
                // multiImagesInProgress suppresses the flash of the form.
                if !showing && !formReady && !multiImagesInProgress {
                    withAnimation(.easeIn(duration: 0.2)) { formReady = true }
                }
            }
            .onChange(of: showingDocumentPicker) { _, showing in
                if !showing && !formReady {
                    withAnimation(.easeIn(duration: 0.2)) { formReady = true }
                }
            }
            .onChange(of: attachedFileURL) { _, url in
                // Run OCR when a PDF is attached (images are handled via attachedImage)
                guard let url, attachedImage == nil, !isEditing else { return }
                runOCROnPDF(url: url)
            }
            .onChange(of: formReady) { _, ready in
                guard ready, focusedField == nil, !hasAttachment else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard attachedImage == nil, attachedFileURL == nil else { return }
                    amountFocusRequested = true
                }
            }
            .onChange(of: notes) { _, newVal in
                if !newVal.isEmpty { notesExpanded = true }
                updateTagSuggestion()
            }
            .onChange(of: merchant) { _, _ in
                if isEditing {
                    updateTagSuggestion()
                } else {
                    applyMerchantHistory()
                }
            }
            .onChange(of: selectedTagIds) { _, newValue in
                if !newValue.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) { tallySuggestion = nil }
                }
            }
            .onChange(of: showingTagPicker) { _, isShowing in
                // Picker dismissed with a user selection — clear the auto-apply flag
                if !isShowing { tagAutoAppliedByHistory = false }
            }
            .onAppear {
                applyInitialState()
                loadExpenses()
                if !receiptImageAttached, !notes.isEmpty {
                    notesExpanded = true
                }
                guard !isEditing, !hasAttachment else { return }
                amountFocusRequested = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard !hasAttachment else { return }
                    amountFocusRequested = true
                }
            }
    }

    private var addExpenseFormWithSheets: some View {
        addExpenseFormChrome
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
                            Button("Done") {
                                dateManuallyEdited = true
                                showingDatePickerSheet = false
                            }
                            .foregroundStyle(Color(hex: "2F402E"))
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $attachedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotosPicker(
                    image: $attachedImage,
                    onCancel: {
                        if enteredViaPhotoFlow && attachedImage == nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                dismiss()
                            }
                        }
                    },
                    onMultipleImages: { images in
                        if let handler = onMultiReceiptImages {
                            // Hand off to parent — it will present MultiReceiptReviewView
                            // at its own level (not nested inside this fullScreenCover).
                            handler(images)
                        } else {
                            multiImagesInProgress = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                multiImagesInProgress = false
                                presentReviewViaUIKit(images: images)
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(selectedFileURL: $attachedFileURL, selectedImage: $attachedImage)
            }
            .sheet(isPresented: $showingTagPicker) {
                SharedTagPickerSheet(selectedTagIds: $selectedTagIds)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerSheet(selectedCode: $currency)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingFullImage) {
                if let image = attachedImage {
                    FullImageView(image: image)
                }
            }
            .sheet(isPresented: $showingProBenefitsCard, onDismiss: { dismiss() }) {
                ProBenefitsCard()
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingGoProFromOcrBanner) {
                SubscriptionView()
            }
    }

    private var addExpenseFormChrome: some View {
        addExpenseFormZStack
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { handleBackButton() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    }
                }
                ToolbarItem(placement: .principal) {
                    if shouldShowOcrFilledBanner {
                        autoScannedBadgeView
                    } else if !receiptImageAttached {
                        Text(isEditing ? "EDIT EXPENSE" : "QUICK ADD")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "2F402E").opacity(0.6))
                            .tracking(1.5)
                    }
                }
                if receiptImageAttached || isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            saveExpense()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Done")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(canSave ? Color(hex: "2F402E") : Color(hex: "2F402E").opacity(0.4))
                            .clipShape(Capsule())
                        }
                        .disabled(!canSave)
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showingAddReceiptSources) {
                ReceiptSourcePickerSheet(
                    title: "Add receipt",
                    onCamera: { showingCamera = true },
                    onPhotos: { showingPhotoPicker = true },
                    onFile: { showingDocumentPicker = true }
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: "F0EDE6"))
            }
            .sheet(isPresented: $showingReplaceReceiptSources) {
                ReceiptSourcePickerSheet(
                    title: "Replace receipt",
                    onCamera: { showingCamera = true },
                    onPhotos: { showingPhotoPicker = true },
                    onFile: { showingDocumentPicker = true }
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: "F0EDE6"))
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
    }

    private var addExpenseFormZStack: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if formReady {
                ScrollView {
                    formScrollStack
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    stickySaveChrome
                }
            }
        }
    }

    // MARK: - Scroll content

    private var formScrollStack: some View {
        VStack(spacing: 8) {
            if receiptImageAttached {
                receiptImageAttachedFormBlock
                tallySuggestsCard
            } else {
                manualEntryFormBlock
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: receiptImageAttached)
    }

    @ViewBuilder
    private var receiptImageAttachedFormBlock: some View {
        receiptHeroView
            .transition(.move(edge: .top).combined(with: .opacity))

        if !appState.isPro {
            proUpsellCompactBanner
        }

        // Same card language as Quick Add — the receipt flow is Quick Add
        // with the hero amount swapped for a compact amount card.
        receiptAmountCard
        quickAddMerchantCard
        quickAddNoteCard
        quickAddTagCard
        receiptDateRow
        quickAddRecurringCard
    }

    @ViewBuilder
    private var manualEntryFormBlock: some View {
        quickAddHeroAmountBlock
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

        quickAddMerchantCard

        quickAddNoteCard

        quickAddTagCard

        quickAddExtrasRow

        quickAddRecurringCard

        // Gentle OCR upsell for free users typing manually — held back until
        // they've logged a few expenses so first impressions stay unmonetised.
        if !appState.isPro && appState.totalExpenseCount >= 3 {
            proUpsellCompactBanner
        }

        if attachedFileURL != nil {
            pdfAttachmentCard
        }

        merchantReturnCard

        tallySuggestsCard
    }

    // MARK: - Quick Add: Merchant card with filtered autocomplete chips

    private var quickAddMerchantCard: some View {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestions: [String] = {
            if trimmed.isEmpty {
                return Array(cachedKnownMerchants.prefix(6))
            }
            let q = trimmed.lowercased()
            return cachedKnownMerchants
                .filter { $0.lowercased().contains(q) }
                .prefix(6)
                .map { $0 }
        }()
        let showChips = focusedField == .merchant && !suggestions.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MERCHANT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    .tracking(1.0)
                Spacer()
                if !merchant.isEmpty {
                    Button("Clear") { merchant = ""; focusedField = nil }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.4))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            TextField(isRunningOCR && appState.isPro && merchant.isEmpty ? "Detecting…" : "Tap or type…", text: $merchant)
                .font(Font.dmSerifDisplay(22))
                .foregroundStyle(Color(hex: "1C1C1E"))   // always black when typing
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .tint(Color(hex: "2F402E"))
                .padding(.horizontal, 14)

            if showChips {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                merchant = name
                                focusedField = nil
                            } label: {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(merchant == name ? Color.white : Color(hex: "2F402E").opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(merchant == name ? Color(hex: "2F402E") : Color(hex: "F0EDE6"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.15), value: showChips)
    }

    // MARK: - Quick Add: Note card

    private var quickAddNoteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "4A5E50"))
                Text("WHAT WAS IT?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    .tracking(1.0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            TextField("A flat white before the meeting…", text: $notes, axis: .vertical)
                .font(Font.dmSerifDisplay(17).italic())
                .foregroundStyle(notes.isEmpty ? Color(hex: "C4BFB9") : Color(hex: "1C1C1E"))
                .focused($focusedField, equals: .notes)
                .tint(Color(hex: "2F402E"))
                .lineLimit(1...4)
                .padding(.horizontal, 14)
        }
        .padding(.bottom, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // MARK: - Quick Add: Tag card

    private var quickAddTagCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TAG")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    .tracking(1.0)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if selectedTagIds.isEmpty {
                // Nothing selected: one unambiguous "add" affordance — never
                // pre-populated tag chips, which read as already-selected.
                Button { showingTagPicker = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add a tag")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule().stroke(
                            style: StrokeStyle(lineWidth: 1, dash: [4])
                        ).foregroundStyle(Color(hex: "2F402E").opacity(0.3))
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedTags) { tag in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTagIds.removeAll { $0 == tag.id }
                                    tagAutoAppliedByHistory = false
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if tag.isGroup {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.8))
                                    } else {
                                        Circle().fill(Color.white.opacity(0.8)).frame(width: 7, height: 7)
                                    }
                                    Text(chipTitle(for: tag))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(hex: "2F402E"))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button { showingTagPicker = true } label: {
                            Text("Change")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "2F402E").opacity(0.55))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Color(hex: "2F402E").opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: selectedTagIds.isEmpty)
    }

    // MARK: - Quick Add: Compact date / receipt row

    private var quickAddExtrasRow: some View {
        HStack(spacing: 8) {
            // DATE
            Button { focusedField = nil; showingDatePickerSheet = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "E8F0EA")).frame(width: 30, height: 30)
                        Image(systemName: "calendar").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "4A5E50"))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DATE").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "2F402E").opacity(0.45)).tracking(0.6)
                        Text(datePillLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "1C1C1E"))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // ADD RECEIPT
            Button { showingAddReceiptSources = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: "2F402E").opacity(0.6))
                    Text("Add receipt").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "2F402E").opacity(0.65))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Color(hex: "2F402E").opacity(0.2)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Quick Add: Floating hero amount (no card, sits on background)

    private var quickAddHeroAmountBlock: some View {
        VStack(spacing: 4) {
            if !quickAddPrompt.isEmpty {
                Text(quickAddPrompt)
                    .font(Font.dmSerifDisplay(22))
                    .italic()
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)
            }

            let parts = quickAddAmountParts
            let hasDecimalTyped = amountText.contains(".")

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Button { showingCurrencyPicker = true } label: {
                    Text(currencySymbol)
                        .font(.system(size: 26, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                        .baselineOffset(8)
                }
                .buttonStyle(.plain)

                if amountText.isEmpty {
                    // Empty: cursor sits right after the currency symbol, nothing else shown
                    Capsule()
                        .fill(Color(hex: "4A5E50"))
                        .frame(width: 3, height: 48)
                        .opacity(amountCursorVisible && !keyboardVisible ? 1 : 0)
                } else {
                    // Whole number
                    Text(parts.whole)
                        .font(Font.dmSerifDisplay(76))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .animation(.none, value: amountText)

                    // Decimal section — only what the user has actually typed
                    if hasDecimalTyped {
                        let dp = decimalDisplayParts
                        HStack(spacing: 0) {
                            Text(".")
                            if !dp.typed.isEmpty { Text(dp.typed) }
                        }
                        .font(Font.dmSerifDisplay(34))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .animation(.none, value: amountText)
                    }

                    // Cursor always at the end of typed content
                    Capsule()
                        .fill(Color(hex: "4A5E50"))
                        .frame(width: 3, height: hasDecimalTyped ? 32 : 48)
                        .opacity(amountCursorVisible && !keyboardVisible ? 1 : 0)
                }
            }
            .fixedSize()

            // Thin moss underline
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, Color(hex: "4A5E50").opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 80, height: 1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 6)
        // Tap anywhere on the hero to dismiss the system keyboard and restore the keypad
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                withAnimation(.easeInOut(duration: 0.08)) { amountCursorVisible.toggle() }
            }
        }
    }


    // MARK: - Quick Add: Recurring card

    private var quickAddRecurringCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isRecurring.toggle() }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "E8F0EA"))
                            .frame(width: 30, height: 30)
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "4A5E50"))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("RECURRING")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                            .tracking(0.6)
                        Text(isRecurring ? "Repeats \(recurringInterval.adverb)" : "One-off expense")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(isRecurring ? Color(hex: "2F402E") : Color(hex: "E2DDD6"))
                            .frame(width: 28, height: 28)
                        if isRecurring {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isRecurring {
                HStack(spacing: 8) {
                    ForEach(RecurringInterval.allCases, id: \.self) { interval in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { recurringInterval = interval }
                        } label: {
                            Text(interval.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(recurringInterval == interval ? .white : Color(hex: "2F402E").opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(recurringInterval == interval ? Color(hex: "2F402E") : Color(hex: "F0EDE6"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: isRecurring)
    }

    // MARK: - PDF-only card

    private var pdfAttachmentCard: some View {
        Group {
            if let url = attachedFileURL {
                HStack(spacing: 12) {
                    // Tappable area opens the PDF preview
                    Button { showingPDFPreview = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(hex: "2F402E"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                    .lineLimit(1)
                                Text("Tap to preview · PDF document")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        attachedFileURL = nil
                        attachedImage = nil
                        attachmentKey = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "2F402E").opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .sheet(isPresented: $showingPDFPreview) {
                    PDFPreviewSheet(url: url)
                }
            }
        }
    }


    // MARK: - State 2: Receipt hero

    private var receiptHeroView: some View {
        ZStack {
            if let image = attachedImage {
                // Receipt image (tap to view full)
                Button { showingFullImage = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                }
                .buttonStyle(.plain)

                // Gradient overlay — covers ~65% from bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .init(x: 0.5, y: 0),
                        endPoint: .bottom
                    )
                    .frame(height: 170)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                if isRunningOCR {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Reading receipt…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 80)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 260)
        // Bottom-left: date + merchant + amount display
        .overlay(alignment: .bottomLeading) {
            if attachedImage != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(heroDateLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(1.2)
                    if !merchant.isEmpty {
                        Text(merchant)
                            .font(Font.dmSerifDisplay(22))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    // Tappable amount — focuses the field in the detail cluster below
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(currencySymbol)
                            .font(.system(size: 18, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(amountText.isEmpty ? "0.00" : amountText)
                            .font(.system(size: 40, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white)
                            .tracking(-1.5)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { amountFocusRequested = true }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        // Bottom-right: VIEW RECEIPT + Replace/Remove
        .overlay(alignment: .bottomTrailing) {
            if attachedImage != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    Button { showingFullImage = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 11, weight: .semibold))
                            Text("VIEW RECEIPT")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.3)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button { showingReplaceReceiptSources = true } label: {
                            Text("Replace")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .underline()
                        }
                        .buttonStyle(.plain)

                        Button {
                            attachedImage = nil
                            attachedFileURL = nil
                            attachmentKey = nil
                            source = .manual
                            enteredViaPhotoFlow = true
                            ocrPopulatedAnyField = false
                            dateManuallyEdited = false
                        } label: {
                            Text("Remove")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }


    // MARK: - State 2: Receipt review cards (quick-add card language)

    /// Compact amount card — replaces the hero amount when a receipt is
    /// attached so the amount sits in line with the rest of the cards.
    private var receiptAmountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "4A5E50"))
                Text("AMOUNT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    .tracking(1.0)
                if isRunningOCR && amountText.isEmpty {
                    ProgressView().scaleEffect(0.6).tint(Color(hex: "8F9E94"))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(alignment: .center, spacing: 4) {
                Button { showingCurrencyPicker = true } label: {
                    HStack(spacing: 2) {
                        Text(currencySymbol)
                            .font(.system(size: 18, weight: .regular, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                }
                .buttonStyle(.plain)

                // Plain, visible native field — real caret in the real text, so
                // the cursor and decimal point land exactly where they appear.
                NumericFieldWithDone(
                    text: $amountText,
                    keyboardType: usesDecimalCurrency ? .decimalPad : .numberPad,
                    font: UIFont.monospacedSystemFont(ofSize: 24, weight: .medium),
                    textAlignment: .left,
                    focusRequested: amountFocusRequested,
                    placeholder: zeroAmountPlaceholder,
                    onBeginEditing: { DispatchQueue.main.async { focusedField = .amount } },
                    onDone: { amountFocusRequested = false; focusedField = nil }
                )
                .frame(height: 34)
                .onChange(of: amountText) { _, newValue in
                    let sanitized = sanitizeAmountInput(newValue)
                    if sanitized != newValue { amountText = sanitized }
                }
                .onChange(of: focusedField) { _, newValue in
                    if newValue != .amount { formatAmount() }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    /// Date row in the extras style — no "Add receipt" here because the
    /// receipt controls (view / replace / remove) live on the hero.
    private var receiptDateRow: some View {
        Button { focusedField = nil; showingDatePickerSheet = true } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "E8F0EA")).frame(width: 30, height: 30)
                    Image(systemName: "calendar").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "4A5E50"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("DATE").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "2F402E").opacity(0.45)).tracking(0.6)
                    HStack(spacing: 5) {
                        Text(datePillLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "1C1C1E"))
                        if isRunningOCR && !dateManuallyEdited {
                            ProgressView().scaleEffect(0.5).tint(Color(hex: "8F9E94"))
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
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

    private var proUpsellCompactBanner: some View {
        Button {
            showingGoProFromOcrBanner = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "2F402E"))
                Text("Still typing? Pro reads receipts and fills this in.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F0EDE6"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Sticky bottom chrome

    private var stickySaveChrome: some View {
        Group {
            if receiptImageAttached {
                // Done button lives in the nav bar — no bottom chrome needed
                Color.clear.frame(height: 0)
            } else if keyboardVisible {
                // System keyboard is up (merchant / note editing) — slim save bar only
                VStack(spacing: 0) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        saveExpense()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                            Text("Save expense").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StickySaveCTAStyle(isEnabled: canSave))
                    .disabled(!canSave)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    if !appState.isPro { BannerAdView() }
                }
                .background(Color(hex: "F0EDE6"))
            } else {
                // Default manual mode: full custom keypad
                quickAddKeypadChrome
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
        .animation(.easeInOut(duration: 0.2), value: receiptImageAttached)
    }

    // MARK: - Custom keypad chrome

    private var quickAddKeypadChrome: some View {
        VStack(spacing: 0) {
            // 3 × 4 keypad grid
            let keys = ["1","2","3","4","5","6","7","8","9",".","0","back"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { quickKeypadPress(key) } label: {
                        Group {
                            if key == "back" {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(Color(hex: "2F402E").opacity(0.65))
                            } else {
                                Text(key)
                                    .font(Font.dmSerifDisplay(30))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "2F402E").opacity(0.06), lineWidth: 1))
                    }
                    .buttonStyle(KeypadButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Save button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                saveExpense()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    Text("Save expense").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StickySaveCTAStyle(isEnabled: canSave))
            .disabled(!canSave)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if !appState.isPro { BannerAdView() }
        }
        .background(Color(hex: "F0EDE6"))
    }

    private func quickKeypadPress(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case "back":
            guard !amountText.isEmpty else { return }
            amountText = String(amountText.dropLast())
        case ".":
            guard usesDecimalCurrency, !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        default:
            if amountText == "0" {
                amountText = key
            } else {
                if let dotIdx = amountText.firstIndex(of: ".") {
                    let decimals = amountText.distance(from: amountText.index(after: dotIdx), to: amountText.endIndex)
                    guard decimals < 2 else { return }
                }
                amountText += key
            }
        }
    }

    // MARK: - UIKit presentation

    private func presentReviewViaUIKit(images: [UIImage]) {
        let reviewView = MultiReceiptReviewView(
            images: images,
            onCancel: {
                reviewHostingController?.dismiss(animated: true) {
                    reviewHostingController = nil
                    formReady = true
                }
            },
            onDone: {
                reviewHostingController?.dismiss(animated: true) {
                    reviewHostingController = nil
                    dismiss()
                }
            }
        )
        let rootView = reviewView
            .environment(appState)
            .modelContainer(modelContext.container)
        let hc = UIHostingController(rootView: rootView)
        hc.modalPresentationStyle = .fullScreen
        // KEY FIX: default sizingOptions = .intrinsicContentSize causes the host to
        // shrink-wrap its SwiftUI content (navBar+Divider = 53pt), leaving the
        // ScrollView with 0pt height. Setting [] tells UIKit to size the view instead.
        hc.sizingOptions = []
        reviewHostingController = hc

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else {
            formReady = true
            return
        }

        var topVC = rootVC
        while let child = topVC.presentedViewController, !child.isBeingDismissed {
            topVC = child
        }

        if let dismissing = topVC.presentedViewController {
            if let coordinator = dismissing.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    topVC.present(hc, animated: true)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    topVC.present(hc, animated: true)
                }
            }
        } else {
            topVC.present(hc, animated: true)
        }
    }

    // MARK: - State / OCR / Save

    private func applyInitialState() {
        if let expense = editingExpense {
            currency = expense.currency
            let usesDecimals = CurrencyFormatter.shared.usesDecimals(for: expense.currency)
            if usesDecimals {
                amountText = String(format: "%.2f", Double(expense.amountCents) / 100.0)
            } else {
                amountText = String(format: "%.0f", Double(expense.amountCents))
            }
            date = expense.date
            merchant = expense.merchant ?? ""
            descriptionText = expense.expenseDescription ?? ""
            let trimmedNotes = expense.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            notes = !trimmedNotes.isEmpty ? (expense.notes ?? "") : (expense.expenseDescription ?? "")
            selectedTagIds = expense.resolvedTagIds
            source = ExpenseSource(rawValue: expense.source) ?? .manual
            attachmentKey = expense.attachmentKey

            if let key = expense.attachmentKey {
                if let img = AttachmentService.shared.loadImage(key: key) {
                    attachedImage = img
                } else if let data = expense.attachmentData, let img = UIImage(data: data) {
                    attachedImage = img
                }
            }
            quickAddPrompt = ""   // No prompt in edit mode
            return
        }

        // Reset all form fields to blank for a new expense
        amountText = ""
        merchant = ""
        descriptionText = ""
        notes = ""
        selectedTagIds = []
        date = Date()
        attachedImage = nil
        attachedFileURL = nil
        attachmentKey = nil
        ocrPopulatedAnyField = false
        isRunningOCR = false
        dateManuallyEdited = false
        notesExpanded = false
        showingGoProFromOcrBanner = false
        tallySuggestion = nil
        tallySuggestionDismissed = false
        merchantReturnMessage = nil
        tagAutoAppliedByHistory = false
        isRecurring = false
        recurringInterval = .monthly
        // Amount-flavored questions only — the hero sits above the amount,
        // so "what was it for" style prompts belong to the note card instead.
        let prompts = ["What's the damage?", "How much was it?", "Where'd it go?", "What did it cost?"]
        quickAddPrompt = prompts.randomElement() ?? "How much was it?"
        source = .manual
        lastImageSource = .manual
        enteredViaPhotoFlow = false
        formReady = true

        currency = appState.defaultCurrency

        if initialImage != nil || initialFileURL != nil {
            // Attachment pre-supplied (share extension or batch) — no picker,
            // land directly on the receipt review layout.
            source = .upload
            lastImageSource = .upload
            enteredViaPhotoFlow = true
            formReady = true
        } else {
            switch initialMode {
            case .camera:
                source = .camera
                lastImageSource = .camera
                enteredViaPhotoFlow = true
                formReady = false
                showingCamera = true
            case .photoLibrary:
                source = .upload
                lastImageSource = .upload
                enteredViaPhotoFlow = true
                formReady = false
                showingPhotoPicker = true
            case .uploadFile:
                source = .upload
                lastImageSource = .upload
                enteredViaPhotoFlow = true
                formReady = false
                showingDocumentPicker = true
            case .manual, .bulkImport:
                source = .manual
            }
        }
        if let img = initialImage { attachedImage = img }
        if let url = initialFileURL { attachedFileURL = url }

        // Apply OCR-derived prefill from the review screen (only sets non-empty values)
        if let prefill = batchPrefill {
            if !prefill.amountText.isEmpty { amountText = prefill.amountText }
            if !prefill.merchant.isEmpty   { merchant   = prefill.merchant }
            date = prefill.date
            if !prefill.notes.isEmpty {
                notes = prefill.notes
                notesExpanded = true
            }
        }
    }

    private func runOCR(on image: UIImage) {
        isRunningOCR = true
        Task {
            let result = await ReceiptOCRService.extract(from: image)
            await MainActor.run { applyOCRResult(result) }
        }
    }

    private func runOCROnPDF(url: URL) {
        guard let document = PDFDocument(url: url) else { return }
        isRunningOCR = true
        Task {
            var merged = ReceiptOCRResult()
            for i in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: i) else { continue }
                let image = renderPDFPage(page)
                let result = await ReceiptOCRService.extract(from: image)
                if merged.amount == nil   { merged.amount = result.amount }
                if merged.merchant == nil { merged.merchant = result.merchant }
                if merged.date == nil     { merged.date = result.date }
                if merged.notes == nil    { merged.notes = result.notes }
                if merged.currencyCode == nil { merged.currencyCode = result.currencyCode }
            }
            await MainActor.run { applyOCRResult(merged) }
        }
    }

    private func renderPDFPage(_ page: PDFPage) -> UIImage {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cgCtx = ctx.cgContext
            cgCtx.scaleBy(x: scale, y: scale)
            // PDF coordinates are bottom-up; flip to match UIKit's top-down
            cgCtx.translateBy(x: 0, y: rect.height)
            cgCtx.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: cgCtx)
        }
    }

    @MainActor
    /// Back from a picker-entered receipt review returns to the picker so a
    /// wrong photo can be swapped without restarting the expense. The scanned
    /// values are cleared — they belong to the discarded photo. Everywhere
    /// else (manual entry, share-extension hand-off, editing) back dismisses.
    private func handleBackButton() {
        let cameFromPicker = enteredViaPhotoFlow && initialImage == nil && initialFileURL == nil
        guard hasAttachment, cameFromPicker, !isEditing else {
            dismiss()
            return
        }
        let wasFile = attachedFileURL != nil
        attachedImage = nil
        attachedFileURL = nil
        amountText = ""
        merchant = ""
        notes = ""
        dateManuallyEdited = false
        ocrPopulatedAnyField = false
        formReady = false
        if wasFile || initialMode == .uploadFile {
            showingDocumentPicker = true
        } else if lastImageSource == .camera {
            showingCamera = true
        } else {
            showingPhotoPicker = true
        }
    }

    private func applyOCRResult(_ result: ReceiptOCRResult) {
        let isPro = appState.isPro
        var applied = false

        if let amount = result.amount, amountText.isEmpty || amountText == "0" || amountText == "0.00" {
            // Receipt names its currency unambiguously (€, EUR, GBP…) — adopt it
            // for this expense before formatting. A bare "$" never overrides.
            if let code = result.currencyCode, code != currency {
                currency = code
            }
            amountText = CurrencyFormatter.shared.usesDecimals(for: currency)
                ? String(format: "%.2f", amount)
                : String(format: "%.0f", amount)
            applied = true
        }
        if let extractedDate = result.date, !dateManuallyEdited {
            date = extractedDate
            applied = true
        }
        if isPro {
            if let name = result.merchant, merchant.isEmpty {
                merchant = name
                applied = true
            }
            if let ocrNotes = result.notes, notes.isEmpty {
                notes = ocrNotes
                applied = true
            }
        }

        ocrPopulatedAnyField = applied
        isRunningOCR = false

        if applied && selectedTagIds.isEmpty {
            let suggestion = TagSuggestionEngine.suggest(merchant: merchant, notes: notes, tags: Array(tags))
            tallySuggestion = suggestion
            tallySuggestionDismissed = false
        }
    }

    /// Re-runs tag suggestion from current merchant + notes text.
    /// Called after OCR, and also on every merchant/notes text change.
    private func updateTagSuggestion() {
        guard selectedTagIds.isEmpty, !tallySuggestionDismissed else { return }
        let suggestion = TagSuggestionEngine.suggest(
            merchant: merchant,
            notes: notes,
            tags: Array(tags)
        )
        guard suggestion?.tag.id != tallySuggestion?.tag.id else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tallySuggestion = suggestion
        }
    }

    /// Checks expense history for the current merchant. Auto-applies historical tag and
    /// shows a playful returning-merchant message instead of generic TallySuggests.
    private func applyMerchantHistory() {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation(.easeInOut(duration: 0.2)) { merchantReturnMessage = nil }
            // Bug 1: clear tag that was auto-applied if merchant is now empty
            if tagAutoAppliedByHistory {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagIds = []
                    tagAutoAppliedByHistory = false
                    tallySuggestionDismissed = false
                }
            }
            updateTagSuggestion()
            return
        }

        if let tagIds = historicalTagIds(for: trimmed), !tagIds.isEmpty {
            // Auto-apply only if nothing is selected yet (first match).
            // Single-selection rule: cap legacy multi-tag history to one tag.
            if selectedTagIds.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagIds = Array(tagIds.prefix(1))
                    tagAutoAppliedByHistory = true
                    tallySuggestion = nil
                    tallySuggestionDismissed = true
                }
            }
            let totalCents = totalSpent(at: trimmed)
            if totalCents > 0 {
                // Bug 3: only set the message once — don't randomise on every keystroke
                if merchantReturnMessage == nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        merchantReturnMessage = buildReturnMessage(for: trimmed, totalCents: totalCents)
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { merchantReturnMessage = nil }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { merchantReturnMessage = nil }
            // Bug 1: merchant no longer matches what was auto-applied — clear the tag
            if tagAutoAppliedByHistory {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagIds = []
                    tagAutoAppliedByHistory = false
                    tallySuggestionDismissed = false
                }
            }
            updateTagSuggestion()
        }
    }

    private func historicalTagIds(for merchantName: String) -> [String]? {
        let q = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let match = allExpenses
            .filter { ($0.merchant ?? "").lowercased() == q && !$0.resolvedTagIds.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        return match?.resolvedTagIds
    }

    private func totalSpent(at merchantName: String) -> Int {
        let q = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }
        let currentYear = Calendar.current.component(.year, from: Date())
        let excludeId = editingExpense?.id
        return allExpenses
            .filter { ($0.merchant ?? "").lowercased() == q }
            .filter { Calendar.current.component(.year, from: $0.date) == currentYear }
            .filter { $0.id != excludeId }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func buildReturnMessage(for merchantName: String, totalCents: Int) -> String {
        let wholeDollars = totalCents / 100
        let amountStr = "\(currencySymbol)\(wholeDollars)"
        let options = [
            "\(merchantName) again?… You've spent \(amountStr) here this year",
            "Back at \(merchantName)! That's \(amountStr) spent this year",
            "Another \(merchantName) visit… \(amountStr) this year and counting",
        ]
        return options.randomElement()!
    }

    @ViewBuilder
    private var merchantReturnCard: some View {
        if let msg = merchantReturnMessage, !receiptImageAttached {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "4A5E50"))
                    .padding(.top, 1)
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.75))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(hex: "EAF5EC"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "2F402E").opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private func expenseCountInMonth(of d: Date) -> Int {
        let cal = Calendar.current
        let (y, m) = (cal.component(.year, from: d), cal.component(.month, from: d))
        return allExpenses.filter {
            cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == m
        }.count
    }

    private func loadExpenses() {
        let descriptor = FetchDescriptor<ExpenseModel>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        allExpenses = (try? modelContext.fetch(descriptor)) ?? []
        cachedKnownMerchants = buildKnownMerchants()
    }

    /// Builds the sorted, deduplicated merchant name list from `allExpenses`.
    /// Called once per `loadExpenses()` so filtering on keystrokes is O(n) over
    /// the small cached list rather than O(n log n) on the full expense array.
    private func buildKnownMerchants() -> [String] {
        let byRecency = allExpenses.sorted { $0.updatedAt > $1.updatedAt }
        var seenLowercased = Set<String>()
        var unique: [String] = []
        for expense in byRecency {
            guard let raw = expense.merchant else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seenLowercased.insert(key).inserted else { continue }
            unique.append(trimmed)
        }
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func saveExpense() {
        guard let amountCents = parsedAmountCents else {
            errorMessage = "Please enter a valid amount."
            showingError = true
            return
        }

        isSaving = true
        let expenseId = editingExpense?.id ?? UUID().uuidString
        let attachmentChanged = isEditing && attachmentKey != editingExpense?.attachmentKey

        Task {
            var savedKey: String? = isEditing ? editingExpense?.attachmentKey : nil
            var rawAttachmentData: Data? = isEditing ? editingExpense?.attachmentData : nil

            if attachedImage != nil && (!isEditing || attachmentChanged || savedKey == nil) {
                if let image = attachedImage {
                    do {
                        savedKey = try await AttachmentService.shared.saveImage(image, id: expenseId)
                        rawAttachmentData = image.jpegData(compressionQuality: 0.8)
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showingError = true
                            isSaving = false
                        }
                        return
                    }
                }
            } else if let url = attachedFileURL {
                do {
                    savedKey = try await AttachmentService.shared.saveFile(from: url, id: expenseId)
                    rawAttachmentData = try? Data(contentsOf: url)
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showingError = true
                        isSaving = false
                    }
                    return
                }
            } else if !hasAttachment {
                if let oldKey = editingExpense?.attachmentKey {
                    await AttachmentService.shared.deleteAttachment(key: oldKey)
                }
                savedKey = nil
                rawAttachmentData = nil
            }

            await MainActor.run {
                if let existing = editingExpense {
                    existing.amountCents = amountCents
                    existing.currency = currency
                    existing.date = date
                    existing.expenseDescription = descriptionText.isEmpty ? nil : descriptionText
                    existing.merchant = merchant.isEmpty ? nil : merchant
                    existing.tagIds = selectedTagIds
                    existing.tagId = selectedTagIds.first ?? ""
                    existing.notes = notes.isEmpty ? nil : notes
                    existing.attachmentKey = savedKey
                    existing.attachmentData = rawAttachmentData
                    existing.updatedAt = Date()

                    do {
                        try modelContext.save()
                        loadExpenses()
                    } catch {}
                } else {
                    let countBeforeInsert = expenseCountInMonth(of: date)
                    let expense = ExpenseModel(
                        id: expenseId,
                        userId: "",
                        amountCents: amountCents,
                        currency: currency,
                        date: date,
                        description: descriptionText.isEmpty ? nil : descriptionText,
                        merchant: merchant.isEmpty ? nil : merchant,
                        tagIds: selectedTagIds,
                        notes: notes.isEmpty ? nil : notes,
                        attachmentKey: savedKey,
                        attachmentData: rawAttachmentData,
                        source: source.rawValue
                    )
                    modelContext.insert(expense)
                    do {
                        try modelContext.save()
                        appState.totalExpenseCount += 1
                        loadExpenses()
                    } catch {}
                    appState.clearFilters()

                    // Skip the pro upsell mid-batch — it would be jarring 3 times in a row
                    if !appState.isPro && onSaved == nil {
                        let newCount = countBeforeInsert + 1
                        let triggerCounts = [3, 6, 9]
                        if triggerCounts.contains(newCount) && appState.proPromptShownThisMonth < 3 {
                            appState.recordProPromptShown()
                            showingProBenefitsCard = true
                            isSaving = false
                            return
                        }
                    }
                }
                isSaving = false
                // Fire before dismiss so HomeView sets landedExpenseId before the row appears
                if onSaved == nil {
                    NotificationCenter.default.post(
                        name: .expenseLogged,
                        object: nil,
                        userInfo: [
                            "expenseId": expenseId,
                            "amountCents": amountCents,
                            "currency": currency
                        ]
                    )
                }
                onSaved?()
                dismiss()
            }
        }
    }
}

private struct ReceiptSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(hex: "DEDAD2"))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                sourceButton(icon: "camera.fill", label: "Camera") {
                    dismiss()
                    onCamera()
                }
                sourceButton(icon: "photo.fill", label: "Photos") {
                    dismiss()
                    onPhotos()
                }
                sourceButton(icon: "doc.fill", label: "File") {
                    dismiss()
                    onFile()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(hex: "F0EDE6"))
    }

    private func sourceButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
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
                Text(label)
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
}

// MARK: - Button styles

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct StickySaveCTAStyle: ButtonStyle {
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
            return Color(hex: "2F402E").opacity(0.4)
        }
        return isPressed ? Color(hex: "2D5A3F") : Color(hex: "2F402E")
    }
}

// MARK: - PDF preview

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.systemGroupedBackground
        return view
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if let doc = PDFDocument(url: url), pdfView.document == nil {
            pdfView.document = doc
        }
    }
}

struct PDFPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}
