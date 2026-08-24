import SwiftUI
import SwiftData

struct GlobalExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }, sort: \ExpenseModel.date, order: .reverse) private var activeExpenses: [ExpenseModel]
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    /// When present, pre-selects the matching period and defaults to it.
    var initialSelection: [ExpenseModel]? = nil

    // MARK: - Period enum

    enum ExportPeriod: CaseIterable, Equatable {
        case thisMonth, lastMonth, yearToDate, thisFinancialYear, lastFinancialYear, allTime
    }

    enum ExportFormat { case csv, pdf, byTag, email }

    // MARK: - State

    @State private var step: Int = 1
    @State private var selectedPeriod: ExportPeriod = .thisMonth
    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedTagFilterIds: Set<String> = []

    @State private var isExporting = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""
    @State private var showingTagExportPicker = false
    @State private var showingTagFilter = false
    @State private var showingReceiptSheet = false

    // MARK: - Formatters

    private static let shortMonthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    private static let longMonthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let calendarMonthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    // MARK: - Amount formatting helper

    private func fmtCents(_ cents: Int) -> String {
        let whole = cents / 100
        let frac  = abs(cents % 100)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return "$\(f.string(from: NSNumber(value: whole)) ?? "\(whole)").\(String(format: "%02d", frac))"
    }

    // MARK: - Period helpers

    private func dateRange(for period: ExportPeriod) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .thisMonth:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!
            let start = cal.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth
            let end   = cal.dateInterval(of: .month, for: lastMonth)?.end ?? lastMonth
            return (start, min(end, now))
        case .yearToDate:
            let start = cal.dateInterval(of: .year, for: now)?.start ?? now
            return (start, now)
        case .thisFinancialYear:
            let start = appState.currentFinancialYearStart
            return (start, now)
        case .lastFinancialYear:
            let fyStart = appState.currentFinancialYearStart
            let prevFyEnd = cal.date(byAdding: .day, value: -1, to: fyStart) ?? fyStart
            let prevFyStart = cal.date(byAdding: .year, value: -1, to: fyStart) ?? fyStart
            return (prevFyStart, prevFyEnd)
        case .allTime:
            let earliest = activeExpenses.last?.date ?? now
            return (earliest, now)
        }
    }

    private func expenses(for period: ExportPeriod) -> [ExpenseModel] {
        let r = dateRange(for: period)
        return activeExpenses.filter { $0.date >= r.start && $0.date <= r.end }
    }

    private func periodName(for period: ExportPeriod) -> String {
        switch period {
        case .thisMonth:         return "This month"
        case .lastMonth:         return "Last month"
        case .yearToDate:        return "Year to date"
        case .thisFinancialYear: return "This financial year"
        case .lastFinancialYear: return "Last financial year"
        case .allTime:           return "All time"
        }
    }

    private func periodDateLabel(for period: ExportPeriod) -> String {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .thisMonth:
            return Self.longMonthYear.string(from: now)
        case .lastMonth:
            let last = cal.date(byAdding: .month, value: -1, to: now)!
            return Self.longMonthYear.string(from: last)
        case .yearToDate:
            let year = cal.component(.year, from: now)
            let monthAbbr = Self.calendarMonthYear.string(from: now)
            return "Jan – \(monthAbbr) \(year)"
        case .thisFinancialYear:
            let start = appState.currentFinancialYearStart
            let startYear = cal.component(.year, from: start)
            let endYear = cal.component(.year, from: now)
            return "FY\(startYear % 100)–\(endYear % 100) · Jul – Jun"
        case .lastFinancialYear:
            let start = appState.currentFinancialYearStart
            let prevStart = cal.date(byAdding: .year, value: -1, to: start)!
            let prevStartYear = cal.component(.year, from: prevStart)
            let prevEndYear = cal.component(.year, from: start)
            return "FY\(prevStartYear % 100)–\(prevEndYear % 100)"
        case .allTime:
            if let earliest = activeExpenses.last?.date {
                return "Since \(Self.shortMonthYear.string(from: earliest))"
            }
            return "All time"
        }
    }

    private func periodShortLabel(for period: ExportPeriod) -> String {
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        switch period {
        case .thisMonth:         return f.string(from: now).uppercased()
        case .lastMonth:         return f.string(from: cal.date(byAdding: .month, value: -1, to: now)!).uppercased()
        case .yearToDate:        return "JAN – \(f.string(from: now).uppercased())"
        case .thisFinancialYear: return "THIS FY"
        case .lastFinancialYear: return "LAST FY"
        case .allTime:           return "ALL TIME"
        }
    }

    // MARK: - Selected period computed values

    private var selectedExpenses: [ExpenseModel] {
        // Apply tag filter on top of period
        let base = expenses(for: selectedPeriod)
        guard !selectedTagFilterIds.isEmpty else { return base }
        return base.filter { expense in
            !expense.resolvedTagIds.filter { selectedTagFilterIds.contains($0) }.isEmpty
        }
    }

    private var selectedTotal: Int {
        selectedExpenses.reduce(0) { $0 + $1.amountCents }
    }

    private var selectedHasReceipts: Bool {
        selectedExpenses.contains { $0.attachmentKey != nil || $0.attachmentData != nil }
    }

    private var tagFilterLabel: String {
        guard !selectedTagFilterIds.isEmpty else { return "All tags & groups" }
        let names = selectedTagFilterIds.compactMap { id in allTags.first { $0.id == id }?.name }
        if names.count == 1 { return names[0] }
        return "\(names[0]) +\(names.count - 1)"
    }

    // MARK: - Format helpers

    private var formatOptions: [(icon: String, iconBg: Color, title: String, subtitle: String, badge: String?, format: ExportFormat)] {
        [
            ("tablecells.fill",  Color(hex: "2F6B3F"),  "Spreadsheet", "CSV · works with Excel & Sheets", "POPULAR", .csv),
            ("doc.richtext.fill", Color(hex: "C0392B"), "Formatted report", "PDF with summary & receipts", nil, .pdf),
            ("tag.fill",         Color(hex: "5B8FC7"),  "By tag or group", "One file per tag, zipped", nil, .byTag),
            ("envelope.fill",    Color(hex: "E07A40"),  "Email", "Send straight to any inbox", nil, .email),
        ]
    }

    private var exportLabel: String {
        "EXPORT \(periodName(for: selectedPeriod).uppercased())"
    }

    // MARK: - Auto-detect period from initialSelection

    private func bestPeriod(for selection: [ExpenseModel]) -> ExportPeriod {
        let cal = Calendar.current
        let now = Date()
        let ids = Set(selection.map(\.id))

        for period in ExportPeriod.allCases {
            let periodIds = Set(expenses(for: period).map(\.id))
            if ids == periodIds { return period }
        }

        // If it's all expenses in a single past month, try lastMonth
        if let first = selection.first {
            let comp = cal.dateComponents([.year, .month], from: first.date)
            let lastComp = cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -1, to: now)!)
            if comp.year == lastComp.year && comp.month == lastComp.month {
                return .lastMonth
            }
        }
        return .thisMonth
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "F0EDE6").ignoresSafeArea()

            if activeExpenses.isEmpty {
                emptyState
            } else if step == 1 {
                step1View
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            } else {
                step2View
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear {
            if let sel = initialSelection, !sel.isEmpty {
                selectedPeriod = bestPeriod(for: sel)
            }
        }
        .sheet(isPresented: $showingProUpsell) {
            ProFeatureSheet(featureName: proFeatureName, limitReached: proFeatureName == "CSV export")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTagExportPicker) {
            TagExportPickerSheet(
                expenses: selectedExpenses,
                tags: Array(allTags),
                periodLabel: periodName(for: selectedPeriod)
            )
        }
        .sheet(isPresented: $showingReceiptSheet) {
            ReceiptExportConfirmSheet(
                onCSVOnly: { exportCSV(includeReceipts: false) },
                onWithPhotos: { exportCSV(includeReceipts: true) }
            )
        }
        .overlay(alignment: .bottom) {
            if showingToast {
                toastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 80)
            }
        }
    }

    // MARK: - Step 1: Pick a period

    private var step1View: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "EDEAE4"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPORT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .tracking(1.2)
                        Text("Pick a period.")
                            .font(Font.dmSerifDisplay(32))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                        Text("Choose a window, optionally filter by tag,\nthen pick a format.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                    .padding(.horizontal, 20)

                    // Hero selected card
                    selectedHeroCard
                        .padding(.horizontal, 20)

                    // Quick periods grid
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Quick periods")
                                .font(Font.dmSerifDisplay(18))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                            Text("Tap to switch")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                        .padding(.horizontal, 20)

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(ExportPeriod.allCases, id: \.self) { period in
                                periodGridCell(period)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Filter by tag
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Filter by tag")
                                .font(Font.dmSerifDisplay(18))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                            Text("Optional")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                        .padding(.horizontal, 20)

                        Button {
                            showingTagFilter = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "FEE8D6"))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color(hex: "E07A40"))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tagFilterLabel)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color(hex: "1C1C1E"))
                                    Text(selectedTagFilterIds.isEmpty
                                         ? "Tap to narrow down what's exported"
                                         : "\(selectedExpenses.count) expense\(selectedExpenses.count == 1 ? "" : "s") match")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "8F9E94"))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: "C4BFB9"))
                            }
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)

            // Next button
            step1NextButton
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .sheet(isPresented: $showingTagFilter) {
            TagExportPickerSheet(
                expenses: expenses(for: selectedPeriod),
                tags: Array(allTags),
                periodLabel: periodName(for: selectedPeriod)
            )
        }
    }

    private var selectedHeroCard: some View {
        let exps = selectedExpenses
        let total = exps.reduce(0) { $0 + $1.amountCents }
        let amtFormatted = fmtCents(total)
        let dollarIdx = amtFormatted.index(amtFormatted.startIndex, offsetBy: 1)
        let dotIdx = amtFormatted.lastIndex(of: ".") ?? amtFormatted.endIndex
        let wholePart = String(amtFormatted[dollarIdx..<dotIdx])
        let fracPart  = String(amtFormatted[dotIdx...])

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(periodShortLabel(for: selectedPeriod))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.5)
            }

            Text(periodName(for: selectedPeriod))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 0) {
                Text("$")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 5)
                Text(wholePart)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(-1)
                Text(fracPart)
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 6)
            }

            HStack {
                Text("\(exps.count) expense\(exps.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("SELECTED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E"))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.9))
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .background(Color(hex: "2F402E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func periodGridCell(_ period: ExportPeriod) -> some View {
        let exps = expenses(for: period)
        let total = exps.reduce(0) { $0 + $1.amountCents }
        let isSelected = selectedPeriod == period
        let amtStr = fmtCents(total)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPeriod = period
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(periodName(for: period))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                        Text(periodDateLabel(for: period))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .lineLimit(1)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color(hex: "2F402E") : Color(hex: "DEDAD2"), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if isSelected {
                            Circle()
                                .fill(Color(hex: "2F402E"))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(amtStr)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(exps.count) exp.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(isSelected ? Color(hex: "EBF3ED") : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "2F402E") : Color(hex: "DEDAD2"), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var step1NextButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { step = 2 }
        } label: {
            HStack(spacing: 6) {
                Text("Next")
                    .font(Font.dmSerifDisplay(20))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color(hex: "2F402E"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .buttonStyle(.plain)
        .background(
            Color(hex: "F0EDE6")
                .opacity(0.95)
                .ignoresSafeArea()
        )
    }

    // MARK: - Step 2: Pick a format

    private var step2View: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step = 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "4A5E50"))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("STEP 2 OF 2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .tracking(0.8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPORT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "4A5E50"))
                            .tracking(1.2)
                        Text("Pick a format.")
                            .font(Font.dmSerifDisplay(32))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                        Text("How would you like to receive \(periodName(for: selectedPeriod).lowercased())?")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                    .padding(.horizontal, 20)

                    // Period summary row
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "E8F0EA"))
                                .frame(width: 44, height: 44)
                            Image(systemName: "calendar")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "2F402E"))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(periodName(for: selectedPeriod))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            let exps = selectedExpenses
                            let total = exps.reduce(0) { $0 + $1.amountCents }
                            let amtStr = fmtCents(total)
                            Text("\(periodDateLabel(for: selectedPeriod)) · \(amtStr) · \(exps.count) expenses")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                    .padding(.horizontal, 20)

                    // Choose format
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose format")
                            .font(Font.dmSerifDisplay(18))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            ForEach(Array(formatOptions.enumerated()), id: \.offset) { idx, opt in
                                formatRow(opt)
                                if idx < formatOptions.count - 1 {
                                    Divider()
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                        .padding(.horizontal, 20)
                    }

                    // Bottom padding for sticky export bar
                    Spacer(minLength: 90)
                }
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)

            // Sticky export bar
            step2ExportBar
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
    }

    private func formatRow(_ opt: (icon: String, iconBg: Color, title: String, subtitle: String, badge: String?, format: ExportFormat)) -> some View {
        // CSV only reads as locked once the free monthly export is spent.
        let locked = opt.format == .csv ? !appState.canExportCSV : !appState.isPro
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedFormat = opt.format
            performExport(format: opt.format)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(opt.iconBg.opacity(locked ? 0.4 : 0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: opt.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(locked ? Color(hex: "8F9E94") : opt.iconBg)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(opt.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(locked ? Color(hex: "8F9E94") : Color(hex: "1C1C1E"))
                        if let badge = opt.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: "2F6B3F"))
                                .tracking(0.3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "B8D9C0"))
                                .clipShape(Capsule())
                        }
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "8F9E94"))
                        }
                    }
                    Text(locked ? "Pro feature" : opt.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "C4BFB9"))
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
        }
        .buttonStyle(.plain)
    }

    private var step2ExportBar: some View {
        let exps = selectedExpenses
        let total = exps.reduce(0) { $0 + $1.amountCents }
        let amtStr = fmtCents(total)

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(exportLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(0.8)
                Text(amtStr)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                performExport(format: selectedFormat)
            } label: {
                HStack(spacing: 6) {
                    Text("Export")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "2F402E"))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.bottom, 16)
        .background(Color(hex: "2F402E"))
    }

    // MARK: - Export Dispatch

    private func performExport(format: ExportFormat) {
        // CSV: free tier gets 1 per calendar month. Everything else is Pro-only.
        let allowed = format == .csv ? appState.canExportCSV : appState.isPro
        guard allowed else {
            proFeatureName = format == .csv ? "CSV export" : format == .pdf ? "PDF export" : "Export"
            showingProUpsell = true
            return
        }

        switch format {
        case .csv:
            if selectedHasReceipts {
                showingReceiptSheet = true
            } else {
                exportCSV(includeReceipts: false)
            }
        case .pdf:
            showToast("PDF export coming soon")
        case .byTag:
            showingTagExportPicker = true
        case .email:
            showToast("Email export coming soon")
        }
    }

    // MARK: - Export Actions

    private func exportCSV(includeReceipts: Bool) {
        isExporting = true
        let exps = selectedExpenses
        let domainTags: [Tag] = allTags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }
        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: exps,
            tags: domainTags,
            filenamePrefix: "tally_expenses",
            includeReceipts: includeReceipts
        ) else {
            isExporting = false
            showToast("Export failed")
            return
        }
        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "8F9E94"))
            VStack(spacing: 8) {
                Text("Nothing to export")
                    .font(Font.dmSerifDisplay(22))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("Add your first expense, then come back here to export.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) { showingToast = false }
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

// MARK: - Selected Export Sheet

struct SelectedExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]

    let expenses: [ExpenseModel]
    var filterLabel: String = "Selected"

    @State private var isExporting = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""
    @State private var showingReceiptSheet = false

    private var hasReceipts: Bool {
        expenses.contains { $0.attachmentKey != nil || $0.attachmentData != nil }
    }

    private var expenseCount: Int { expenses.count }

    private var totalCents: Int {
        expenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        summaryHeader
                            .padding(.bottom, Spacing.lg)

                        VStack(spacing: Spacing.xs) {
                            exportOption(
                                icon: "tablecells",
                                title: "Export as CSV",
                                subtitle: "\(expenseCount) expense\(expenseCount == 1 ? "" : "s") \u{2022} \(filterLabel)",
                                proOnly: true
                            ) {
                                if hasReceipts {
                                    showingReceiptSheet = true
                                } else {
                                    exportCSV(includeReceipts: false)
                                }
                            }

                            exportOption(
                                icon: "doc.richtext",
                                title: "Export as PDF",
                                subtitle: "Formatted report with summary",
                                proOnly: true
                            ) {
                                exportPDF()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingProUpsell) {
                ProFeatureSheet(featureName: proFeatureName, limitReached: proFeatureName == "CSV export")
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingReceiptSheet) {
                ReceiptExportConfirmSheet(
                    onCSVOnly: { exportCSV(includeReceipts: false) },
                    onWithPhotos: { exportCSV(includeReceipts: true) }
                )
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

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text(CurrencyFormatter.shared.format(cents: totalCents, currencyCode: appState.defaultCurrency))
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expenses")
                        .font(Fonts.caption(12))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(expenseCount)")
                        .font(Fonts.headline(22))
                        .foregroundStyle(Color.textPrimary)
                }
            }

            HStack {
                Text(filterLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .padding(.horizontal, Spacing.smd)
                    .padding(.vertical, 6)
                    .background(Color.chipInactiveBg)
                    .clipShape(Capsule())

                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }

    // MARK: - Option Row

    private func exportOption(
        icon: String,
        title: String,
        subtitle: String,
        proOnly: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let locked = proOnly && !appState.isPro

        return Button {
            if locked {
                proFeatureName = title
                showingProUpsell = true
                return
            }
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.6 : 1)
    }

    // MARK: - Export Actions

    private func exportCSV(includeReceipts: Bool) {
        guard appState.canExportCSV else {
            proFeatureName = "CSV export"
            showingProUpsell = true
            return
        }

        isExporting = true

        let domainTags: [Tag] = allTags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: expenses,
            tags: domainTags,
            filenamePrefix: "tally_selected",
            includeReceipts: includeReceipts
        ) else {
            isExporting = false
            showToast("Export failed")
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }

    private func exportPDF() {
        guard appState.isPro else {
            proFeatureName = "PDF export"
            showingProUpsell = true
            return
        }
        showToast("PDF export coming soon")
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

// MARK: - Tag/Group Export Picker

struct TagExportPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let expenses: [ExpenseModel]
    let tags: [TagModel]
    let periodLabel: String

    @State private var selectedIds: Set<String> = []
    @State private var isExporting = false
    @State private var showingReceiptSheet = false
    @State private var showingProUpsell = false
    @State private var proFeatureName = ""

    private var matchingHasReceipts: Bool {
        matchingExpenses.contains { $0.attachmentKey != nil || $0.attachmentData != nil }
    }

    private var standaloneTags: [TagModel] {
        tags.filter { $0.parentId == nil && !$0.isGroup }
    }

    private var groupTags: [TagModel] {
        tags.filter { $0.isGroup }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var matchingExpenses: [ExpenseModel] {
        guard !selectedIds.isEmpty else { return [] }

        let selectedGroupIds = selectedIds.filter { id in groupTags.contains { $0.id == id } }
        let selectedTagIds = selectedIds.subtracting(selectedGroupIds)

        var expandedTagIds = selectedTagIds
        for groupId in selectedGroupIds {
            if let group = groupTags.first(where: { $0.id == groupId }) {
                let childIds = childrenOf(group).map(\.id)
                expandedTagIds.formUnion(childIds)
            }
        }
        // Expenses can be tagged with a group directly (group-alone selection),
        // so a selected group must match its own id, not just its children.
        expandedTagIds.formUnion(selectedGroupIds)

        return expenses.filter { expense in
            !expense.resolvedTagIds.filter({ expandedTagIds.contains($0) }).isEmpty
        }
    }

    private var matchingTotal: Int {
        matchingExpenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if standaloneTags.isEmpty && groupTags.isEmpty {
                    VStack(spacing: Spacing.lg) {
                        Spacer()

                        Image(systemName: "tag")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textMuted)

                        VStack(spacing: Spacing.sm) {
                            Text("No tags yet")
                                .font(Fonts.headline(20))
                                .foregroundStyle(Color.textPrimary)

                            Text("Create tags in Settings to filter and export expenses by category.")
                                .font(Fonts.body(15))
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, Spacing.xl)

                        Spacer()
                    }
                } else {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        if !standaloneTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Tags")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                VStack(spacing: 0) {
                                    ForEach(standaloneTags) { tag in
                                        let isSelected = selectedIds.contains(tag.id)
                                        Button {
                                            toggleSelection(tag.id)
                                        } label: {
                                            HStack(spacing: Spacing.smd) {
                                                Circle()
                                                    .fill(tag.tagColor.primaryColor)
                                                    .frame(width: 12, height: 12)
                                                Text(tag.name)
                                                    .font(Fonts.body(15))
                                                    .foregroundStyle(Color.textPrimary)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(Color.brandPrimary)
                                                }
                                            }
                                            .padding(.horizontal, Spacing.md)
                                            .frame(height: 48)
                                            .background(isSelected ? Color.brandTint : Color.surface)
                                        }
                                        .buttonStyle(.plain)

                                        if tag.id != standaloneTags.last?.id {
                                            Divider().padding(.leading, Spacing.md)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(Color.borderColor, lineWidth: 1)
                                )
                            }
                        }

                        if !groupTags.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Groups")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.leading, Spacing.xs)

                                VStack(spacing: 0) {
                                    ForEach(groupTags) { group in
                                        let isSelected = selectedIds.contains(group.id)
                                        Button {
                                            toggleSelection(group.id)
                                        } label: {
                                            HStack(spacing: Spacing.smd) {
                                                Image(systemName: "folder.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(group.tagColor.primaryColor)
                                                Text(group.name)
                                                    .font(Fonts.body(15))
                                                    .foregroundStyle(Color.textPrimary)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(Color.brandPrimary)
                                                }
                                            }
                                            .padding(.horizontal, Spacing.md)
                                            .frame(height: 48)
                                            .background(isSelected ? Color.brandTint : Color.surface)
                                        }
                                        .buttonStyle(.plain)

                                        if group.id != groupTags.last?.id {
                                            Divider().padding(.leading, Spacing.md)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(Color.borderColor, lineWidth: 1)
                                )
                            }
                        }

                        if !selectedIds.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Divider().foregroundStyle(Color.borderColor)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(matchingExpenses.count) expense\(matchingExpenses.count == 1 ? "" : "s")")
                                            .font(Fonts.label(14))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(CurrencyFormatter.shared.format(cents: matchingTotal, currencyCode: appState.defaultCurrency))
                                            .font(Fonts.caption(13))
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    Text(periodLabel)
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .padding(.top, Spacing.sm)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }

                VStack(spacing: 0) {
                    Divider()
                    PrimaryButton(
                        title: selectedIds.isEmpty
                            ? "Select tags or groups"
                            : "Export \(matchingExpenses.count) expenses",
                        action: {
                            if matchingHasReceipts {
                                showingReceiptSheet = true
                            } else {
                                exportFiltered(includeReceipts: false)
                            }
                        },
                        isLoading: isExporting
                    )
                    .disabled(selectedIds.isEmpty || matchingExpenses.isEmpty)
                    .padding(Spacing.md)
                }
                .background(Color.bgPrimary)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export by tag/group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }

                if !selectedIds.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedIds.removeAll()
                            }
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showingReceiptSheet) {
                ReceiptExportConfirmSheet(
                    onCSVOnly: { exportFiltered(includeReceipts: false) },
                    onWithPhotos: { exportFiltered(includeReceipts: true) }
                )
            }
            .sheet(isPresented: $showingProUpsell) {
                ProFeatureSheet(featureName: proFeatureName, limitReached: proFeatureName == "CSV export")
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedIds)
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func exportFiltered(includeReceipts: Bool) {
        guard !matchingExpenses.isEmpty else { return }
        guard appState.canExportCSV else {
            proFeatureName = "CSV export"
            showingProUpsell = true
            return
        }

        isExporting = true

        let domainTags: [Tag] = tags.map {
            Tag(id: $0.id, userId: $0.userId, name: $0.name, colorId: $0.colorId, icon: $0.icon, sortOrder: $0.sortOrder, parentId: $0.parentId)
        }

        let selectedNames = selectedIds.compactMap { id in tags.first { $0.id == id }?.name }
        let tagSuffix = selectedNames.prefix(3).joined(separator: "_").replacingOccurrences(of: " ", with: "-")

        guard let fileURL = ExpenseExportService.buildCSVExport(
            expenses: matchingExpenses,
            tags: domainTags,
            filenamePrefix: "tally_\(tagSuffix)",
            includeReceipts: includeReceipts
        ) else {
            isExporting = false
            return
        }

        appState.recordCSVExport()
        isExporting = false
        presentShareSheet(items: [fileURL])
    }
}

// MARK: - Receipt Export Confirm Sheet

struct ReceiptExportConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCSVOnly: () -> Void
    let onWithPhotos: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: "DEDAD2"))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Include receipt photos?")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                Text("Photos will be bundled alongside the CSV in a ZIP file.")
                    .font(Fonts.body(14))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onWithPhotos()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 15, weight: .medium))
                        Text("Include receipt photos")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "2F402E"))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                    onCSVOnly()
                } label: {
                    Text("CSV only")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color.bgPrimary)
        .presentationDetents([.height(290)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }
}

// MARK: - Share Sheet Presenter

func presentShareSheet(items: [Any]) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
    var topVC = rootVC
    while let presented = topVC.presentedViewController { topVC = presented }
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    topVC.present(vc, animated: true)
}
