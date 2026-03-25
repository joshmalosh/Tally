import SwiftUI
import SwiftData
import UIKit

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var allExpenses: [ExpenseModel]

    var initialMode: AddEntryMode = .manual
    var initialImage: UIImage? = nil
    var initialFileURL: URL? = nil
    var editingExpense: ExpenseModel? = nil

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

    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var showingTagPicker = false
    @State private var showingCurrencyPicker = false
    @State private var showingFullImage = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var formReady = true
    @State private var isKeyboardVisible = false
    @State private var isRunningOCR = false
    @State private var showingMonthlyLimitSheet = false
    @State private var showingProBenefitsCard = false
    @State private var showingGoProFromOcrBanner = false

    @State private var showingDatePickerSheet = false
    @State private var showingAddReceiptSources = false
    @State private var showingReplaceReceiptSources = false
    @State private var notesExpanded = false
    @State private var ocrPopulatedAnyField = false

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

    private var isAmountDisplayEmpty: Bool {
        amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var currencySymbol: String {
        CurrencyFormatter.shared.symbol(for: currency)
    }

    private var canSave: Bool {
        parsedAmountCents != nil && !isSaving
    }

    private var hasAttachment: Bool {
        attachedImage != nil || attachedFileURL != nil
    }

    private var shouldShowBanner: Bool {
        !appState.isPro && !isKeyboardVisible
    }

    /// Save ~56pt + vertical padding, optional ad ~52pt, safe bottom ~34, margin 16.
    private var formBottomChromeClearance: CGFloat {
        let saveChrome: CGFloat = 56 + 36
        let banner: CGFloat = shouldShowBanner ? 52 : 0
        let safeBottom: CGFloat = 34
        let margin: CGFloat = 16
        return saveChrome + banner + safeBottom + margin
    }

    private var selectedTags: [TagModel] {
        selectedTagIds.compactMap { id in tags.first { $0.id == id } }
    }

    private var knownMerchants: [String] {
        let merchants = Set(
            allExpenses
                .compactMap { $0.merchant }
                .filter { !$0.isEmpty }
        )
        return merchants.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var merchantSuggestions: [String] {
        guard !merchant.isEmpty, focusedField == .merchant else { return [] }
        let query = merchant.lowercased()
        return knownMerchants.filter {
            $0.lowercased().hasPrefix(query) && $0.lowercased() != query
        }
    }

    private var shouldShowOcrFilledBanner: Bool {
        receiptImageAttached && ocrPopulatedAnyField && !isRunningOCR
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
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                Group {
                    if formReady {
                        ScrollView {
                            formScrollStack
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scrollDismissesKeyboard(.interactively)
                        .simultaneousGesture(
                            TapGesture().onEnded { _ in
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if formReady {
                    stickySaveChrome
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .navigationTitle(isEditing ? "Edit expense" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "346049"), for: .keyboard)
            .toolbarBackground(.visible, for: .keyboard)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
                }
            }
            .confirmationDialog("Add receipt", isPresented: $showingAddReceiptSources, titleVisibility: .visible) {
                Button("Camera") { showingCamera = true }
                Button("Photos") { showingPhotoPicker = true }
                Button("File") { showingDocumentPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Replace receipt", isPresented: $showingReplaceReceiptSources, titleVisibility: .visible) {
                Button("Camera") { showingCamera = true }
                Button("Photos") { showingPhotoPicker = true }
                Button("File") { showingDocumentPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
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
                                .foregroundStyle(Color(hex: "346049"))
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
                PhotosPicker(image: $attachedImage, onCancel: {
                    if enteredViaPhotoFlow && attachedImage == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dismiss()
                        }
                    }
                })
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
                    source = showingCamera ? .camera : .upload
                    ocrPopulatedAnyField = false
                    if !isEditing {
                        runOCR(on: image)
                    }
                }
            }
            .onChange(of: showingCamera) { _, showing in
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
                if !showing && !formReady {
                    withAnimation(.easeIn(duration: 0.2)) { formReady = true }
                }
            }
            .onChange(of: showingDocumentPicker) { _, showing in
                if !showing && !formReady {
                    withAnimation(.easeIn(duration: 0.2)) { formReady = true }
                }
            }
            .onChange(of: formReady) { _, ready in
                if ready && focusedField == nil && !receiptImageAttached {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = .amount
                    }
                }
            }
            .onChange(of: notes) { _, newVal in
                if !newVal.isEmpty { notesExpanded = true }
            }
            .onAppear {
                applyInitialState()
                if !receiptImageAttached, notesExpanded == false, !notes.isEmpty {
                    notesExpanded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
        }
    }

    // MARK: - Scroll content

    private var formScrollStack: some View {
        VStack(spacing: 8) {
            if receiptImageAttached {
                receiptImageHero
                    .transition(.move(edge: .top).combined(with: .opacity))

                if shouldShowOcrFilledBanner {
                    ocrFilledBanner
                }

                if !appState.isPro {
                    proUpsellCompactBanner
                }

                receiptStateAmountMerchantDateCluster
            } else {
                amountHeroBlock
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

                merchantDateCardCluster

                if attachedFileURL != nil {
                    pdfAttachmentCard
                }

                tagsRow

                addReceiptCard

                notesRow
            }

            if receiptImageAttached {
                tagsRow

                notesRow
            }
        }
        .padding(.top, 12)
        .padding(.bottom, formBottomChromeClearance)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: receiptImageAttached)
    }

    // MARK: - State 1: Amount hero

    private var amountHeroBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AMOUNT")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "346049").opacity(0.7))
                .tracking(0.8)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    showingCurrencyPicker = true
                } label: {
                    Text(currencySymbol)
                        .font(.system(size: 28, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "346049").opacity(0.5))
                }
                .buttonStyle(.plain)

                TextField("", text: $amountText, prompt: Text(zeroAmountPlaceholder)
                    .font(.system(size: 52, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(-2))
                    .font(.system(size: 52, weight: .regular, design: .monospaced))
                    .foregroundStyle(isAmountDisplayEmpty ? Color(hex: "8F9E94") : Color(hex: "1C1C1E"))
                    .tracking(-2)
                    .keyboardType(usesDecimalCurrency ? .decimalPad : .numberPad)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1
                            ? parts[0] + "." + parts.dropFirst().joined()
                            : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmount() }
                    }

                if focusedField != .amount {
                    TimelineView(.periodic(from: .now, by: 0.55)) { context in
                        let on = Int(context.date.timeIntervalSince1970 / 0.55) % 2 == 0
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: "346049"))
                            .frame(width: 3, height: 48)
                            .opacity(on ? 1 : 0)
                    }
                }
            }

            Text("Tap to enter amount")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "8F9E94"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color(hex: "346049").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .amount
        }
        .onAppear {
            if !isEditing, focusedField == nil {
                focusedField = .amount
            }
        }
    }

    // MARK: - State 1: Merchant + date cluster

    private var merchantDateCardCluster: some View {
        VStack(spacing: 2) {
            merchantRowShape(radiusTop: 14, radiusBottom: 6)
            dateRowShape(radiusTop: 6, radiusBottom: 14)
        }
        .padding(.horizontal, 16)
    }

    private func merchantRowShape(radiusTop: CGFloat, radiusBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MERCHANT")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.6)
                .textCase(.uppercase)

            TextField("Where did you pay?", text: $merchant)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .tint(Color(hex: "346049"))

            if !merchantSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(merchantSuggestions.prefix(5), id: \.self) { name in
                            Button {
                                merchant = name
                                focusedField = nil
                            } label: {
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(hex: "346049"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "E8F0EA"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
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

    private func dateRowShape(radiusTop: CGFloat, radiusBottom: CGFloat) -> some View {
        Button {
            showingDatePickerSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("DATE OF TRANSACTION")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .textCase(.uppercase)

                HStack(spacing: 10) {
                    Text(Calendar.current.isDateInToday(date) ? "Today" : Self.shortDateString(date))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "346049"))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(hex: "E8F0EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text(Self.datePillFormatter.string(from: date))
                        .font(.system(size: 15, weight: .regular))
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

    private static func shortDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    // MARK: - Tags row

    private var tagsRow: some View {
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
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(tag.tagColor.primaryColor)
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "346049"))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color(hex: "E8F0EA"))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color(hex: "346049"), lineWidth: 1.5)
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

    private var addReceiptCard: some View {
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
                        .foregroundStyle(Color(hex: "346049"))
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
                        .foregroundStyle(Color(hex: "346049"))
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
                    .foregroundStyle(Color(hex: "346049"))
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

    private var notesRow: some View {
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

    private var receiptImageHero: some View {
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
                .fill(Color(hex: "346049"))
                .frame(width: 5, height: 5)
            Text("Fields filled from receipt — review before saving")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "346049"))
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
                    .foregroundStyle(Color(hex: "346049"))
                Text("Upgrade to Pro for merchant & notes auto-fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "346049"))
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
            Text("AMOUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "346049").opacity(0.7))
                .tracking(0.8)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                Button { showingCurrencyPicker = true } label: {
                    Text(currencySymbol)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "346049").opacity(0.5))
                }
                .buttonStyle(.plain)

                TextField("", text: $amountText, prompt: Text(zeroAmountPlaceholder)
                    .font(.system(size: 36, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "8F9E94")))
                    .font(.system(size: 36, weight: .regular, design: .monospaced))
                    .foregroundStyle(isAmountDisplayEmpty ? Color(hex: "8F9E94") : Color(hex: "1C1C1E"))
                    .keyboardType(usesDecimalCurrency ? .decimalPad : .numberPad)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1
                            ? parts[0] + "." + parts.dropFirst().joined()
                            : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmount() }
                    }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "346049").opacity(0.06))
        .clipShape(unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4))
        .overlay(
            unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .amount }
    }

    private var receiptMerchantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MERCHANT")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.6)
                .textCase(.uppercase)

            TextField("Where did you pay?", text: $merchant)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
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
            showingDatePickerSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("DATE OF TRANSACTION")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .textCase(.uppercase)

                HStack(spacing: 10) {
                    Text(Calendar.current.isDateInToday(date) ? "Today" : Self.shortDateString(date))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "346049"))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(hex: "E8F0EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text(Self.datePillFormatter.string(from: date))
                        .font(.system(size: 15, weight: .regular))
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

            if shouldShowBanner {
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
                Task {
                    if let img = await AttachmentService.shared.loadImage(key: key) {
                        attachedImage = img
                    } else if let data = expense.attachmentData, let img = UIImage(data: data) {
                        attachedImage = img
                    }
                }
            }
            return
        }

        currency = appState.defaultCurrency

        switch initialMode {
        case .camera:
            source = .camera
            enteredViaPhotoFlow = true
            formReady = false
            showingCamera = true
        case .photoLibrary:
            source = .upload
            enteredViaPhotoFlow = true
            formReady = false
            showingPhotoPicker = true
        case .uploadFile:
            source = .upload
            enteredViaPhotoFlow = true
            formReady = false
            showingDocumentPicker = true
        case .manual, .bulkImport:
            source = .manual
            focusedField = .amount
        }
        if let img = initialImage { attachedImage = img }
        if let url = initialFileURL { attachedFileURL = url }
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
                    } catch {}
                    appState.clearFilters()

                    if !appState.isPro {
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
                dismiss()
            }
        }
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
            return Color(hex: "346049").opacity(0.4)
        }
        return isPressed ? Color(hex: "2D5A3F") : Color(hex: "346049")
    }
}
