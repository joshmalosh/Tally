import SwiftUI
import SwiftData
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Import from statement (Pro): pick one PDF, read its transactions in memory,
/// turn the debits into draft expenses, and hand them to the SHARED multi-expense
/// review (`MultiReceiptReviewView`, statement config). The PDF is never stored —
/// we read it, build the drafts, and drop it.
struct StatementImportView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var phase: Phase = .chooser
    @State private var drafts: [ReceiptDraft] = []
    @State private var showingPicker = false
    @State private var didAutoOpen = false

    private enum Phase { case chooser, parsing, review, empty }

    var body: some View {
        ZStack {
            Color(hex: "F0EDE6").ignoresSafeArea()
            switch phase {
            case .chooser: chooser
            case .parsing: loading
            case .empty:   emptyState
            case .review:
                MultiReceiptReviewView(drafts: drafts, config: .statement,
                                       onCancel: onCancel, onDone: onDone)
            }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { handlePick($0) }
        .onAppear {
            guard !didAutoOpen else { return }
            didAutoOpen = true
            showingPicker = true
        }
    }

    // MARK: - States

    private var chooser: some View {
        VStack(spacing: 20) {
            Spacer()
            PDFSourceTile(size: 64, cornerRadius: 16)
            Text("Import from statement")
                .font(.dmSerifDisplay(26))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("Choose a PDF statement. Tally reads each transaction into an\nexpense you can review before saving. The file isn't stored.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "8F9E94"))
                .multilineTextAlignment(.center)
            Button { showingPicker = true } label: {
                Text("Choose a PDF")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 28)
                    .background(Color(hex: "2F402E"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Cancel") { onCancel() }
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8F9E94"))
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var loading: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color(hex: "2F402E"))
            Text("Reading your statement…")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8F9E94"))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🧾").font(.system(size: 52))
            Text("No expenses found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("Tally couldn't read any transactions from that PDF.\nTry a different statement.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "8F9E94"))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Choose another") { showingPicker = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "2F402E"))
                Button("Cancel") { onCancel() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Pick + parse

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            // Cancelled or errored — stay on the chooser so the user can retry.
            if phase != .review { phase = .chooser }
        case .success(let urls):
            guard let url = urls.first else { return }
            phase = .parsing
            Task {
                let built = await buildDrafts(from: url)
                await MainActor.run {
                    drafts = built
                    phase = built.isEmpty ? .empty : .review
                }
            }
        }
    }

    private func buildDrafts(from url: URL) async -> [ReceiptDraft] {
        let text = await statementText(from: url)
        // Debits only — money out. Credits/deposits are filtered here.
        let lines = StatementParser.parse(text).filter(\.isDebit)
        let existingNames = tags.map(\.name)
        let usesDecimals = CurrencyFormatter.shared.usesDecimals(for: appState.defaultCurrency)

        return lines.map { line in
            var d = ReceiptDraft()
            d.image = nil
            d.isProcessing = false
            d.date = line.date
            d.amountCents = line.amountCents
            d.amountText = usesDecimals
                ? String(format: "%.2f", Double(line.amountCents) / 100)
                : String(line.amountCents)
            d.merchant = line.description
            d.notes = "Generated from PDF statement"
            if let match = BulkExpenseParser.findMatchingTag(suggested: line.description, existingTags: existingNames),
               let tag = tags.first(where: { $0.name == match }) {
                d.selectedTagIds = [tag.id]
            }
            d.isChecked = true
            return d
        }
    }

    /// Reads the statement text in memory. Native text layer first (no OCR); a
    /// scanned statement falls back to rasterize-then-Vision. Nothing is written
    /// to disk; the security-scoped URL is released immediately.
    private func statementText(from url: URL) async -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return "" }
        if let text = doc.string,
           text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
            return text
        }
        // Scanned statement (no text layer): OCR each page.
        var ocr = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let image = renderPDFPage(page) else { continue }
            ocr += await ReceiptOCRService.extractFullText(from: image) + "\n"
        }
        return ocr
    }

    // ponytail: duplicated from AddExpenseView.renderPDFPage; unify into a shared
    // PDF helper if a third caller appears.
    private func renderPDFPage(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
