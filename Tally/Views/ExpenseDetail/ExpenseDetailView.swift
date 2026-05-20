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
    @State private var isEditingMode = false
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

    private var navigationTitleText: String {
        let m = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "Expense" : m
    }

    private static let datePillFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            if let expense {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 8) {
                            if receiptImageAttached {
                                receiptImageHero
                                detailAmountMerchantDateCluster
                            } else {
                                detailAmountHeroBlock
                                detailMerchantDateCluster
                                if attachedFileURL != nil {
                                    detailPdfCard
                                }
                                detailTagsSection
                                detailNotesSection
                            }

                            if receiptImageAttached {
                                detailTagsSection
                                detailNotesSection
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
                    ToolbarItem(placement: .principal) {
                        Text(navigationTitleText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if isEditingMode {
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .foregroundStyle(Color.textSecondary)
                        } else {
                            Button("Edit") {
                                beginEditing(from: expense)
                            }
                            .foregroundStyle(Color(hex: "2F402E"))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            if isEditingMode {
                                Task { await saveEdits(expense: expense) }
                            } else {
                                dismiss()
                            }
                        }
                        .foregroundStyle(Color(hex: "2F402E"))
                        .disabled(isEditingMode && !canSaveEdits)
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
                .confirmationDialog("Replace receipt", isPresented: $showingReplaceReceiptSources, titleVisibility: .visible) {
                    Button("Camera") { showingCamera = true }
                    Button("Photos") { showingPhotoPicker = true }
                    Button("File") { showingDocumentPicker = true }
                    Button("Cancel", role: .cancel) {}
                }
                .fullScreenCover(isPresented: $showingCamera) {
                    CameraPicker(image: $attachmentImage)
                        .ignoresSafeArea()
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
                }
                .onChange(of: expense.updatedAt) { _, _ in
                    if !isEditingMode {
                        syncFromExpense(expense)
                    }
                }
                .task(id: expense.updatedAt) { await loadAttachment(expense) }
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

    private var receiptImageHero: some View {
        ZStack {
            if let image = attachmentImage {
                Button { showingFullImage = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
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
                    .frame(height: 260 / 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 260)
        .overlay(alignment: .bottomTrailing) {
            if attachmentImage != nil, isEditingMode {
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
                        attachmentImage = nil
                        attachedFileURL = nil
                        attachmentKey = nil
                        source = .manual
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

    // MARK: - Amount + cluster (receipt path)

    private var detailAmountMerchantDateCluster: some View {
        VStack(spacing: 2) {
            detailReceiptAmountRow
            detailMerchantRow(clip: (4, 4, 4, 4))
            detailDateRow
        }
    }

    private var detailReceiptAmountRow: some View {
        Group {
            if isEditingMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AMOUNT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.7))
                        .tracking(0.8)
                        .textCase(.uppercase)

                    HStack(spacing: 6) {
                        Button { showingCurrencyPicker = true } label: {
                            Text(currencySymbol)
                                .font(.system(size: 20, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "2F402E").opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        NumericFieldWithDone(
                            text: $amountText,
                            keyboardType: CurrencyFormatter.shared.usesDecimals(for: currency) ? .decimalPad : .numberPad,
                            font: UIFont.monospacedSystemFont(ofSize: 36, weight: .regular),
                            focusRequested: focusedField == .amount,
                            onDone: { focusedField = nil }
                        )
                        .frame(minHeight: 44)
                        .onChange(of: amountText) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber || $0 == "." }
                            let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "2F402E").opacity(0.06))
                .clipShape(unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4))
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .amount }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AMOUNT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.7))
                        .tracking(0.8)
                        .textCase(.uppercase)

                    Text(CurrencyFormatter.shared.format(cents: expense?.amountCents ?? 0, currencyCode: currency))
                        .font(.system(size: 36, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "2F402E").opacity(0.06))
                .clipShape(unevenRect(topLeading: 14, topTrailing: 14, bottomLeading: 4, bottomTrailing: 4))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Amount hero (no receipt image)

    private var detailAmountHeroBlock: some View {
        Group {
            if isEditingMode {
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
                            keyboardType: CurrencyFormatter.shared.usesDecimals(for: currency) ? .decimalPad : .numberPad,
                            font: UIFont.monospacedSystemFont(ofSize: 52, weight: .regular),
                            focusRequested: focusedField == .amount,
                            onDone: { focusedField = nil }
                        )
                        .frame(minHeight: 56)
                        .onChange(of: amountText) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber || $0 == "." }
                            let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                            let sanitized = parts.count > 1
                                ? parts[0] + "." + parts.dropFirst().joined()
                                : filtered
                            if sanitized != newValue { amountText = String(sanitized) }
                        }
                        .onChange(of: focusedField) { _, newValue in
                            if newValue != .amount { formatAmountField() }
                        }
                    }

                    Text("Tap to enter amount")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .background(Color(hex: "2F402E").opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .amount }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AMOUNT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.7))
                        .tracking(0.8)
                        .textCase(.uppercase)

                    Text(CurrencyFormatter.shared.format(cents: expense?.amountCents ?? 0, currencyCode: currency))
                        .font(.system(size: 52, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .tracking(-2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .background(Color(hex: "2F402E").opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Merchant + date

    private var detailMerchantDateCluster: some View {
        VStack(spacing: 2) {
            detailMerchantRow(clip: (14, 14, 4, 4))
            detailDateRow
        }
    }

    private func detailMerchantRow(clip: (CGFloat, CGFloat, CGFloat, CGFloat)) -> some View {
        let tl = clip.0
        let tr = clip.1
        let bl = clip.2
        let br = clip.3
        return Group {
            if isEditingMode {
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
                .clipShape(unevenRect(topLeading: tl, topTrailing: tr, bottomLeading: bl, bottomTrailing: br))
                .padding(.horizontal, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MERCHANT")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .tracking(0.6)
                        .textCase(.uppercase)

                    Text(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No merchant" : merchant)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(hex: "C4BFB9") : Color(hex: "1C1C1E"))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(unevenRect(topLeading: tl, topTrailing: tr, bottomLeading: bl, bottomTrailing: br))
                .padding(.horizontal, 16)
            }
        }
    }

    private var detailDateRow: some View {
        Group {
            if isEditingMode {
                Button {
                    showingDatePickerSheet = true
                } label: {
                    dateRowInner
                }
                .buttonStyle(.plain)
                .background(Color.white)
                .clipShape(unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 14, bottomTrailing: 14))
                .padding(.horizontal, 16)
            } else {
                dateRowInner
                    .background(Color.white)
                    .clipShape(unevenRect(topLeading: 4, topTrailing: 4, bottomLeading: 14, bottomTrailing: 14))
                    .padding(.horizontal, 16)
            }
        }
    }

    private var dateRowInner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE OF TRANSACTION")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "8F9E94"))
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Text(Calendar.current.isDateInToday(date) ? "Today" : Self.shortDateString(date))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "2F402E"))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color(hex: "E8F0EA"))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(Self.datePillFormatter.string(from: date))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: "1C1C1E"))

                Spacer(minLength: 0)

                if isEditingMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static func shortDateString(_ d: Date) -> String {
        shortDateFormatter.string(from: d)
    }

    // MARK: - PDF card

    private var detailPdfCard: some View {
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
                    if isEditingMode {
                        Button("Remove") {
                            attachedFileURL = nil
                            attachmentImage = nil
                            attachmentKey = nil
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "2F402E"))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Tags

    private var detailTagsSection: some View {
        Group {
            if selectedTagIds.isEmpty {
                Group {
                    if isEditingMode {
                        Button {
                            showingTagPicker = true
                        } label: {
                            tagsPlaceholderLabel
                        }
                        .buttonStyle(.plain)
                    } else {
                        tagsPlaceholderLabel
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Group {
                    if isEditingMode {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedTags) { tag in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(tag.tagColor.primaryColor)
                                            .frame(width: 8, height: 8)
                                        Text(tag.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color(hex: "2F402E"))
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
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
                                            .foregroundStyle(Color(hex: "2F402E"))
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color(hex: "E8F0EA"))
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color(hex: "2F402E"), lineWidth: 1.5)
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private var tagsPlaceholderLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8F9E94"))
            Text("No tags")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "C4BFB9"))
            Spacer(minLength: 0)
            if isEditingMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Notes

    private var detailNotesSection: some View {
        Group {
            if isEditingMode {
                VStack(alignment: .leading, spacing: 0) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            } else if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "8F9E94"))
                    Text("No notes")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                Text(notes)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
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

    private func unevenRect(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing,
            style: .continuous
        )
    }

    private func syncFromExpense(_ expense: ExpenseModel) {
        currency = expense.currency
        let usesDecimals = CurrencyFormatter.shared.usesDecimals(for: expense.currency)
        if usesDecimals {
            amountText = String(format: "%.2f", Double(expense.amountCents) / 100.0)
        } else {
            amountText = String(format: "%.0f", Double(expense.amountCents))
        }
        date = expense.date
        merchant = expense.merchant ?? ""
        notes = expense.notes ?? ""
        selectedTagIds = expense.resolvedTagIds
        source = ExpenseSource(rawValue: expense.source) ?? .manual
        attachmentKey = expense.attachmentKey
    }

    private func beginEditing(from expense: ExpenseModel) {
        syncFromExpense(expense)
        isEditingMode = true
    }

    private func cancelEditing() {
        if let e = expense {
            syncFromExpense(e)
        }
        isEditingMode = false
        focusedField = nil
    }

    private func deleteExpense(_ expense: ExpenseModel) {
        expense.deletedAt = Date()
        expense.updatedAt = Date()
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

    private func loadAttachment(_ expense: ExpenseModel) async {
        if let key = expense.attachmentKey,
           let image = await AttachmentService.shared.loadImage(key: key) {
            attachmentImage = image
            return
        }

        if let data = expense.attachmentData, let image = UIImage(data: data) {
            attachmentImage = image
            return
        }

        attachmentImage = nil
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

        var savedKey: String? = expense.attachmentKey
        var rawAttachmentData: Data? = expense.attachmentData

        if let image = attachmentImage {
            do {
                savedKey = try await AttachmentService.shared.saveImage(image, id: expenseId)
                rawAttachmentData = image.jpegData(compressionQuality: 0.8)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving = false
                return
            }
        } else if let url = attachedFileURL {
            do {
                savedKey = try await AttachmentService.shared.saveFile(from: url, id: expenseId)
                rawAttachmentData = try? Data(contentsOf: url)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving = false
                return
            }
        } else if let oldKey = expense.attachmentKey, attachmentKey == nil {
            await AttachmentService.shared.deleteAttachment(key: oldKey)
            savedKey = nil
            rawAttachmentData = nil
        } else {
            savedKey = expense.attachmentKey
            rawAttachmentData = expense.attachmentData
        }

        expense.amountCents = amountCents
        expense.currency = currency
        expense.date = date
        expense.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : merchant
        expense.tagIds = selectedTagIds
        expense.tagId = selectedTagIds.first ?? ""
        expense.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        expense.attachmentKey = savedKey
        expense.attachmentData = rawAttachmentData
        expense.source = source.rawValue
        expense.updatedAt = Date()

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
