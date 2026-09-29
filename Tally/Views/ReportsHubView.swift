import SwiftUI
import SwiftData

// MARK: - Reports hub (documents tab)

/// The documents hub: build expense reports (envelopes/dossiers) and export them.
/// Distinct from Insights (analytics). Reports are grouped by lifecycle
/// (Active / Archived), not by "report groups"; their emoji + name do the sorting.
struct ReportsHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ReportModel> { $0.deletedAt == nil },
           sort: \ReportModel.createdAt, order: .reverse) private var reports: [ReportModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]

    enum Filter: String, CaseIterable { case all = "All", active = "Active", archived = "Archived" }
    @State private var filter: Filter = .active

    @State private var showingNewReport = false
    @State private var showingExport = false
    /// Non-nil ⇒ exporting one report's expenses; nil ⇒ Quick Export (period picker).
    @State private var exportSelection: [ExpenseModel]? = nil

    // MARK: Per-report rollups

    private func reportExpenses(_ r: ReportModel) -> [ExpenseModel] {
        expenses.filter { $0.resolvedReportIds.contains(r.id) }
    }
    private func reportTotalCents(_ r: ReportModel) -> Int {
        reportExpenses(r).filter { $0.currency == appState.activeCurrency }.reduce(0) { $0 + $1.amountCents }
    }

    private var activeCount: Int { reports.filter { !$0.isArchived }.count }
    private var archivedCount: Int { reports.filter { $0.isArchived }.count }
    private var filtered: [ReportModel] {
        switch filter {
        case .all:      return reports
        case .active:   return reports.filter { !$0.isArchived }
        case .archived: return reports.filter { $0.isArchived }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your reports")
                        .font(.dmSerifDisplay(30))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    actionTiles
                    filterChips

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { report in
                            NavigationLink {
                                ReportDetailView(report: report)
                            } label: {
                                dossierCard(report)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNewReport) { NewReportView() }
            .sheet(isPresented: $showingExport) {
                GlobalExportSheet(initialSelection: exportSelection,
                                  directSelection: exportSelection != nil)
            }
        }
    }

    // MARK: Action tiles (New Report / Quick Export)

    private var actionTiles: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                showingNewReport = true
            } label: {
                actionTile(system: "doc.badge.plus", label: "New Report", primary: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                exportSelection = nil
                showingExport = true
            } label: {
                actionTile(system: "square.and.arrow.up", label: "Quick Export", primary: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private func actionTile(system: String, label: String, primary: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(primary ? Color(hex: "F2EEE7") : Color(hex: "2F402E"))
            Text(label)
                .font(.dmSerifDisplay(17))
                .foregroundStyle(primary ? Color(hex: "F2EEE7") : Color(hex: "2F402E"))
        }
        .frame(maxWidth: .infinity, minHeight: 106)
        .background(primary ? Color(hex: "2F402E") : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(primary ? Color.clear : Color(hex: "9BC3A8"), lineWidth: 1.5)
        )
    }

    // MARK: Lifecycle filters

    private var filterChips: some View {
        HStack(spacing: 8) {
            chip(.all, count: reports.count)
            chip(.active, count: activeCount)
            chip(.archived, count: archivedCount)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private func chip(_ f: Filter, count: Int) -> some View {
        let on = filter == f
        return Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { filter = f }
        } label: {
            HStack(spacing: 4) {
                Text(f.rawValue)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(on ? 0.8 : 0.55)
            }
            .foregroundStyle(on ? Color.white : Color(hex: "4A5E50"))
            .padding(.vertical, 7)
            .padding(.horizontal, 15)
            .background(on ? Color(hex: "2F402E") : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "DEDAD2"), lineWidth: on ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Dossier card

    private func dossierCard(_ report: ReportModel) -> some View {
        let exps = reportExpenses(report)
        let total = reportTotalCents(report)
        let dateLabel = Self.dateRangeLabel(for: exps)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(report.emoji)
                    .font(.system(size: 19))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "E8EFE9"))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .opacity(report.isArchived ? 0.9 : 1)
                Text(report.name.isEmpty ? "Untitled report" : report.name)
                    .font(.dmSerifDisplay(18))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(CurrencyFormatter.shared.format(cents: total, currencyCode: appState.activeCurrency))
                    .font(.system(size: 15, weight: .bold).monospaced())
                    .foregroundStyle(Color(hex: "1C1C1E"))
            }
            HStack {
                Text("📎 \(exps.count) docket\(exps.count == 1 ? "" : "s")\(dateLabel.isEmpty ? "" : " · \(dateLabel)")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8F9E94"))
                Spacer()
                if report.isArchived {
                    Text("Sent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "8F9E94"))
                        .padding(.vertical, 5).padding(.horizontal, 13)
                        .background(Color(hex: "EDEAE4")).clipShape(Capsule())
                } else {
                    Button {
                        Haptics.tap()
                        exportSelection = exps
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .frame(width: 36, height: 36)
                            .background(Color(hex: "2F402E").opacity(0.06))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(hex: "DEDAD2"), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 50)
        }
        .padding(15)
        .background(report.isArchived ? Color(hex: "FAF8F3") : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(filter == .archived ? "🗄️" : "🗂️").font(.system(size: 40))
            Text(filter == .archived ? "No archived reports yet" : "No reports yet")
                .font(.dmSerifDisplay(20))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("Got a project or work trip coming up? Add them to a report to track or export later.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "8F9E94"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// "6–9 Mar" / "Feb 2025" style range from a set of expenses.
    static func dateRangeLabel(for exps: [ExpenseModel]) -> String {
        let dates = exps.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else { return "" }
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDate(first, equalTo: last, toGranularity: .day) {
            df.dateFormat = "d MMM"
            return df.string(from: first)
        }
        if cal.isDate(first, equalTo: last, toGranularity: .month) {
            let dayF = DateFormatter(); dayF.dateFormat = "d"
            df.dateFormat = "d MMM"
            return "\(dayF.string(from: first))–\(df.string(from: last))"
        }
        df.dateFormat = "MMM yyyy"
        return "\(df.string(from: first)) – \(df.string(from: last))"
    }
}
