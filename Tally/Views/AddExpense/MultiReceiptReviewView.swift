import SwiftUI
import SwiftData

// MARK: - Draft model

struct ReceiptDraft: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
    var isProcessing: Bool = true
    var amountText: String = ""
    var amountCents: Int? = nil
    var merchant: String = ""
    var date: Date = Date()
    var notes: String = ""
    var selectedTagIds: [String] = []
    var isChecked: Bool = true
}

// MARK: - Focus field identifier

private enum DraftField: Hashable {
    case amount(UUID), merchant(UUID), notes(UUID)
}

// MARK: - Review view

struct MultiReceiptReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    let images: [UIImage]
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var drafts: [ReceiptDraft]
    @State private var expandedIds: Set<UUID> = []
    @State private var showingTagPicker = false
    @State private var tagPickerDraftId: UUID? = nil
    @State private var showingDatePicker = false
    @State private var datePickerDraftId: UUID? = nil
    @State private var isSaving = false
    @State private var showingAmountAlert = false
    @State private var fullscreenImageDraft: ReceiptDraft? = nil
    @FocusState private var focusedField: DraftField?

    init(images: [UIImage], onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.images   = images
        self.onCancel = onCancel
        self.onDone   = onDone
        _drafts = State(initialValue: images.map { ReceiptDraft(image: $0) })
    }

    private var checkedCount: Int { drafts.filter(\.isChecked).count }
    private var currencyCode: String { appState.defaultCurrency }
    private var currencySymbol: String { CurrencyFormatter.shared.symbol(for: currencyCode) }
    private var usesDecimals: Bool { CurrencyFormatter.shared.usesDecimals(for: currencyCode) }

    // MARK: - Body
    // No NavigationStack — iOS 26 beta proposes zero height to scroll content.
    // ZStack layout: ScrollView fills the entire frame (no VStack height distribution),
    // navBar overlays on top. UIHostingController must have sizingOptions = [] so
    // UIKit (not intrinsic content size) determines the frame.

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "F0EDE6").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(drafts.indices, id: \.self) { idx in
                        accordionCard(idx: idx)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .padding(.top, 53) // navBar (52) + Divider (1)

            VStack(spacing: 0) {
                navBar
                Divider()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .foregroundStyle(Color(hex: "2F402E"))
            }
        }
        .alert("Missing amounts", isPresented: $showingAmountAlert) {
            Button("OK") {}
        } message: {
            Text("All selected receipts need an amount. Fill in or uncheck any that are missing.")
        }
        .task { await runAllOCR() }
        .sheet(isPresented: $showingTagPicker) {
            if let id = tagPickerDraftId,
               let idx = drafts.firstIndex(where: { $0.id == id }) {
                SharedTagPickerSheet(selectedTagIds: $drafts[idx].selectedTagIds)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            if let id = datePickerDraftId,
               let idx = drafts.firstIndex(where: { $0.id == id }) {
                NavigationStack {
                    DatePicker("", selection: $drafts[idx].date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingDatePicker = false }
                                    .foregroundStyle(Color(hex: "2F402E"))
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(item: $fullscreenImageDraft) { draft in
            ReceiptImageFullscreenView(image: draft.image) {
                fullscreenImageDraft = nil
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Custom nav bar

    private var navBar: some View {
        ZStack {
            Text("Review receipts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            HStack {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "EEEDEB"))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 52)
        .background(Color(hex: "F0EDE6"))
    }

    // MARK: - Accordion card

    private func accordionCard(idx: Int) -> some View {
        let d = drafts[idx]
        let isExpanded = expandedIds.contains(d.id)

        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Button {
                    drafts[idx].isChecked.toggle()
                } label: {
                    Image(systemName: drafts[idx].isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(drafts[idx].isChecked ? Color(hex: "346049") : Color(hex: "C4BFB9"))
                }
                .buttonStyle(.plain)

                Image(uiImage: d.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
                    )
                    .onTapGesture { fullscreenImageDraft = d }

                VStack(alignment: .leading, spacing: 4) {
                    if d.isProcessing {
                        OCRProgressBar()
                    } else {
                        Text(amountDisplay(d))
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(d.amountText.isEmpty ? Color(hex: "C4BFB9") : Color(hex: "1C1C1E"))
                        HStack(spacing: 4) {
                            if !d.merchant.isEmpty {
                                Text(d.merchant)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                                    .lineLimit(1)
                                Text("·").font(.system(size: 13)).foregroundStyle(Color(hex: "C4BFB9"))
                            }
                            Text(Self.dateFmt.string(from: d.date))
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                    }
                }

                Spacer(minLength: 0)

                if !d.isProcessing {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !d.isProcessing else { return }
                focusedField = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded { expandedIds.remove(d.id) }
                    else          { expandedIds.insert(d.id) }
                }
            }

            if isExpanded {
                Color(hex: "F0EFE9").frame(height: 1).padding(.horizontal, 14)
                expandedFields(idx: idx)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isExpanded ? Color(hex: "346049").opacity(0.3) : Color(hex: "DEDAD2"),
                    lineWidth: isExpanded ? 1.5 : 1
                )
        )
        .opacity(d.isChecked ? 1 : 0.5)
    }

    // MARK: - Expanded fields

    private func expandedFields(idx: Int) -> some View {
        let d = drafts[idx]
        let draftId = d.id
        let selectedTags = d.selectedTagIds.compactMap { id in tags.first { $0.id == id } }

        return VStack(alignment: .leading, spacing: 0) {
            // Amount
            fieldRow(label: "Amount") {
                HStack(spacing: 4) {
                    Text(currencySymbol)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "2F402E").opacity(0.45))
                    TextField(usesDecimals ? "0.00" : "0", text: $drafts[idx].amountText)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                        .keyboardType(usesDecimals ? .decimalPad : .numberPad)
                        .focused($focusedField, equals: .amount(draftId))
                        .onChange(of: drafts[idx].amountText) { _, new in
                            let clean = sanitizeAmount(new)
                            if clean != new { drafts[idx].amountText = clean }
                            drafts[idx].amountCents = parseCents(clean)
                        }
                }
            }

            rowDivider

            // Merchant
            fieldRow(label: "Merchant") {
                TextField("Where did you pay?", text: $drafts[idx].merchant)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .merchant(draftId))
            }

            rowDivider

            // Date
            fieldRow(label: "Date") {
                HStack {
                    Text(Self.dateFmt.string(from: d.date))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Spacer()
                    Button("Change") {
                        focusedField = nil
                        datePickerDraftId = draftId
                        showingDatePicker = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "346049"))
                    .buttonStyle(.plain)
                }
            }

            rowDivider

            // Tags
            fieldRow(label: "Tags") {
                if selectedTags.isEmpty {
                    Button {
                        focusedField = nil
                        tagPickerDraftId = draftId
                        showingTagPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tag.fill").font(.system(size: 11))
                            Text("Add tag").font(.system(size: 14))
                        }
                        .foregroundStyle(Color(hex: "8F9E94"))
                    }
                    .buttonStyle(.plain)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedTags) { tag in
                                tagChip(tag: tag) {
                                    drafts[idx].selectedTagIds.removeAll { $0 == tag.id }
                                }
                            }
                            Button {
                                focusedField = nil
                                tagPickerDraftId = draftId
                                showingTagPicker = true
                            } label: {
                                Text("+ Add")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                                    .padding(.vertical, 5).padding(.horizontal, 9)
                                    .overlay(
                                        Capsule().stroke(Color(hex: "DEDAD2"),
                                                         style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            rowDivider

            // Notes
            fieldRow(label: "Notes") {
                TextField("Add a note…", text: $drafts[idx].notes, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .notes(draftId))
            }
        }
        .padding(.top, 4)
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "8F9E94"))
            content()
        }
        .padding(.vertical, 10)
    }

    private var rowDivider: some View {
        Color(hex: "F0EFE9").frame(height: 1)
    }

    private func tagChip(tag: TagModel, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tag.tagColor.primaryColor).frame(width: 7, height: 7)
            Text(tag.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "2F402E"))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "2F402E").opacity(0.6))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 5).padding(.leading, 9).padding(.trailing, 7)
        .background(Color(hex: "E8F0EA"))
        .clipShape(Capsule())
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Color(hex: "F0EDE6")], startPoint: .top, endPoint: .bottom)
                .frame(height: 36).allowsHitTesting(false)
            Button { addExpenses() } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(checkedCount == 0
                             ? "No receipts selected"
                             : "Add \(checkedCount) expense\(checkedCount == 1 ? "" : "s")")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "2F402E").opacity(checkedCount > 0 ? 1 : 0.4))
                )
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(checkedCount == 0 || isSaving)
            .padding(.bottom, 34)
        }
        .background(Color(hex: "F0EDE6"))
    }

    // MARK: - Helpers

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private func amountDisplay(_ draft: ReceiptDraft) -> String {
        let t = draft.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let val = Double(t), val > 0 else { return "Set amount" }
        return usesDecimals
            ? "\(currencySymbol)\(String(format: "%.2f", val))"
            : "\(currencySymbol)\(String(format: "%.0f", val))"
    }

    private func sanitizeAmount(_ input: String) -> String {
        guard usesDecimals else { return input.filter(\.isNumber) }
        let filtered = input.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count > 1 ? "\(parts[0]).\(parts.dropFirst().joined())" : String(filtered)
    }

    private func parseCents(_ text: String) -> Int? {
        guard let val = Double(text), val > 0 else { return nil }
        return usesDecimals ? Int(round(val * 100)) : Int(round(val))
    }

    // MARK: - OCR

    private func runAllOCR() async {
        for i in drafts.indices {
            let image   = drafts[i].image
            let draftId = drafts[i].id
            let isPro   = appState.isPro
            Task {
                let result = await ReceiptOCRService.extract(from: image)
                await MainActor.run {
                    guard let idx = drafts.firstIndex(where: { $0.id == draftId }) else { return }
                    drafts[idx].isProcessing = false
                    if let amount = result.amount {
                        drafts[idx].amountCents = Int(round(amount * 100))
                        drafts[idx].amountText  = usesDecimals
                            ? String(format: "%.2f", amount)
                            : String(format: "%.0f", amount)
                    }
                    if let d = result.date { drafts[idx].date = d }
                    if isPro {
                        if let name = result.merchant { drafts[idx].merchant = name }
                        if let n    = result.notes    { drafts[idx].notes    = n }
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func addExpenses() {
        let checked = drafts.filter(\.isChecked)
        let missingAmount = checked.filter {
            guard let val = Double($0.amountText.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return true }
            return val <= 0
        }
        guard missingAmount.isEmpty else { showingAmountAlert = true; return }

        isSaving = true
        Task {
            for draft in checked {
                let t = draft.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let val = Double(t), val > 0 else { continue }
                let cents     = usesDecimals ? Int(round(val * 100)) : Int(round(val))
                let expenseId = UUID().uuidString
                var savedKey: String? = nil
                var rawData:  Data?   = nil
                do {
                    savedKey = try await AttachmentService.shared.saveImage(draft.image, id: expenseId)
                    rawData  = draft.image.jpegData(compressionQuality: 0.8)
                } catch {}

                await MainActor.run {
                    let expense = ExpenseModel(
                        id: expenseId,
                        userId: "",
                        amountCents: cents,
                        currency: currencyCode,
                        date: draft.date,
                        description: nil,
                        merchant: draft.merchant.isEmpty ? nil : draft.merchant,
                        tagIds: draft.selectedTagIds,
                        notes: draft.notes.isEmpty ? nil : draft.notes,
                        attachmentKey: savedKey,
                        attachmentData: rawData,
                        source: ExpenseSource.upload.rawValue
                    )
                    modelContext.insert(expense)
                }
            }

            await MainActor.run {
                try? modelContext.save()
                appState.totalExpenseCount += checked.count
                appState.clearFilters()
                isSaving = false
                onDone()
            }
        }
    }
}

// MARK: - OCR Progress Bar

private struct OCRProgressBar: View {
    @State private var progress: CGFloat = 0.05

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scanning…")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "8F9E94"))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "EEEDEB"))
                    Capsule()
                        .fill(Color(hex: "346049"))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 3.0)) {
                progress = 0.82
            }
        }
    }
}

// MARK: - Receipt Image Fullscreen View

private struct ReceiptImageFullscreenView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.white.opacity(0.3))
                    .padding(16)
            }
        }
    }
}
