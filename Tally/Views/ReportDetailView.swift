import SwiftUI
import SwiftData

/// Preset cover emojis offered when creating or renaming a report.
let reportEmojiOptions = ["🗂️","🌴","💼","🔨","🧾","📑","✈️","🏠","🚗","🎬","🍽️","🏥","🎁","📸","⚽️","🎓"]

// MARK: - Report detail (the dossier)

struct ReportDetailView: View {
    let report: ReportModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil },
           sort: \ExpenseModel.date, order: .reverse) private var allExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingExport = false
    @State private var showingAdd = false
    @State private var showingRename = false
    @State private var showingDeleteConfirm = false
    @State private var detailExpenseId: String?

    private var myExpenses: [ExpenseModel] {
        allExpenses.filter { $0.resolvedReportIds.contains(report.id) }
    }
    private var totalCents: Int {
        myExpenses.filter { $0.currency == appState.activeCurrency }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "F0EDE6").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 0) {
                        summaryCard
                    }
                    .padding(.bottom, 120)
                }
                .scrollContentBackground(.hidden)
            }

            exportFooter
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) {
            GlobalExportSheet(initialSelection: myExpenses, directSelection: true)
        }
        .sheet(isPresented: $showingAdd) {
            AddExpensesToReportSheet(report: report)
        }
        .sheet(isPresented: $showingRename) {
            ReportEditSheet(report: report)
        }
        .sheet(item: $detailExpenseId) { id in
            ExpenseDetailView(expenseId: id)
        }
        .confirmationDialog("Delete this report?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete report", role: .destructive) { deleteReport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The report is removed. Your expenses stay in Tally.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text("Reports").font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color(hex: "4A5E50"))
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { showingRename = true } label: { Label("Rename report", systemImage: "pencil") }
                Button {
                    report.archivedAt = report.isArchived ? nil : .now
                    report.updatedAt = .now
                    try? modelContext.save()
                    Haptics.firm()
                    if report.isArchived { dismiss() }
                } label: {
                    Label(report.isArchived ? "Unarchive report" : "Archive report", systemImage: "archivebox")
                }
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete report", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "4A5E50"))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: "EDEAE4")).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { showingRename = true } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(report.emoji)
                                .font(.system(size: 24))
                                .frame(width: 46, height: 46)
                                .background(Color(hex: "E8EFE9"))
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(Color(hex: "2F402E"))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .offset(x: 4, y: 4)
                        }
                        Text(report.name.isEmpty ? "Untitled report" : report.name)
                            .font(.dmSerifDisplay(25))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                amountLine.padding(.top, 14)

                HStack(spacing: 8) {
                    Text("📎 \(myExpenses.count) docket\(myExpenses.count == 1 ? "" : "s") clipped")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E"))
                        .padding(.vertical, 4).padding(.horizontal, 9)
                        .background(Color(hex: "E8EFE9")).clipShape(Capsule())
                    let range = ReportsHubView.dateRangeLabel(for: myExpenses)
                    if !range.isEmpty {
                        Text(range).font(.system(size: 12)).foregroundStyle(Color(hex: "8F9E94"))
                    }
                }
                .padding(.top, 10)
            }
            .padding(16)

            if !myExpenses.isEmpty {
                Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5)
            }

            VStack(spacing: 0) {
                ForEach(myExpenses) { exp in
                    Button { detailExpenseId = exp.id } label: { expenseRow(exp) }
                        .buttonStyle(.plain)
                    if exp.id != myExpenses.last?.id {
                        Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5).padding(.leading, 47)
                    }
                }

                Button { Haptics.tap(); showingAdd = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        Text("Add an expense to this report").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "4A5E50"))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color(hex: "C6C0B4")))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, myExpenses.isEmpty ? 4 : 12)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var amountLine: some View {
        let symbol = CurrencyFormatter.shared.symbol(for: appState.activeCurrency)
        let whole = CurrencyFormatter.shared.groupedWhole(cents: totalCents, currencyCode: appState.activeCurrency)
        let showsCents = CurrencyFormatter.shared.usesDecimals(for: appState.activeCurrency)
        return HStack(alignment: .top, spacing: 0) {
            Text(symbol).font(.system(size: 22, weight: .regular, design: .monospaced)).padding(.top, 7)
            Text(whole).font(.system(size: 46, weight: .bold, design: .monospaced)).tracking(-2)
            if showsCents {
                Text(String(format: ".%02d", abs(totalCents % 100)))
                    .font(.system(size: 22, weight: .regular, design: .monospaced)).padding(.top, 9)
            }
        }
        .foregroundStyle(Color(hex: "1C1C1E"))
    }

    /// Same `ExpenseCard` the Home list and period drill-down use, so the receipt
    /// thumbnail + tag-coloured icon and layout are identical across the app —
    /// one visual style, never two.
    private func expenseRow(_ exp: ExpenseModel) -> some View {
        let tag = exp.resolvedTagIds.first.flatMap { id in tags.first { $0.id == id } }
        let label: String? = tag.map { t in
            if let pid = t.parentId, let g = tags.first(where: { $0.id == pid }) {
                return "\(g.name) › \(t.name)"
            }
            return t.name
        }
        let hasReceipt = exp.attachmentKey != nil || exp.attachmentData != nil
        return ExpenseCard(
            receiptCacheKey: hasReceipt ? (exp.attachmentKey ?? exp.id) : nil,
            receiptAttachmentKey: exp.attachmentKey,
            receiptAttachmentData: exp.attachmentData,
            isStatementSource: exp.source == "statement_import",
            iconEmoji: tag?.displayEmoji,
            iconSystemName: tag?.icon ?? "tag.fill",
            iconBackground: tag?.tagColor.primaryColor.opacity(0.15) ?? Color(hex: "EDEBE6"),
            description: exp.expenseDescription ?? "Expense",
            merchant: exp.merchant,
            notes: exp.notes,
            amountCents: exp.amountCents,
            currency: exp.currency,
            primaryTagLabel: label,
            primaryTagColor: tag?.tagColor,
            additionalTagCount: max(0, exp.resolvedTagIds.count - 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: Sticky export

    private var exportFooter: some View {
        Button {
            Haptics.firm()
            showingExport = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 17))
                Text("Export Report").font(.system(size: 15, weight: .semibold))
                Text("· \(myExpenses.count) docket\(myExpenses.count == 1 ? "" : "s")")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: "2F402E"))
            .clipShape(Capsule())
            .shadow(color: Color(hex: "2F402E").opacity(0.22), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
        .background(
            LinearGradient(colors: [Color(hex: "F0EDE6").opacity(0), Color(hex: "F0EDE6")],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120).allowsHitTesting(false),
            alignment: .bottom
        )
    }

    private func deleteReport() {
        report.deletedAt = .now
        report.updatedAt = .now
        try? modelContext.save()
        Haptics.crisp()
        dismiss()
    }
}

// MARK: - New report

struct NewReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var emoji = "🗂️"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                emojiPicker

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color(hex: "8F9E94"))
                    TextField("e.g. Bali Trip, Q2 Reimbursement", text: $name)
                        .font(.system(size: 17))
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                }

                Text("Then add expenses to it from here, or clip an expense to it from the expense screen.")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: "8F9E94"))

                Spacer()

                Button { create() } label: {
                    Text("Create report")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color(hex: "9DA99B") : Color(hex: "2F402E"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .navigationTitle("New report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color(hex: "4A5E50"))
                }
            }
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COVER").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color(hex: "8F9E94"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(reportEmojiOptions, id: \.self) { e in
                        Button { emoji = e; Haptics.tap() } label: {
                            Text(e).font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(emoji == e ? Color(hex: "2F402E") : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: emoji == e ? 0 : 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let report = ReportModel(name: trimmed, emoji: emoji)
        modelContext.insert(report)
        try? modelContext.save()
        Haptics.firm()
        dismiss()
    }
}

// MARK: - Rename / edit report

struct ReportEditSheet: View {
    let report: ReportModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var emoji = "🗂️"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COVER").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color(hex: "8F9E94"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(reportEmojiOptions, id: \.self) { e in
                                Button { emoji = e; Haptics.tap() } label: {
                                    Text(e).font(.system(size: 22))
                                        .frame(width: 44, height: 44)
                                        .background(emoji == e ? Color(hex: "2F402E") : Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: emoji == e ? 0 : 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color(hex: "8F9E94"))
                    TextField("Report name", text: $name)
                        .font(.system(size: 17)).padding(14).background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                }
                Spacer()
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    report.name = trimmed.isEmpty ? report.name : trimmed
                    report.emoji = emoji
                    report.updatedAt = .now
                    try? modelContext.save()
                    Haptics.firm()
                    dismiss()
                } label: {
                    Text("Save").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(hex: "2F402E")).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .navigationTitle("Edit report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color(hex: "4A5E50"))
                }
            }
            .onAppear { name = report.name; emoji = report.emoji }
        }
    }
}

// MARK: - Report picker (single-select, from the expense screen)

/// Clip one expense into a report. Single-select: None, the active reports (with
/// their spend + date window), and an inline "Create new report". Mirrors the Tag
/// picker's role on the expense screen — Report sits directly under Tag there.
struct ReportPickerSheet: View {
    @Binding var selectedReportId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @Query(filter: #Predicate<ReportModel> { $0.deletedAt == nil },
           sort: \ReportModel.createdAt, order: .reverse) private var reports: [ReportModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]

    @State private var showingNewReport = false

    /// Active reports only — you don't clip into an archived (sent) report.
    private var activeReports: [ReportModel] { reports.filter { !$0.isArchived } }

    private func reportExpenses(_ r: ReportModel) -> [ExpenseModel] {
        expenses.filter { $0.resolvedReportIds.contains(r.id) }
    }
    private func reportTotalCents(_ r: ReportModel) -> Int {
        reportExpenses(r).filter { $0.currency == appState.activeCurrency }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    noneRow
                    if !activeReports.isEmpty {
                        Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5).padding(.leading, 16)
                        ForEach(activeReports) { report in
                            Button { pick(report.id) } label: { reportRow(report) }.buttonStyle(.plain)
                            if report.id != activeReports.last?.id {
                                Rectangle().fill(Color(hex: "DEDAD2")).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Button { Haptics.tap(); showingNewReport = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        Text("Create new report").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "4A5E50"))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color(hex: "C6C0B4")))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .navigationTitle("Add to report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color(hex: "2F402E")).fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingNewReport) { NewReportView() }
        }
    }

    private var noneRow: some View {
        Button { pick(nil) } label: {
            HStack(spacing: 12) {
                Image(systemName: "nosign")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "EDEAE4"))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text("None")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                if selectedReportId == nil {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "2F402E"))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reportRow(_ report: ReportModel) -> some View {
        let exps = reportExpenses(report)
        let on = selectedReportId == report.id
        let dateLabel = ReportsHubView.dateRangeLabel(for: exps)
        return HStack(spacing: 12) {
            Text(report.emoji)
                .font(.system(size: 19))
                .frame(width: 38, height: 38)
                .background(Color(hex: "E8EFE9"))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(report.name.isEmpty ? "Untitled report" : report.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Text("\(exps.count) docket\(exps.count == 1 ? "" : "s")\(dateLabel.isEmpty ? "" : " · \(dateLabel)")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            Spacer(minLength: 8)
            Text(CurrencyFormatter.shared.format(cents: reportTotalCents(report), currencyCode: appState.activeCurrency))
                .font(.system(size: 14, weight: .semibold).monospaced())
                .foregroundStyle(Color(hex: "8F9E94"))
            if on {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "2F402E"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }

    private func pick(_ id: String?) {
        Haptics.tap()
        selectedReportId = id
        dismiss()
    }
}

// MARK: - Add expenses to a report

struct AddExpensesToReportSheet: View {
    let report: ReportModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil },
           sort: \ExpenseModel.date, order: .reverse) private var allExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var selected: Set<String> = []
    @State private var searchText = ""
    /// Local tag/group filter — nil means "All". Never touches the Home filter's
    /// global `appState.activeFilterIds`, so drilling down here is self-contained.
    @State private var filterTagId: String?

    // MARK: Filter chip data

    private var groups: [TagModel] {
        tags.filter { $0.isGroup }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var standaloneTags: [TagModel] {
        tags.filter { !$0.isGroup && $0.parentId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func childIds(of group: TagModel) -> [String] {
        tags.filter { $0.parentId == group.id }.map(\.id)
    }

    /// Does an expense fall under the active tag/group filter?
    private func matchesTagFilter(_ exp: ExpenseModel) -> Bool {
        guard let id = filterTagId else { return true }
        let ids = exp.resolvedTagIds
        if let group = tags.first(where: { $0.id == id && $0.isGroup }) {
            // A group matches the group id itself or any of its children.
            return ids.contains(id) || childIds(of: group).contains(where: ids.contains)
        }
        return ids.contains(id)
    }

    private func matchesSearch(_ exp: ExpenseModel) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = [exp.merchant, exp.notes, exp.expenseDescription].compactMap { $0 }.joined(separator: " ")
        return hay.localizedCaseInsensitiveContains(q)
    }

    /// Expenses not already clipped in, matching search + tag filter.
    private var candidates: [ExpenseModel] {
        allExpenses.filter {
            !$0.resolvedReportIds.contains(report.id) && matchesTagFilter($0) && matchesSearch($0)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                filterChips
                ScrollView {
                    if candidates.isEmpty {
                        Text(searchText.isEmpty && filterTagId == nil
                             ? "No expenses to add yet."
                             : "No expenses match this filter.")
                            .font(.system(size: 14)).foregroundStyle(Color(hex: "8F9E94"))
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(candidates) { exp in
                                Button { toggle(exp.id) } label: { row(exp) }.buttonStyle(.plain)
                                if exp.id != candidates.last?.id {
                                    Rectangle().fill(Color(hex: "F0EDE6")).frame(height: 0.5).padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 90)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .navigationTitle("Add to \(report.name.isEmpty ? "report" : report.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color(hex: "4A5E50"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") { addSelected() }
                        .disabled(selected.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Search + filter

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Color(hex: "8F9E94"))
            TextField("Search expenses", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color(hex: "C4BFB9"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(id: nil, label: "All", isGroup: false, color: nil)
                ForEach(groups) { g in
                    filterChip(id: g.id, label: g.name, isGroup: true, color: g.tagColor.primaryColor)
                }
                ForEach(standaloneTags) { t in
                    filterChip(id: t.id, label: t.name, isGroup: false, color: t.tagColor.primaryColor)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func filterChip(id: String?, label: String, isGroup: Bool, color: Color?) -> some View {
        let on = filterTagId == id
        return Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { filterTagId = id }
        } label: {
            HStack(spacing: 5) {
                if let color {
                    if isGroup {
                        Image(systemName: "folder.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(on ? .white : color)
                    } else {
                        Circle().fill(on ? Color.white : color).frame(width: 7, height: 7)
                    }
                }
                Text(label).font(.system(size: 13, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? Color.white : Color(hex: "4A5E50"))
            .padding(.vertical, 7).padding(.horizontal, 13)
            .background(on ? Color(hex: "2F402E") : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "DEDAD2"), lineWidth: on ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Row — checkbox + shared ExpenseCard (matches Home multi-select)

    private func row(_ exp: ExpenseModel) -> some View {
        let on = selected.contains(exp.id)
        let tag = exp.resolvedTagIds.first.flatMap { id in tags.first { $0.id == id } }
        let label: String? = tag.map { t in
            if let pid = t.parentId, let g = tags.first(where: { $0.id == pid }) { return "\(g.name) › \(t.name)" }
            return t.name
        }
        let hasReceipt = exp.attachmentKey != nil || exp.attachmentData != nil
        return HStack(spacing: 0) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: on ? .regular : .light))
                .foregroundStyle(on ? Color(hex: "2F402E") : Color(hex: "C4BFB9"))
                .frame(width: 44)
            ExpenseCard(
                receiptCacheKey: hasReceipt ? (exp.attachmentKey ?? exp.id) : nil,
                receiptAttachmentKey: exp.attachmentKey,
                receiptAttachmentData: exp.attachmentData,
                isStatementSource: exp.source == "statement_import",
                iconEmoji: tag?.displayEmoji,
                iconSystemName: tag?.icon ?? "tag.fill",
                iconBackground: tag?.tagColor.primaryColor.opacity(0.15) ?? Color(hex: "EDEBE6"),
                description: exp.expenseDescription ?? "Expense",
                merchant: exp.merchant,
                notes: exp.notes,
                amountCents: exp.amountCents,
                currency: exp.currency,
                primaryTagLabel: label,
                primaryTagColor: tag?.tagColor,
                additionalTagCount: max(0, exp.resolvedTagIds.count - 1)
            )
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        Haptics.tap()
    }

    private func addSelected() {
        for exp in allExpenses where selected.contains(exp.id) {
            var ids = exp.reportIds ?? []
            if !ids.contains(report.id) { ids.append(report.id) }
            exp.reportIds = ids
            exp.updatedAt = .now
        }
        try? modelContext.save()
        Haptics.firm()
        dismiss()
    }
}
