import SwiftUI
import SwiftData

struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    let expenseId: String

    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingDeleteConfirmation = false
    @State private var showingEdit = false
    @State private var attachmentImage: UIImage?
    @State private var showingFullImage = false

    private var expense: ExpenseModel? {
        activeExpenses.first { $0.id == expenseId }
    }

    private func tagFor(_ id: String) -> TagModel? {
        tags.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            if let expense {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        amountHeader(expense)

                        if let image = attachmentImage {
                            attachmentSection(image: image)
                        }

                        detailRows(expense)

                        if let notes = expense.notes, !notes.isEmpty {
                            notesSection(notes)
                        }

                        deleteButton

                        if !appState.isPro {
                            BannerAdView()
                                .padding(.top, Spacing.sm)
                        }
                    }
                    .padding(Spacing.md)
                }
                .background(Color.surface)
                .navigationTitle("Expense")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit") { showingEdit = true }
                            .foregroundStyle(Color.brandPrimary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
                .alert(expense.isRecurring ? "Stop \(expense.merchant ?? "recurring") recurring?" : "Delete expense?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button(expense.isRecurring ? "Stop Recurring" : "Delete", role: .destructive) { deleteExpense(expense) }
                } message: {
                    Text(expense.isRecurring ? "Past entries will be kept." : "This action cannot be undone.")
                }
                .sheet(isPresented: $showingEdit) {
                    AddExpenseView(editingExpense: expense)
                }
                .fullScreenCover(isPresented: $showingFullImage) {
                    if let image = attachmentImage {
                        FullImageView(image: image)
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

    // MARK: - Amount Header

    private func parentOf(_ tag: TagModel) -> TagModel? {
        guard let parentId = tag.parentId else { return nil }
        return tags.first { $0.id == parentId }
    }

    private func amountHeader(_ expense: ExpenseModel) -> some View {
        let resolvedTags = expense.resolvedTagIds.compactMap { tagFor($0) }

        return VStack(spacing: Spacing.sm) {
            Text(CurrencyFormatter.shared.format(cents: expense.amountCents, currencyCode: expense.currency))
                .font(Fonts.brand(36))
                .foregroundStyle(Color.textPrimary)

            if resolvedTags.isEmpty {
                TagPill(name: "Untagged", tagColor: TagColors.forId("warmGrey"), isActive: true)
            } else {
                FlowLayout(spacing: 6, rowAlignment: .bottom, centerRows: true) {
                    ForEach(resolvedTags) { tag in
                        VStack(spacing: 2) {
                            if let group = parentOf(tag) {
                                Text(group.name)
                                    .font(Fonts.caption(10))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            TagPill(name: tag.name, tagColor: tag.tagColor, isActive: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Attachment

    private func attachmentSection(image: UIImage) -> some View {
        Button { showingFullImage = true } label: {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Rows

    private func detailRows(_ expense: ExpenseModel) -> some View {
        VStack(spacing: 0) {
            detailRow(label: "Date", value: formatDate(expense.date))
            Divider().padding(.leading, Spacing.md)
            if expense.isRecurring {
                detailRow(label: "Recurring", value: formatRecurringFrequency(expense.recurringFrequency))
                Divider().padding(.leading, Spacing.md)
            }
            if let desc = expense.expenseDescription, !desc.isEmpty {
                detailRow(label: "Description", value: desc)
                Divider().padding(.leading, Spacing.md)
            }
            if let merchant = expense.merchant, !merchant.isEmpty {
                detailRow(label: "Merchant", value: merchant)
                Divider().padding(.leading, Spacing.md)
            }
            detailRow(label: "Source", value: expense.source.capitalized)
            if expense.attachmentKey != nil {
                Divider().padding(.leading, Spacing.md)
                detailRow(label: "Attachment", value: "Receipt attached")
            }
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notes")
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)
            Text(notes)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
        .padding(.top, Spacing.md)
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

    // MARK: - Helpers

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

    private func formatRecurringFrequency(_ frequency: String) -> String {
        switch frequency {
        case "weekly": return "Weekly"
        case "yearly": return "Yearly"
        default: return "Monthly"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: date)
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
