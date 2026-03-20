import SwiftUI
import SwiftData

struct ExportExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let expense: ExpenseModel
    let tags: [TagModel]

    @State private var showingShareSheet = false
    @State private var shareItem: Any?
    @State private var showingToast = false
    @State private var toastMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.xs) {
                        exportOption(
                            icon: "doc.text",
                            title: "Share as PDF",
                            subtitle: "Formatted expense document",
                            proOnly: true
                        ) {
                            sharePDF()
                        }

                        exportOption(
                            icon: "photo",
                            title: "Share as Image",
                            subtitle: "Receipt + expense details",
                            proOnly: false
                        ) {
                            shareImage()
                        }

                        Divider()
                            .foregroundStyle(Color.borderColor.opacity(0.5))
                            .padding(.vertical, Spacing.sm)

                        exportOption(
                            icon: "doc.on.clipboard",
                            title: "Copy expense details",
                            subtitle: "Plain text summary",
                            proOnly: false
                        ) {
                            copyDetails()
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let item = shareItem {
                    ActivitySheet(items: [item])
                }
            }
            .overlay(alignment: .bottom) {
                if showingToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
    }

    private func exportOption(
        icon: String,
        title: String,
        subtitle: String,
        proOnly: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let locked = proOnly && !appState.isPro

        return Button {
            if locked { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: Spacing.smd) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(locked ? Color.textMuted : Color.brandPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Fonts.body(16))
                            .foregroundStyle(locked ? Color.textMuted : Color.textPrimary)

                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    Text(locked ? "Pro feature" : subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.6 : 1)
    }

    // MARK: - Actions

    private func copyDetails() {
        let text = ExpenseExportService.plainText(
            expense: expense,
            tags: tags,
            currency: appState.defaultCurrency
        )
        UIPasteboard.general.string = text
        showToast("Copied to clipboard")
    }

    private func shareImage() {
        let image = ExpenseExportService.generateImage(
            expense: expense,
            tags: tags,
            currency: appState.defaultCurrency
        )
        shareItem = image
        showingShareSheet = true
    }

    private func sharePDF() {
        guard appState.isPro else { return }
        let url = ExpenseExportService.generatePDF(
            expense: expense,
            tags: tags,
            currency: appState.defaultCurrency
        )
        shareItem = url
        showingShareSheet = true
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingToast = false
            }
        }
    }

    private var toastView: some View {
        Text(toastMessage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.smd)
            .background(Color.textPrimary.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
    }
}

// MARK: - Activity Sheet

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
