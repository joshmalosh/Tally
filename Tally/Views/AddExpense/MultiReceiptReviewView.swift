import SwiftUI

// MARK: - Item wrapper (used by AddExpenseView to present this screen)

/// Wraps the selected images so they can be passed via the ZStack overlay.
struct MultiReviewItem: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

// MARK: - Draft model

struct ReceiptDraft: Identifiable {
    let id: UUID = UUID()
    let image: UIImage

    // OCR state
    var isProcessing: Bool = true
    var amountText: String = ""
    var amountCents: Int? = nil
    var merchant: String = ""
    var date: Date = Date()
    var notes: String = ""

    // Save state
    var isSaved: Bool = false
}

// MARK: - Review view

struct MultiReceiptReviewView: View {
    @Environment(AppState.self) private var appState

    let images: [UIImage]
    /// Called by Cancel — parent hides the overlay without dismissing AddExpenseView.
    let onCancel: () -> Void
    /// Called by Done — parent hides the overlay and dismisses AddExpenseView.
    let onDone: () -> Void

    @State private var drafts: [ReceiptDraft]
    @State private var editingDraft: ReceiptDraft? = nil

    /// Drafts initialised eagerly in init so receipt cards render immediately
    /// in shimmer state, with no dependency on onAppear / task timing.
    init(images: [UIImage], onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.images = images
        self.onCancel = onCancel
        self.onDone = onDone
        _drafts = State(initialValue: images.map { ReceiptDraft(image: $0) })
    }

    private var savedCount: Int  { drafts.filter(\.isSaved).count }
    private var totalCount: Int  { drafts.count }
    private var allSaved: Bool   { totalCount > 0 && savedCount == totalCount }

    // Safe-area top inset so the custom header sits below the status bar when
    // the view is shown with .ignoresSafeArea() from AddExpenseView.
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 47
    }

    // MARK: - Body
    //
    // No NavigationStack here. Having two NavigationStacks as ZStack siblings
    // in iOS 26 / SwiftUI 6 causes the inner one to receive a zero or minimal
    // height proposal, collapsing the ScrollView and floating the Done button
    // directly below the nav bar. Using a plain ZStack + custom header avoids
    // the sizing conflict entirely.

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background fills the entire screen including safe areas.
            Color(hex: "F6F5F3").ignoresSafeArea()

            // Content column: status-bar spacer → header → scroll list.
            VStack(spacing: 0) {
                // Push header below the status bar.
                Color(hex: "F6F5F3").frame(height: topInset)

                // Custom navigation-bar replacement.
                ZStack {
                    Text("Review receipts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    HStack {
                        Button("Cancel") { onCancel() }
                            .font(.system(size: 17))
                            .foregroundStyle(Color(hex: "8F9E94"))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 44)
                .background(Color(hex: "F6F5F3"))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(hex: "DEDAD2"))
                        .frame(height: 0.5)
                }

                // Receipt list — ScrollView expands to fill remaining height.
                ScrollView {
                    VStack(spacing: 10) {
                        progressCard
                            .padding(.top, 4)

                        ForEach(drafts) { draft in
                            DraftReceiptCard(draft: draft) {
                                editingDraft = draft
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
            // Force VStack to fill the full ZStack frame so the ScrollView
            // actually expands rather than collapsing to content size.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Sticky Done button pinned to the bottom of the ZStack.
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await runAllOCR() }
        .sheet(item: $editingDraft) { draft in
            AddExpenseView(
                initialImage: draft.image,
                batchPrefill: BatchDraftPrefill(
                    amountText: draft.amountText,
                    merchant: draft.merchant,
                    date: draft.date,
                    notes: draft.notes
                ),
                onSaved: {
                    markSaved(draftId: draft.id)
                }
            )
        }
    }

    // MARK: - Progress card

    private var progressCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(totalCount) receipt\(totalCount == 1 ? "" : "s") to review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text(progressSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .animation(.easeInOut, value: savedCount)
            }

            Spacer(minLength: 0)

            if allSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: "346049"))
                    .transition(.scale.combined(with: .opacity))
            } else {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "DEDAD2"), lineWidth: 2.5)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: totalCount > 0 ? CGFloat(savedCount) / CGFloat(totalCount) : 0)
                        .stroke(Color(hex: "346049"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: savedCount)
                    Text("\(savedCount)/\(totalCount)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(hex: "346049"))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
        )
        .animation(.spring(response: 0.3), value: allSaved)
    }

    private var progressSubtitle: String {
        if savedCount == 0 { return "Tap a receipt to review and save" }
        if allSaved        { return "All saved — tap Done to finish" }
        return "\(savedCount) of \(totalCount) saved"
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, Color(hex: "F6F5F3")],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
            .allowsHitTesting(false)

            Button { onDone() } label: {
                Text(doneLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "2F402E"))
                    )
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 34)

            Color(hex: "F6F5F3")
        }
        .background(Color(hex: "F6F5F3"))
    }

    private var doneLabel: String {
        if allSaved       { return "Done · All \(totalCount) saved ✓" }
        if savedCount > 0 { return "Done · \(savedCount) of \(totalCount) saved" }
        return "Done"
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
                        drafts[idx].amountText  = String(format: "%.2f", amount)
                    }
                    if let extractedDate = result.date {
                        drafts[idx].date = extractedDate
                    }
                    if isPro {
                        if let name = result.merchant { drafts[idx].merchant = name }
                        if let notes = result.notes   { drafts[idx].notes    = notes }
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func markSaved(draftId: UUID) {
        guard let idx = drafts.firstIndex(where: { $0.id == draftId }) else { return }
        withAnimation(.spring(response: 0.3)) {
            drafts[idx].isSaved = true
        }
    }
}

// MARK: - Draft card

private struct DraftReceiptCard: View {
    let draft: ReceiptDraft
    let onEdit: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var formattedAmount: String {
        guard let cents = draft.amountCents else { return "Set amount" }
        let whole = cents / 100
        let frac  = cents % 100
        return "$\(whole).\(String(format: "%02d", frac))"
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                // Receipt thumbnail
                Image(uiImage: draft.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
                    )

                // Details
                VStack(alignment: .leading, spacing: 5) {
                    if draft.isProcessing {
                        HStack(spacing: 8) {
                            shimmerBar(width: 72, height: 16)
                            ProgressView()
                                .scaleEffect(0.65)
                                .tint(Color(hex: "8F9E94"))
                        }
                        shimmerBar(width: 110, height: 12)
                    } else {
                        Text(formattedAmount)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(
                                draft.amountCents == nil
                                    ? Color(hex: "C4BFB9")
                                    : Color(hex: "1C1C1E")
                            )

                        HStack(spacing: 4) {
                            if !draft.merchant.isEmpty {
                                Text(draft.merchant)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "8F9E94"))
                                    .lineLimit(1)
                                Text("·")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "C4BFB9"))
                            }
                            Text(Self.dateFormatter.string(from: draft.date))
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                    }
                }

                Spacer(minLength: 0)

                statusBadge
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        draft.isSaved ? Color(hex: "346049").opacity(0.35) : Color(hex: "DEDAD2"),
                        lineWidth: draft.isSaved ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(DraftCardButtonStyle())
        .disabled(draft.isProcessing)
        .opacity(draft.isProcessing ? 0.75 : 1)
        .animation(.easeInOut(duration: 0.2), value: draft.isProcessing)
        .animation(.spring(response: 0.3), value: draft.isSaved)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if draft.isSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: "346049"))
                .transition(.scale.combined(with: .opacity))
        } else if !draft.isProcessing {
            Text("Review")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "346049"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "E8F0EA"))
                .clipShape(Capsule())
        }
    }

    private func shimmerBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(hex: "EEEDEB"))
            .frame(width: width, height: height)
    }
}

// MARK: - Card press style

private struct DraftCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
