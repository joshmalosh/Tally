import SwiftUI
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
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    @State private var tallySuggestion: TagSuggestionEngine.Suggestion? = nil
    @State private var tallySuggestionDismissed = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount, merchant, notes
    }

    private var expense: ExpenseModel? {
        activeExpenses.first { $0.id == expenseId }
    }

    private var receiptImageAttached: Bool { attachmentImage != nil }

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

    /// "18 APR 2026" style for hero overlay
    private var heroDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date).uppercased()
    }

    /// Split amountText into whole and decimal for the hero display
    private var heroAmountParts: (whole: String, decimal: String?) {
        let raw = amountText.isEmpty ? "0" : amountText
        if let dotIdx = raw.firstIndex(of: ".") {
            let whole = String(raw[raw.startIndex..<dotIdx])
            let dec   = String(raw[raw.index(after: dotIdx)...])
            return (whole, dec.isEmpty ? "00" : dec)
        }
        return (raw, nil)
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
                            if receiptImageAttached {
                                receiptHeroView
                            } else {
                                noReceiptAmountBlock
                            }

                            unifiedDetailCard

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
                        .padding(.top, 12)
                        .padding(.bottom, Spacing.xl)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // < Back
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                        }
                    }
                    // AUTO-SCANNED badge
                    ToolbarItem(placement: .principal) {
                        if source != .manual {
                            autoScannedBadge
                        }
                    }
                    // Done pill
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await saveEdits(expense: expense) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Done")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                canSaveEdits
                                    ? Color(hex: "2F402E")
                                    : Color(hex: "2F402E").opacity(0.4)
                            )
                            .clipShape(Capsule())
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
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .confirmationDialog(
                    "Replace receipt",
                    isPresented: $showingReplaceReceiptSources,
                    titleVisibility: .visible
                ) {
                    Button("Camera")  { showingCamera       = true }
                    Button("Photos")  { showingPhotoPicker  = true }
                    Button("File")    { showingDocumentPicker = true }
                    Button("Cancel", role: .cancel) {}
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
                .onAppear { syncFromExpense(expense) }
                .onChange(of: expense.updatedAt) { _, _ in syncFromExpense(expense) }
                .onChange(of: merchant)     { _, _ in updateTagSuggestion() }
                .onChange(of: notes)        { _, _ in updateTagSuggestion() }
                .onChange(of: selectedTagIds) { _, newVal in
                    if !newVal.isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) { tallySuggestion = nil }
                    }
                }
                .task(id: expense.updatedAt) { loadAttachment(expense) }

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

    // MARK: - AUTO-SCANNED badge

    private var autoScannedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 10, weight: .semibold))
            Text("AUTO-SCANNED")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(Color(hex: "2F402E"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "D6E8D4"))
        .clipShape(Capsule())
    }

    // MARK: - Receipt hero

    private var receiptHeroView: some View {
        ZStack {
            // Receipt image
            if let image = attachmentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                    .allowsHitTesting(false)
            } else {
                Color(hex: "2F402E").opacity(0.12)
            }

            // Gradient — bottom ~170 pt
            VStack {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear,                        location: 0),
                        .init(color: Color.black.opacity(0.78),     location: 1)
                    ],
                    startPoint: .top,
                    endPoint:   .bottom
                )
                .frame(height: 170)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .frame(height: 260)
        // Tag pill — top-left
        .overlay(alignment: .topLeading) {
            if !selectedTags.isEmpty, let tag = selectedTags.first {
                HStack(spacing: 5) {
                    Circle()
                        .fill(tag.tagColor.primaryColor)
                        .frame(width: 7, height: 7)
                    Text(
                        selectedTags.count == 1
                            ? tag.name
                            : "\(tag.name) +\(selectedTags.count - 1)"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.92))
                .clipShape(Capsule())
                .padding(12)
            }
        }
        // Date / merchant / amount — bottom-left
        .overlay(alignment: .bottomLeading) {
            let parts = heroAmountParts
            VStack(alignment: .leading, spacing: 2) {
                Text(heroDateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(1.2)

                Text(
                    merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Merchant"
                        : merchant
                )
                .font(Font.dmSerifDisplay(24))
                .foregroundStyle(.white)
                .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(currencySymbol)
                        .font(.system(size: 18, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(parts.whole)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    if let dec = parts.decimal {
                        Text(".\(dec)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .baselineOffset(8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .allowsHitTesting(false)
        }
        // VIEW RECEIPT + Replace / Remove — bottom-right
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                Button { showingFullImage = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("VIEW RECEIPT")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.2))
                    .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Button { showingReplaceReceiptSources = true } label: {
                        Text("Replace")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .underline()
                    }
                    .buttonStyle(.plain)

                    Button {
                        attachmentImage  = nil
                        attachedFileURL  = nil
                        attachmentKey    = nil
                        source           = .manual
                    } label: {
                        Text("Remove")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Amount hero (no receipt)

    private var noReceiptAmountBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AMOUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "2F402E").opacity(0.7))
                .tracking(0.8)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { showingCurrencyPicker = true } label: {
                    Text(currencySymbol)
                        .font(.system(size: 28, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                }
                .buttonStyle(.plain)

                NumericFieldWithDone(
                    text: $amountText,
                    keyboardType: CurrencyFormatter.shared.usesDecimals(for: currency)
                        ? .decimalPad : .numberPad,
                    font: UIFont.monospacedSystemFont(ofSize: 52, weight: .regular),
                    focusRequested: focusedField == .amount,
                    onDone: { focusedField = nil }
                )
                .frame(minHeight: 56)
                .onChange(of: amountText) { _, newValue in
                    let filtered  = newValue.filter { $0.isNumber || $0 == "." }
                    let parts     = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                    let sanitized = parts.count > 1
                        ? parts[0] + "." + parts.dropFirst().joined()
                        : filtered
                    if sanitized != newValue { amountText = String(sanitized) }
                }
                .onChange(of: focusedField) { _, newValue in
                    if newValue != .amount { formatAmountField() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color(hex: "2F402E").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .amount }
    }

    // MARK: - Unified detail card

    private var unifiedDetailCard: some View {
        VStack(spacing: 0) {
            // AMOUNT — editable row, receipt state only (non-receipt state uses the hero block above)
            if receiptImageAttached {
                amountDetailRow
                Divider().padding(.leading, 52)
            }

            merchantDetailRow
            Divider().padding(.leading, 52)
            dateDetailRow
            Divider().padding(.leading, 52)
            noteDetailRow      // NOTE above TAG per design spec
            Divider().padding(.leading, 52)
            tagDetailRow
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Detail rows

    private var amountDetailRow: some View {
        HStack(spacing: 12) {
            rowIcon("dollarsign")

            Text("AMOUNT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.8)

            Spacer()

            HStack(spacing: 3) {
                Button { showingCurrencyPicker = true } label: {
                    Text(currencySymbol)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                }
                .buttonStyle(.plain)

                TextField("0.00", text: $amountText)
                    .keyboardType(
                        CurrencyFormatter.shared.usesDecimals(for: currency)
                            ? .decimalPad : .numberPad
                    )
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let filtered  = newValue.filter { $0.isNumber || $0 == "." }
                        let parts     = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                        let sanitized = parts.count > 1
                            ? parts[0] + "." + parts.dropFirst().joined()
                            : filtered
                        if sanitized != newValue { amountText = String(sanitized) }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        if newValue != .amount { formatAmountField() }
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .amount }
    }

    private var merchantDetailRow: some View {
        HStack(spacing: 12) {
            rowIcon("bag.fill")

            Text("MERCHANT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.8)

            Spacer()

            TextField("Add merchant", text: $merchant)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .merchant)
                .textInputAutocapitalization(.words)
                .frame(maxWidth: 160)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var dateDetailRow: some View {
        Button { showingDatePickerSheet = true } label: {
            HStack(spacing: 12) {
                rowIcon("calendar")

                Text("DATE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.8)

                Spacer()

                Text(Self.datePillFormatter.string(from: date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noteDetailRow: some View {
        HStack(alignment: .top, spacing: 12) {
            rowIcon("doc.text")
                .padding(.top, 1)

            Text("NOTE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "8F9E94"))
                .tracking(0.8)
                .padding(.top, 4)

            Spacer()

            TextField("Add a note...", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .notes)
                .lineLimit(1...4)
                .frame(maxWidth: 190)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var tagDetailRow: some View {
        Button { showingTagPicker = true } label: {
            HStack(spacing: 12) {
                rowIcon("tag.fill")

                Text("TAG")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.8)

                Spacer()

                if selectedTags.isEmpty {
                    Text("Add tag...")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                } else {
                    HStack(spacing: 6) {
                        ForEach(selectedTags.prefix(2)) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(tag.tagColor.primaryColor)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "2F402E"))
                            }
                        }
                        if selectedTags.count > 2 {
                            Text("+\(selectedTags.count - 2)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Light green circle with dark green icon — shared by all detail rows
    private func rowIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "E8F0EA"))
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "2F402E"))
        }
    }

    // MARK: - Tally Suggests

    @ViewBuilder
    private var tallySuggestsCard: some View {
        if let suggestion = tallySuggestion,
           !tallySuggestionDismissed,
           selectedTagIds.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E"))
                    Text("TALLY SUGGESTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "2F402E"))
                        .tracking(0.8)
                }

                Text("Looks like a \(suggestion.reason) — want to tag this as **\(suggestion.tag.name)**?")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "2F402E").opacity(0.9))

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagIds = [suggestion.tag.id]
                            tallySuggestion = nil
                        }
                    } label: {
                        Text("Apply tag")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 18)
                            .background(Color(hex: "2F402E"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tallySuggestionDismissed = true
                        }
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "2F402E"))
                            .padding(.vertical, 9)
                            .padding(.horizontal, 18)
                            .background(Color(hex: "2F402E").opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "EAF5EC"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "2F402E").opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
            HStack {
                Image(systemName: "trash")
                Text("Delete expense")
            }
            .font(Fonts.body(15))
            .foregroundStyle(Color.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
        .padding(.horizontal, 16)
        .padding(.top, Spacing.md)
    }

    // MARK: - Helpers

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
        } catch {
            #if DEBUG
            print("[Tally] ERROR deleting expense: \(error)")
            #endif
        }
        if let key = expense.attachmentKey {
            Task { await AttachmentService.shared.deleteAttachment(key: key) }
        }
        dismiss()
    }

    private func loadAttachment(_ expense: ExpenseModel) {
        if let key = expense.attachmentKey,
           let image = AttachmentService.shared.loadImage(key: key) {
            attachmentImage = image
            return
        }
        if let data = expense.attachmentData, let image = UIImage(data: data) {
            attachmentImage = image
            return
        }
        attachmentImage = nil
    }

    private func updateTagSuggestion() {
        guard selectedTagIds.isEmpty, !tallySuggestionDismissed else { return }
        let suggestion = TagSuggestionEngine.suggest(
            merchant: merchant,
            notes:    notes,
            tags:     Array(tags)
        )
        guard suggestion?.tag.id != tallySuggestion?.tag.id else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tallySuggestion = suggestion
        }
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
            #if DEBUG
            print("[Tally] ERROR saving expense: \(error)")
            #endif
        }
        isSaving = false
        dismiss()
    }
}

// MARK: - Full Image View

struct FullImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
            .padding(Spacing.lg)
        }
    }
}
