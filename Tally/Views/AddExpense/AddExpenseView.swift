import SwiftUI
import SwiftData
import UIKit

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
    @State private var lastImageSource: ExpenseSource = .manual
    @State private var showingTagPicker = false
    @State private var showingCurrencyPicker = false
    @State private var showingFullImage = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var formReady = true
    @State private var isRunningOCR = false
    @State private var showingMonthlyLimitSheet = false
    @State private var showingProBenefitsCard = false
    @State private var showingGoProFromOcrBanner = false

    @State private var showingDatePickerSheet = false
    @State private var showingAddReceiptSources = false
    @State private var showingReplaceReceiptSources = false
    @State private var notesExpanded = false
    @State private var ocrPopulatedAnyField = false
    @State private var amountFocusRequested: Bool = false
    @State private var keyboardVisible = false

    @FocusState private var focusedField: Field?

    private var isEditing: Bool { editingExpense != nil }

    private enum Field: Hashable {
        case amount, merchant, notes
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

    private var shouldShowOcrFilledBanner: Bool {
        receiptImageAttached && ocrPopulatedAnyField && !isRunningOCR
    }

    private var knownMerchants: [String] {
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

    private var filteredMerchantSuggestions: [String] {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard focusedField == .merchant, !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()
        return knownMerchants.filter { candidate in
            let low = candidate.lowercased()
            return low.contains(q) && low != q
        }
    }

    private var topMerchantSuggestions: [String] {
        Array(filteredMerchantSuggestions.prefix(3))
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
            addExpenseNavigationRoot
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = false }
        }
        .onTapGesture {
            UIApplication.shared.endEditing()
        }
    }

    /// Split from `body` so the type checker can infer `NavigationStack` without timing out.
    private var addExpenseNavigationRoot: some View {
        addExpenseFormWithSheets
            .onChange(of: attachedImage) { _, newValue in
                if newValue == nil {
                    ocrPopulatedAnyField = false
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
            .onChange(of: formReady) { _, ready in
                guard ready, focusedField == nil, !hasAttachment else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard attachedImage == nil, attachedFileURL == nil else { return }
                    amountFocusRequested = true
                }
            }
            .onChange(of: notes) { _, newVal in
                if !newVal.isEmpty { notesExpanded = true }
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
                            Button("Done") { showingDatePickerSheet = false }
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
                        multiImagesInProgress = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            multiImagesInProgress = false
                            presentReviewViaUIKit(images: images)
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
            .sheet(isPresented: $showingMonthlyLimitSheet) {
                MonthlyLimitSheet(onProUnlocked: {
                    saveExpense()
                })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
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
            .navigationTitle(isEditing ? "Edit expense" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(hex: "8F9E94"))
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
                .presentationBackground(Color(hex: "F6F5F3"))
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
                .presentationBackground(Color(hex: "F6F5F3"))
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
                tagsRowView

                notesRowView
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

        if shouldShowOcrFilledBanner {
            ocrFilledBanner
        }

        if !appState.isPro {
            proUpsellCompactBanner
        }

        receiptStateAmountMerchantDateCluster
    }

    @ViewBuilder
    private var manualEntryFormBlock: some View {
        amountHeroView
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

        merchantDateView

        if attachedFileURL != nil {
            pdfAttachmentCard
        }

        tagsRowView

        addReceiptView

        notesRowView
    }

    // MARK: - State 1: Amount hero

    private var amountHeroView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amount")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    showingCurrencyPicker = true
                } label: {
                    Text(currencySymbol)
                        .font(.system(size: 28, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                }
                .buttonStyle(.plain)

                ZStack(alignment: .leading) {
                    NumericFieldWithDone(
                        text: $amountText,
                        keyboardType: usesDecimalCurrency ? .decimalPad : .numberPad,
                        font: UIFont.monospacedSystemFont(ofSize: 52, weight: .regular),
                        textAlignment: .natural,
                        focusRequested: amountFocusRequested,
                        hidesFieldText: true,
                        onBeginEditing: { DispatchQueue.main.async { focusedField = .amount } },
                        onDone: {
                            amountFocusRequested = false
                            focusedField = nil
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .onChange(of: amountText) { _, newValue in
                        let sanitized = sanitizeAmountInput(newValue)
                        if sanitized != newValue { amountText = sanitized }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmount() }
                    }

                    Text(amountText.isEmpty ? zeroAmountPlaceholder : amountText)
                        .font(.system(size: 52, weight: .regular, design: .monospaced))
                        .foregroundStyle(amountText.isEmpty ? Color(hex: "8F9E94") : Color(hex: "1C1C1E"))
                        .tracking(-2)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            amountFocusRequested = true
        })
    }

    // MARK: - State 1: Merchant + date cluster

    private var merchantDateView: some View {
        VStack(spacing: 2) {
            merchantRowShape(radiusTop: 14, radiusBottom: 6)
            dateRowShape(radiusTop: 6, radiusBottom: 14)
        }
        .padding(.horizontal, 16)
    }

    private func merchantRowShape(radiusTop: CGFloat, radiusBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))

            TextField("Where did you pay?", text: $merchant)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .tint(Color(hex: "2F402E"))

            merchantSuggestionInlineList()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(unevenRect(topLeading: radiusTop, topTrailing: radiusTop, bottomLeading: radiusBottom, bottomTrailing: radiusBottom))
        .overlay(
            unevenRect(topLeading: radiusTop, topTrailing: radiusTop, bottomLeading: radiusBottom, bottomTrailing: radiusBottom)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func merchantSuggestionInlineList() -> some View {
        let suggestions = topMerchantSuggestions
        if focusedField == .merchant && !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        merchant = name
                        focusedField = nil
                    } label: {
                        Text(name)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if name != suggestions.last {
                        Rectangle()
                            .fill(Color(hex: "DEDAD2"))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)
            .animation(nil, value: suggestions)
        }
    }

    private func dateRowShape(radiusTop: CGFloat, radiusBottom: CGFloat) -> some View {
        Button {
            focusedField = nil
            showingDatePickerSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of transaction")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "8F9E94"))

                HStack(spacing: 10) {
                    Text(Self.datePillFormatter.string(from: date))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "1C1C1E"))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .buttonStyle(.plain)
        .clipShape(unevenRect(topLeading: radiusTop, topTrailing: radiusTop, bottomLeading: radiusBottom, bottomTrailing: radiusBottom))
        .overlay(
            unevenRect(topLeading: radiusTop, topTrailing: radiusTop, bottomLeading: radiusBottom, bottomTrailing: radiusBottom)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
    }

    // MARK: - Tags row

    private var tagsRowView: some View {
        Group {
            if selectedTagIds.isEmpty {
                Button {
                    showingTagPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "8F9E94"))
                        Text("Add tag")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "C4BFB9"))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "C4BFB9"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedTags) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(tag.tagColor.primaryColor)
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "2F402E"))
                                Button {
                                    selectedTagIds.removeAll { $0 == tag.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "2F402E").opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 14)
                            .padding(.trailing, 10)
                            .background(Color(hex: "E8F0EA"))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color(hex: "2F402E"), lineWidth: 1.5)
                            )
                        }

                        Button {
                            showingTagPicker = true
                        } label: {
                            Text("+ Add tag")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color(hex: "DEDAD2"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 0)
            }
        }
    }

    // MARK: - Add receipt card (state 1 only in stack)

    private var addReceiptView: some View {
        Button {
            showingAddReceiptSources = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "E8F0EA"))
                        .frame(width: 40, height: 40)
                    Image(systemName: "paperclip")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "2F402E"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add receipt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text("Scan, upload photo or PDF")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - PDF-only card

    private var pdfAttachmentCard: some View {
        Group {
            if let url = attachedFileURL {
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
                        attachedFileURL = nil
                        attachedImage = nil
                        attachmentKey = nil
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
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
            }
        }
    }

    // MARK: - Notes

    private var notesRowView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if notesExpanded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .padding(.top, 10)

                    TextEditor(text: $notes)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72)
                        .focused($focusedField, equals: .notes)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Button {
                    notesExpanded = true
                    focusedField = .notes
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "8F9E94"))
                        Text("Add a note…")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "C4BFB9"))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - State 2: Receipt hero

    private var receiptHeroView: some View {
        ZStack {
            if let image = attachedImage {
                Button { showingFullImage = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                }
                .buttonStyle(.plain)

                VStack {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200 / 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                if isRunningOCR {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Reading receipt…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 200)
        .overlay(alignment: .bottomTrailing) {
            if attachedImage != nil {
                HStack(spacing: 14) {
                    Button {
                        showingReplaceReceiptSources = true
                    } label: {
                        Text("Replace")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
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
                    } label: {
                        Text("Remove")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var ocrFilledBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Color(hex: "2F402E"))
                .frame(width: 5, height: 5)
            Text("Fields filled from receipt — review before saving")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "2F402E"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "E8F0EA"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - State 2: Amount + merchant + date cluster

    private var receiptStateAmountMerchantDateCluster: some View {
        VStack(spacing: 2) {
            receiptAmountRow
            receiptMerchantRow
            dateRowForReceiptState
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
                Text("Upgrade to Pro for merchant & notes auto-fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F6F5F3"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var receiptAmountRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))

            HStack(spacing: 6) {
                Button { showingCurrencyPicker = true } label: {
                    Text(currencySymbol)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                }
                .buttonStyle(.plain)

                ZStack(alignment: .leading) {
                    NumericFieldWithDone(
                        text: $amountText,
                        keyboardType: usesDecimalCurrency ? .decimalPad : .numberPad,
                        font: UIFont.monospacedSystemFont(ofSize: 36, weight: .regular),
                        textAlignment: .natural,
                        focusRequested: amountFocusRequested,
                        hidesFieldText: true,
                        onBeginEditing: { DispatchQueue.main.async { focusedField = .amount } },
                        onDone: {
                            amountFocusRequested = false
                            focusedField = nil
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .onChange(of: amountText) { _, newValue in
                        let sanitized = sanitizeAmountInput(newValue)
                        if sanitized != newValue { amountText = sanitized }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmount() }
                    }

                    Text(amountText.isEmpty ? zeroAmountPlaceholder : amountText)
                        .font(.system(size: 36, weight: .regular, design: .monospaced))
                        .foregroundStyle(amountText.isEmpty ? Color(hex: "8F9E94") : Color(hex: "1C1C1E"))
                        .tracking(-2)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4))
        .overlay(
            unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { amountFocusRequested = true }
    }

    private var receiptMerchantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))

            TextField("Where did you pay?", text: $merchant)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .tint(Color(hex: "2F402E"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 4, bottomTrailing: 4))
        .overlay(
            unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 4, bottomTrailing: 4)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var dateRowForReceiptState: some View {
        Button {
            focusedField = nil
            showingDatePickerSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of transaction")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "8F9E94"))

                HStack(spacing: 10) {
                    Text(Self.datePillFormatter.string(from: date))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "1C1C1E"))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .buttonStyle(.plain)
        .clipShape(unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 14, bottomTrailing: 14))
        .overlay(
            unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 14, bottomTrailing: 14)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Sticky save

    private var stickySaveChrome: some View {
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
                    saveExpense()
                } label: {
                    Text("Save expense")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StickySaveCTAStyle(isEnabled: canSave))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .disabled(!canSave)
            }
            .background(Color(hex: "F6F5F3"))

            if !appState.isPro {
                BannerAdView()
            }
        }
    }

    // MARK: - Helpers

    private func unevenRect(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing,
            style: .continuous
        )
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
        notesExpanded = false
        showingGoProFromOcrBanner = false
        source = .manual
        lastImageSource = .manual
        enteredViaPhotoFlow = false
        formReady = true

        currency = appState.defaultCurrency

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
        if let img = initialImage {
            attachedImage = img
            // Image was pre-supplied (batch mode) — treat as uploaded, not manual
            if source == .manual { source = .upload }
        }
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
            await MainActor.run {
                let isPro = appState.isPro
                var applied = false

                if let amount = result.amount, amountText.isEmpty || amountText == "0" || amountText == "0.00" {
                    if CurrencyFormatter.shared.usesDecimals(for: currency) {
                        amountText = String(format: "%.2f", amount)
                    } else {
                        amountText = String(format: "%.0f", amount)
                    }
                    applied = true
                }
                if let extractedDate = result.date {
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
            }
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
    }

    private func saveExpense() {
        guard let amountCents = parsedAmountCents else {
            errorMessage = "Please enter a valid amount."
            showingError = true
            return
        }

        if !isEditing && !appState.isPro {
            let countInMonth = expenseCountInMonth(of: date)
            if countInMonth >= 15 {
                showingMonthlyLimitSheet = true
                return
            }
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
        .background(Color(hex: "F6F5F3"))
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

// MARK: - Button style (sticky save pressed state)

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
