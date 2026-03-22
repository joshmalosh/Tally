import SwiftUI
import SwiftData

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AdManager.self) private var adManager
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
    @State private var isRecurring = false
    @State private var recurringFrequency = "monthly"
    @State private var showingRecurringEditActionSheet = false
    @State private var pendingRecurringEditChoice: RecurringEditChoice?
    @State private var showingMonthlyLimitSheet = false
    @State private var showingProBenefitsCard = false
    @State private var showingGoProFromOcrBanner = false

    @FocusState private var focusedField: Field?

    private enum RecurringEditChoice {
        case futureOnly, allEntries
    }

    private var isEditing: Bool { editingExpense != nil }

    private enum Field: Hashable {
        case amount, merchant, notes
    }

    // MARK: - Computed Properties

    private var parsedAmountCents: Int? {
        guard let amount = Double(amountText), amount > 0 else { return nil }
        if CurrencyFormatter.shared.usesDecimals(for: currency) {
            return Int(round(amount * 100))
        }
        return Int(round(amount))
    }

    private func formatAmount() {
        guard let value = Double(amountText), value > 0 else { return }
        if CurrencyFormatter.shared.usesDecimals(for: currency) {
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

    private var shouldShowOcrUpsellBanner: Bool {
        !appState.isPro && attachedImage != nil
    }

    private var shouldShowBanner: Bool {
        !appState.isPro && !isKeyboardVisible
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    if formReady {
                        formContent
                    }

                    if shouldShowBanner {
                        BannerAdView()
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: shouldShowBanner)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit expense" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isEditing, let exp = editingExpense, exp.isRecurring {
                            showingRecurringEditActionSheet = true
                        } else {
                            saveExpense(recurringEditChoice: nil)
                        }
                    }) {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(SaveButtonStyle(isEnabled: canSave))
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Apply this change to future expenses only, or update all past entries too?", isPresented: $showingRecurringEditActionSheet, titleVisibility: .visible) {
                Button("Future only") { saveExpense(recurringEditChoice: .futureOnly) }
                Button("All entries") { saveExpense(recurringEditChoice: .allEntries) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how to apply your edits to this recurring expense.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
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
                TagPickerSheet(selectedTagIds: $selectedTagIds)
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
                MonthlyLimitSheet()
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
                if let image = newValue {
                    if AttachmentService.exceedsMaxSize(image) {
                        attachedImage = nil
                        attachedFileURL = nil
                        errorMessage = "This image is too large. Maximum size is 20 MB."
                        showingError = true
                        return
                    }
                    source = showingCamera ? .camera : .upload
                    #if DEBUG
                    let ocrAllowed = appState.ocrEnabled && !isEditing
                    #else
                    let ocrAllowed = appState.isPro && appState.ocrEnabled && !isEditing
                    #endif
                    if ocrAllowed {
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
                if ready && focusedField == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = .amount
                    }
                }
            }
            .onAppear { applyInitialState() }
            .onChange(of: editingExpense?.id, initial: true) { _, _ in
                if let expense = editingExpense {
                    isRecurring = expense.isRecurring
                    let validFreqs = ["weekly", "monthly", "yearly"]
                    recurringFrequency = validFreqs.contains(expense.recurringFrequency) ? expense.recurringFrequency : "monthly"
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

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if hasAttachment {
                    receiptPreview
                        .padding(.bottom, 14)
                } else if enteredViaPhotoFlow || isEditing {
                    reattachPlaceholder
                        .padding(.bottom, 14)
                }

                if shouldShowOcrUpsellBanner {
                    ocrUpsellBanner
                        .padding(.bottom, 14)
                }

                amountField
                    .padding(.bottom, 14)

                merchantField
                    .padding(.bottom, 14)

                dateRow
                    .padding(.bottom, 14)

                recurringSection
                    .padding(.bottom, 14)

                tagChips
                    .padding(.bottom, 14)

                if !hasAttachment && !enteredViaPhotoFlow && !isEditing {
                    addReceiptRow
                        .padding(.bottom, 14)
                }

                notesField
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, hasAttachment ? Spacing.sm : Spacing.smd)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - OCR Upsell Banner

    private var ocrUpsellBanner: some View {
        Button {
            showingGoProFromOcrBanner = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8F9E94"))
                Text("Upgrade to Pro to auto-fill this receipt ")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))
                + Text("Upgrade")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Receipt Preview (Compact)

    private var receiptPreview: some View {
        ZStack(alignment: .topTrailing) {
            if let image = attachedImage {
                // Fixed 200pt container — no intrinsic sizing, prevents constraint conflicts
                ZStack {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                    Button { showingFullImage = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 200)
                    }
                    .buttonStyle(.plain)

                    if isRunningOCR {
                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                                Text("Reading receipt...")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, Spacing.smd)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            .padding(.bottom, Spacing.sm)
                            .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else if let url = attachedFileURL {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.brandPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(Fonts.body(15))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("PDF document")
                            .font(Fonts.caption(13))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
            }

            Button {
                attachedImage = nil
                attachedFileURL = nil
                attachmentKey = nil
                source = .manual
                enteredViaPhotoFlow = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.9))
                    .clipShape(Circle())
            }
            .padding(Spacing.sm)
        }
    }

    // MARK: - Reattach Placeholder

    private var reattachPlaceholder: some View {
        Menu {
            Button {
                showingCamera = true
            } label: {
                Label("Camera", systemImage: "camera.fill")
            }
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Photos", systemImage: "photo")
            }
            Button {
                showingDocumentPicker = true
            } label: {
                Label("File", systemImage: "doc.fill")
            }
        } label: {
            VStack(spacing: Spacing.smd) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.textMuted)

                Text("Add receipt or photo")
                    .font(Fonts.label(14))
                    .foregroundStyle(Color.brandPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.borderColor, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
    }

    // MARK: - Amount Field

    private var amountField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Amount")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: Spacing.xs) {
                Button { showingCurrencyPicker = true } label: {
                    HStack(spacing: 3) {
                        Text(currencySymbol)
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(Color.textMuted)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)

                TextField(
                    CurrencyFormatter.shared.usesDecimals(for: currency) ? "0.00" : "0",
                    text: $amountText
                )
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .keyboardType(CurrencyFormatter.shared.usesDecimals(for: currency) ? .decimalPad : .numberPad)
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
            .padding(.horizontal, Spacing.md)
            .frame(height: 64)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(focusedField == .amount ? Color.brandPrimary : Color.borderColor, lineWidth: 1)
            )
        }
    }

    // MARK: - Merchant Field

    private var merchantField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Merchant")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            TextField("Where did you pay?", text: $merchant)
                .font(Fonts.body(16))
                .foregroundStyle(Color.textPrimary)
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, Spacing.md)
                .frame(height: 48)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(focusedField == .merchant ? Color.brandPrimary : Color.borderColor, lineWidth: 1)
                )

            if !merchantSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(merchantSuggestions.prefix(5), id: \.self) { name in
                            Button {
                                merchant = name
                                focusedField = nil
                            } label: {
                                Text(name)
                                    .font(Fonts.label(14))
                                    .foregroundStyle(Color.brandPrimary)
                                    .padding(.horizontal, Spacing.smd)
                                    .padding(.vertical, 6)
                                    .background(Color.brandTint)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: merchantSuggestions)
    }

    // MARK: - Add Receipt Row

    private var addReceiptRow: some View {
        Menu {
            Button {
                showingCamera = true
            } label: {
                Label("Camera", systemImage: "camera.fill")
            }
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Photos", systemImage: "photo")
            }
            Button {
                showingDocumentPicker = true
            } label: {
                Label("File", systemImage: "doc.fill")
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "paperclip")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                Text("Add receipt")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .frame(height: 44)
        }
    }

    // MARK: - Date Row

    private var dateRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Date")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            ZStack {
                HStack {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(Fonts.body(16))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 48)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
                .allowsHitTesting(false)

                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorMultiply(.clear)
                    .frame(height: 48)
            }
        }
    }

    // MARK: - Recurring

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle("Recurring", isOn: $isRecurring)
                .tint(Color.brandPrimary)
            if isRecurring {
                Picker("Frequency", selection: $recurringFrequency) {
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                    Text("Yearly").tag("yearly")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func nextDueDate(from base: Date, frequency: String) -> Date {
        let cal = Calendar.current
        switch frequency {
        case "weekly":
            return cal.date(byAdding: .weekOfYear, value: 1, to: base) ?? base
        case "yearly":
            return cal.date(byAdding: .year, value: 1, to: base) ?? base
        default:
            return cal.date(byAdding: .month, value: 1, to: base) ?? base
        }
    }

    // MARK: - Tags

    private var tagChips: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tags")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            Button { showingTagPicker = true } label: {
                HStack(spacing: Spacing.sm) {
                    if selectedTags.isEmpty {
                        Text("Select tags")
                            .font(Fonts.body(16))
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                    } else {
                        selectedTagPills
                        Spacer(minLength: Spacing.xs)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 48)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var selectedTagPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(selectedTags) { tag in
                HStack(spacing: 5) {
                    Circle()
                        .fill(tag.tagColor.primaryColor)
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                        .font(Fonts.body(14))
                        .foregroundStyle(tag.tagColor.primaryColor)
                    Button {
                        selectedTagIds.removeAll { $0 == tag.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tag.tagColor.primaryColor.opacity(0.6))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tag.tagColor.tintColor)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Notes Field

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notes")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)

            TextEditor(text: $notes)
                .font(Fonts.body(16))
                .foregroundStyle(Color.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(Spacing.smd)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
        }
    }

    // MARK: - State

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
            notes = expense.notes ?? ""
            selectedTagIds = expense.resolvedTagIds
            source = ExpenseSource(rawValue: expense.source) ?? .manual
            attachmentKey = expense.attachmentKey
            isRecurring = expense.isRecurring
            recurringFrequency = expense.recurringFrequency

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

    // MARK: - OCR

    private func runOCR(on image: UIImage) {
        isRunningOCR = true
        Task {
            let result = await ReceiptOCRService.extract(from: image)
            await MainActor.run {
                if let amount = result.amount, amountText.isEmpty || amountText == "0" || amountText == "0.00" {
                    if CurrencyFormatter.shared.usesDecimals(for: currency) {
                        amountText = String(format: "%.2f", amount)
                    } else {
                        amountText = String(format: "%.0f", amount)
                    }
                }
                if let name = result.merchant, merchant.isEmpty {
                    merchant = name
                }
                if let extractedDate = result.date {
                    date = extractedDate
                }
                if let ocrNotes = result.notes, notes.isEmpty {
                    notes = ocrNotes
                }
                isRunningOCR = false
            }
        }
    }

    // MARK: - Save

    private struct SaveButtonStyle: ButtonStyle {
        let isEnabled: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(isEnabled
                    ? (configuration.isPressed
                        ? Color.brandPrimary.opacity(0.7)
                        : Color.brandPrimary)
                    : Color.textMuted
                )
                .animation(.easeInOut(duration: 0.13), value: configuration.isPressed)
        }
    }

    private func expenseCountInMonth(of d: Date) -> Int {
        let cal = Calendar.current
        let (y, m) = (cal.component(.year, from: d), cal.component(.month, from: d))
        return allExpenses.filter {
            cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == m
        }.count
    }

    private func saveExpense(recurringEditChoice: RecurringEditChoice?) {
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

        Task { @MainActor in
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
                    existing.isRecurring = isRecurring
                    existing.recurringFrequency = recurringFrequency
                    if isRecurring {
                        existing.nextDueDate = self.nextDueDate(from: date, frequency: recurringFrequency)
                    } else {
                        existing.nextDueDate = nil
                    }
                    existing.updatedAt = Date()

                    // "All entries" — update all logged instances from this template
                    if recurringEditChoice == .allEntries && existing.isRecurring {
                        let templateId = existing.id
                        for exp in allExpenses where exp.recurrenceTemplateId == templateId {
                            exp.amountCents = amountCents
                            exp.currency = currency
                            exp.expenseDescription = descriptionText.isEmpty ? nil : descriptionText
                            exp.merchant = merchant.isEmpty ? nil : merchant
                            exp.tagIds = selectedTagIds
                            exp.tagId = selectedTagIds.first ?? ""
                            exp.notes = notes.isEmpty ? nil : notes
                            exp.updatedAt = Date()
                        }
                    }

                    do {
                        try modelContext.save()
                        #if DEBUG
                        print("[Tally] Expense updated: \(expenseId)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[Tally] ERROR updating expense: \(error)")
                        #endif
                    }
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
                    expense.isRecurring = isRecurring
                    expense.recurringFrequency = recurringFrequency
                    if isRecurring {
                        expense.nextDueDate = nextDueDate(from: date, frequency: recurringFrequency)
                    }
                    modelContext.insert(expense)
                    do {
                        try modelContext.save()
                        appState.totalExpenseCount += 1
                        #if DEBUG
                        print("[Tally] Expense saved: \(expenseId)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[Tally] ERROR saving expense: \(error)")
                        #endif
                    }
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
