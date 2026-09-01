import SwiftUI
import SwiftData

/// The soft-delete bin. Deleted expenses keep their `deletedAt` and their receipt
/// until the user restores them (clears `deletedAt`) or permanently removes them
/// (hard delete + attachment cleanup). Reached from Settings.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ExpenseModel> { $0.deletedAt != nil },
        sort: \ExpenseModel.deletedAt,
        order: .reverse
    ) private var deleted: [ExpenseModel]

    @State private var pendingPurge: ExpenseModel?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        ZStack {
            Color(hex: "F0EDE6").ignoresSafeArea()

            if deleted.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(deleted) { expense in
                            row(expense)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this expense permanently? This can't be undone.",
            isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                if let e = pendingPurge { purge(e) }
                pendingPurge = nil
            }
            Button("Cancel", role: .cancel) { pendingPurge = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(hex: "8F9E94"))
            Text("Nothing here")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("Deleted expenses show up here so you can restore them.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "8F9E94"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private func row(_ expense: ExpenseModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: expense))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .lineLimit(1)
                    if let when = expense.deletedAt {
                        Text("Deleted \(Self.relative.localizedString(for: when, relativeTo: Date()))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "8E8E93"))
                    }
                }
                Spacer(minLength: 8)
                Text(CurrencyFormatter.shared.format(cents: expense.amountCents, currencyCode: expense.currency))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(hex: "1C1C1E"))
            }

            HStack(spacing: 10) {
                Button { restore(expense) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .semibold))
                        Text("Restore").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "2F402E"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "E8F0EA")))
                }
                .buttonStyle(.plain)

                Button { pendingPurge = expense } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill").font(.system(size: 12, weight: .semibold))
                        Text("Delete").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "C0392B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "F6E4DF")))
                }
                .buttonStyle(.plain)
            }
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

    private func title(for expense: ExpenseModel) -> String {
        if let m = expense.merchant, !m.isEmpty { return m }
        if let d = expense.expenseDescription, !d.isEmpty { return d }
        return "Expense"
    }

    private func restore(_ expense: ExpenseModel) {
        expense.deletedAt = nil
        expense.updatedAt = Date()
        try? modelContext.save()
    }

    private func purge(_ expense: ExpenseModel) {
        if let key = expense.attachmentKey {
            Task { await AttachmentService.shared.deleteAttachment(key: key) }
        }
        modelContext.delete(expense)
        try? modelContext.save()
    }
}
