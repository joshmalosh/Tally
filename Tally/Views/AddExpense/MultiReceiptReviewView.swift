import SwiftUI
import OSLog
import SwiftData

// MARK: - Draft model

struct ReceiptDraft: Identifiable {
    let id: UUID = UUID()
    /// nil for image-less sources (e.g. a PDF statement line) — the row then shows
    /// the green PDF tile instead of a photo thumbnail.
    var image: UIImage? = nil
    var isProcessing: Bool = true
    var amountText: String = ""
    var amountCents: Int? = nil
    var merchant: String = ""
    var date: Date = Date()
    var notes: String = ""
    var selectedTagIds: [String] = []
    var isChecked: Bool = true
    /// OCR's lower-ranked merchant guesses, for the per-row "Doesn't look right?"
    /// picker — same affordance as the single Add-expense page.
    var merchantAlternates: [String] = []
    var showAlternates: Bool = false
    var wasAutoScanned: Bool = false
    /// Currency the scan detected for this receipt; falls back to the default.
    var currencyCode: String? = nil
}

// MARK: - Review config
//
// The one thing that makes this view reusable across sources (photo receipts,
// PDF statements). Everything else — the accordion, edit fields, removal, save
// loop — is shared, so a design change here updates every flow at once. Add a new
// source by passing a config, never by copying this screen.

struct ReviewConfig {
    var navTitle: String
    /// Run per-row OCR on appearance (photos). Statement drafts arrive parsed.
    var runsOCR: Bool
    /// Save each row's image as an attachment. Off for statements (never store the PDF).
    var savesAttachment: Bool
    /// Charge the free-tier scan quota per added row, and show the over-limit UI.
    /// Off for statements (Pro-only, unlimited).
    var chargesScan: Bool
    /// `ExpenseModel.source` written for saved rows.
    var expenseSource: String
    /// Noun for the "N <noun>s found" summary banner at the top of the list.
    var foundNoun: String

    static let photos = ReviewConfig(
        navTitle: "Review receipts", runsOCR: true, savesAttachment: true,
        chargesScan: true, expenseSource: ExpenseSource.upload.rawValue,
        foundNoun: "receipt"
    )
    static let statement = ReviewConfig(
        navTitle: "Review expenses", runsOCR: false, savesAttachment: false,
        chargesScan: false, expenseSource: "statement_import", foundNoun: "expense"
    )
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

    let config: ReviewConfig
    let onCancel: () -> Void
    let onDone: () -> Void
    /// How many were found up front — the summary banner stays accurate even after
    /// rows are deleted.
    let foundCount: Int

    @State private var drafts: [ReceiptDraft]
    // Only one row open at a time — opening another closes the current one.
    @State private var expandedId: UUID? = nil
    @State private var showingTagPicker = false
    @State private var tagPickerDraftId: UUID? = nil
    @State private var showingDatePicker = false
    @State private var datePickerDraftId: UUID? = nil
    @State private var isSaving = false
    @State private var showingAmountAlert = false
    @State private var showingScanLimit = false
    @State private var fullscreenImageDraft: ReceiptDraft? = nil
    // Per-row swipe reveal for the trailing Delete affordance (id → x offset).
    @State private var swipeOffset: [UUID: CGFloat] = [:]
    @FocusState private var focusedField: DraftField?

    /// Photo receipts — one draft per image, OCR runs, attachments saved, scans charged.
    init(images: [UIImage], onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.config     = .photos
        self.onCancel   = onCancel
        self.onDone     = onDone
        self.foundCount = images.count
        _drafts = State(initialValue: images.map { ReceiptDraft(image: $0) })
    }

    /// Pre-built drafts from another source (e.g. a parsed PDF statement) with an
    /// explicit config. Same screen, different data.
    init(drafts: [ReceiptDraft], config: ReviewConfig,
         onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.config     = config
        self.onCancel   = onCancel
        self.onDone     = onDone
        self.foundCount = drafts.count
        _drafts = State(initialValue: drafts)
    }

    private var checkedCount: Int { drafts.filter(\.isChecked).count }
    // Free-tier scan allowance left this month (.max for Pro). A scan is charged
    // per receipt actually added, not per preview, so this stays fixed while the
    // user ticks/unticks and `overBy` tracks live. Sources that don't charge
    // (statements) are never over.
    private var remainingScans: Int { appState.ocrScansRemaining }
    private var overBy: Int {
        guard config.chargesScan else { return 0 }
        return checkedCount > remainingScans ? checkedCount - remainingScans : 0
    }
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
                    foundBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    ForEach(drafts.indices, id: \.self) { idx in
                        accordionCard(idx: idx)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 100) // clear the pinned bottom bar
            }
            .scrollDismissesKeyboard(.interactively)
            .padding(.top, 52)

            navBar
        }
        // Let the container reach the screen's bottom edge so the pinned bar sits at
        // the very bottom (behind the home indicator), not above the safe area.
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) { bottomBar }
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
            Text("Every selected expense needs an amount. Fill it in, untick it, or swipe to delete it.")
        }
        .task { if config.runsOCR { await runAllOCR() } }
        .sheet(isPresented: $showingScanLimit) {
            ScanLimitSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
            if let image = draft.image {
                ReceiptImageFullscreenView(image: image) {
                    fullscreenImageDraft = nil
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Summary banner

    private var foundBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: "2F402E"))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(foundCount) \(config.foundNoun)\(foundCount == 1 ? "" : "s") found")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("Review and add the ones you want to keep.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        // Light neutral grey bubble (matches the target), clearly distinct from the
        // warm F0EDE6 canvas without the green cast.
        .background(Color(hex: "E2E6E4"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Custom nav bar

    private var navBar: some View {
        ZStack {
            Text(config.navTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            HStack {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "2F402E"))
                Spacer()
                Button(allChecked ? "Deselect all" : "Select all") { toggleSelectAll() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .background(Color(hex: "F0EDE6"))
    }

    private var allChecked: Bool { !drafts.isEmpty && drafts.allSatisfy(\.isChecked) }

    private func toggleSelectAll() {
        let newValue = !allChecked
        for i in drafts.indices { drafts[i].isChecked = newValue }
    }

    // MARK: - Accordion card

    private func accordionCard(idx: Int) -> some View {
        let d = drafts[idx]
        let isExpanded = expandedId == d.id

        return ZStack(alignment: .trailing) {
            // Red Delete only exists while the row is actually swiped, so it can't
            // bleed through an unticked (dimmed) card.
            if (swipeOffset[d.id] ?? 0) < 0 {
                deleteBackground(for: d.id)
            }

            VStack(spacing: 0) {
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

                // Photo receipts show their thumbnail; statement rows have no image
                // and stay clean — just the tick and the details.
                if let image = d.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
                        )
                        .onTapGesture { fullscreenImageDraft = d }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if d.isProcessing {
                        OCRProgressBar()
                    } else {
                        Text(amountDisplay(d))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(d.amountText.isEmpty ? Color(hex: "C4BFB9") : Color(hex: "1C1C1E"))
                        if !d.merchant.isEmpty {
                            Text(d.merchant)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                // Date pinned right, chevron far right — a balanced two-column row
                // that fills the width instead of leaving the right side empty.
                if !d.isProcessing {
                    Text(Self.dateFmt.string(from: d.date))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8E8E93"))
                        .fixedSize()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "C4BFB9"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !d.isProcessing else { return }
                focusedField = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedId = isExpanded ? nil : d.id
                }
            }

            if isExpanded {
                Color(hex: "F0EFE9").frame(height: 1).padding(.horizontal, 14)
                expandedFields(idx: idx)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        // Dim only the content when unticked; the card stays solid white so the
        // red Delete behind can never show through.
        .opacity(d.isChecked ? 1 : 0.45)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isExpanded ? Color(hex: "346049").opacity(0.3) : Color(hex: "DEDAD2"),
                    lineWidth: isExpanded ? 1.5 : 1
                )
        )
        .offset(x: swipeOffset[d.id] ?? 0)
        .simultaneousGesture(swipeGesture(for: d.id))
        }
    }

    // Trailing red Delete, revealed by swiping the card left. Tap to remove.
    private func deleteBackground(for id: UUID) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "C0392B"))
            .overlay(alignment: .trailing) {
                Button { removeDraft(id: id) } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
    }

    // Horizontal-dominant left swipe reveals Delete; snaps open past ~40pt.
    private func swipeGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeOffset[id] = max(-76, min(0, value.translation.width))
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.2)) {
                    swipeOffset[id] = (value.translation.width < -40) ? -76 : 0
                }
            }
    }

    private func removeDraft(id: UUID) {
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            drafts.removeAll { $0.id == id }
            if expandedId == id { expandedId = nil }
        }
        swipeOffset[id] = nil
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
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Where did you pay?", text: $drafts[idx].merchant)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .merchant(draftId))
                    if !d.merchantAlternates.isEmpty {
                        merchantAlternatesRow(idx: idx)
                            .padding(.top, 8)
                    }
                }
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
            fieldRow(label: "Tag") {
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
                                Text("Change")
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

    /// The per-row "Doesn't look right?" affordance — mirrors the single Add-
    /// expense page: a chip that expands to the OCR's other merchant guesses.
    @ViewBuilder
    private func merchantAlternatesRow(idx: Int) -> some View {
        if drafts[idx].showAlternates {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(drafts[idx].merchantAlternates.prefix(5), id: \.self) { name in
                        Button {
                            drafts[idx].merchant = name
                            drafts[idx].showAlternates = false
                        } label: {
                            Text(name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "2F402E"))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color(hex: "F0EDE6"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Button {
                drafts[idx].showAlternates = true
            } label: {
                Text("Doesn't look right?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// "Group · Child" for a group's sub-tag, plain name otherwise.
    private func chipTitle(for tag: TagModel) -> String {
        if let parentId = tag.parentId, let parent = tags.first(where: { $0.id == parentId }) {
            return "\(parent.name) · \(tag.name)"
        }
        return tag.name
    }

    private func tagChip(tag: TagModel, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            if tag.isGroup {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tag.tagColor.primaryColor)
            } else {
                Circle().fill(tag.tagColor.primaryColor).frame(width: 7, height: 7)
            }
            Text(chipTitle(for: tag)).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "2F402E"))
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
        let blocked = overBy > 0
        return VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Color(hex: "F0EDE6")], startPoint: .top, endPoint: .bottom)
                .frame(height: 20).allowsHitTesting(false)

            // Over the monthly free-scan limit: warn and say by how many, live.
            if blocked {
                Button { showingScanLimit = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(overBy) over your free monthly limit. Untick \(overBy) or go Pro.")
                            .font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color(hex: "8A3A2E"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "F6E4DF"))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }

            Button { addExpenses() } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(checkedCount == 0
                             ? "No expenses selected"
                             : "Add \(checkedCount) expense\(checkedCount == 1 ? "" : "s")")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "2F402E").opacity(checkedCount > 0 && !blocked ? 1 : 0.4))
                )
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(checkedCount == 0 || isSaving || blocked)
        }
        // Parent already reaches the screen bottom; lift the button 18pt so it
        // clears the home indicator.
        .padding(.bottom, 18)
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
        // Preview every selected receipt. The free-tier scan quota is charged per
        // receipt actually *added* (in addExpenses), never per preview, so the
        // user can untick down to their remaining allowance on this screen and
        // the `overBy` counter moves live. Pro is unlimited either way.
        // ponytail: one Task per receipt, unbounded; add a semaphore only if huge
        // batches (20+) actually strain Vision on device.
        for i in drafts.indices {
            guard let image = drafts[i].image else { continue }
            let draftId = drafts[i].id

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
                    if let name = result.merchant { drafts[idx].merchant = name }
                    if let n    = result.notes    { drafts[idx].notes    = n }
                    drafts[idx].merchantAlternates = result.merchantAlternates
                    drafts[idx].showAlternates = false
                    drafts[idx].wasAutoScanned = result.amount != nil
                    drafts[idx].currencyCode = result.currencyCode
                }
            }
        }
    }

    // MARK: - Save

    private func addExpenses() {
        // Free users can't add more than their monthly scan allowance. The button
        // is disabled while over, but guard here too so it can never slip through.
        guard overBy == 0 else { showingScanLimit = true; return }

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
                // Statements never store the source file, so their config turns
                // attachment saving off — nothing about the PDF is persisted.
                if config.savesAttachment, let image = draft.image {
                    do {
                        savedKey = try await AttachmentService.shared.saveImage(image, id: expenseId)
                        rawData  = image.jpegData(compressionQuality: 0.8)
                    } catch {
                        Log.attachments.error("multi-receipt image save failed: \(error.localizedDescription, privacy: .public)")
                    }
                }

                await MainActor.run {
                    let expense = ExpenseModel(
                        id: expenseId,
                        userId: "",
                        amountCents: cents,
                        currency: draft.currencyCode ?? currencyCode,
                        date: draft.date,
                        description: nil,
                        merchant: draft.merchant.isEmpty ? nil : draft.merchant,
                        tagIds: draft.selectedTagIds,
                        notes: draft.notes.isEmpty ? nil : draft.notes,
                        attachmentKey: savedKey,
                        attachmentData: rawData,
                        source: config.expenseSource,
                        wasAutoScanned: draft.wasAutoScanned
                    )
                    modelContext.insert(expense)
                }
            }

            await MainActor.run {
                do { try modelContext.save() }
                catch { Log.data.error("multi-receipt save failed: \(error.localizedDescription, privacy: .public)") }
                // Charge the free-tier scan quota only for receipts whose OCR
                // actually produced an amount (`wasAutoScanned` is set to
                // `result.amount != nil`). A bogus photo that yielded no amount, or
                // a receipt whose amount the user had to type in, isn't charged.
                // Sources that don't charge (statements, Pro-only) skip this.
                if config.chargesScan {
                    for draft in checked where draft.wasAutoScanned {
                        appState.recordOCRScan(extractedAmount: true)
                    }
                }
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
