import UIKit
import SwiftUI

enum ExpenseExportService {

    // MARK: - Bundled CSV + Receipts

    /// Builds a CSV export. If any expenses have receipt attachments, bundles everything
    /// into a ZIP (CSV + `receipts/` folder). Otherwise shares a plain CSV file.
    /// Returns the file URL to share via `UIActivityViewController`.
    static func buildCSVExport(
        expenses: [ExpenseModel],
        tags: [Tag],
        filenamePrefix: String,
        includeReceipts: Bool = false
    ) -> URL? {
        let fm = FileManager.default
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateSuffix = dateFormatter.string(from: Date())

        let sorted = expenses
            .filter { $0.deletedAt == nil }
            .sorted { $0.date < $1.date }

        // Build receipt manifest only when the caller opts in
        var receiptFilenames: [String: String] = [:]
        var receiptSources: [(filename: String, model: ExpenseModel)] = []

        if includeReceipts {
            for (index, model) in sorted.enumerated() {
                let hasAttachment = model.attachmentKey != nil || model.attachmentData != nil
                guard hasAttachment else { continue }
                let rawExt = model.attachmentKey?.components(separatedBy: ".").last ?? "jpg"
                let ext = rawExt.allSatisfy(\.isLetter) && (1...4).contains(rawExt.count) ? rawExt : "jpg"
                let label = (model.merchant ?? model.expenseDescription ?? "expense")
                    .lowercased()
                    .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                    .prefix(40)
                let filename = "\(String(format: "%03d", index + 1))_\(label).\(ext)"
                receiptFilenames[model.id] = "receipts/\(filename)"
                receiptSources.append((filename: filename, model: model))
            }
        }

        let domainExpenses: [Expense] = sorted.map { model in
            Expense(
                id: model.id,
                userId: model.userId,
                amountCents: model.amountCents,
                currency: model.currency,
                date: model.date,
                description: model.expenseDescription,
                merchant: model.merchant,
                tagIds: model.resolvedTagIds,
                notes: model.notes,
                attachmentKey: model.attachmentKey,
                source: ExpenseSource(rawValue: model.source) ?? .manual,
                createdAt: model.createdAt,
                updatedAt: model.updatedAt,
                deletedAt: nil
            )
        }

        let csv = ExpenseCalculations.generateCSV(
            expenses: domainExpenses,
            tags: tags,
            receiptFilenames: receiptFilenames
        )

        // Plain CSV when no receipts are being bundled
        if receiptSources.isEmpty {
            let fileURL = fm.temporaryDirectory.appendingPathComponent("\(filenamePrefix)_\(dateSuffix).csv")
            try? fm.removeItem(at: fileURL)
            do {
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                return fileURL
            } catch {
                return nil
            }
        }

        // ZIP: CSV + receipts/ folder
        let exportDir = fm.temporaryDirectory.appendingPathComponent("tally_export_\(UUID().uuidString)")
        let receiptsDir = exportDir.appendingPathComponent("receipts")
        do {
            try fm.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
        } catch { return nil }

        let csvURL = exportDir.appendingPathComponent("\(filenamePrefix)_\(dateSuffix).csv")
        do {
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        } catch { return nil }

        for item in receiptSources {
            let destURL = receiptsDir.appendingPathComponent(item.filename)
            if let key = item.model.attachmentKey,
               let image = AttachmentService.shared.loadImage(key: key),
               let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: destURL)
            } else if let data = item.model.attachmentData {
                try? data.write(to: destURL)
            }
        }

        let zipURL = fm.temporaryDirectory.appendingPathComponent("\(filenamePrefix)_\(dateSuffix).zip")
        try? fm.removeItem(at: zipURL)

        var resultURL: URL?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: exportDir, options: .forUploading, error: &coordinatorError) { tempZipURL in
            try? fm.copyItem(at: tempZipURL, to: zipURL)
            resultURL = zipURL
        }

        try? fm.removeItem(at: exportDir)
        return resultURL
    }

    // MARK: - Plain Text

    static func plainText(expense: ExpenseModel, tags: [TagModel], currency: String) -> String {
        var lines: [String] = []

        if let merchant = expense.merchant, !merchant.isEmpty {
            lines.append("Merchant: \(merchant)")
        }

        let amount = CurrencyFormatter.shared.format(
            cents: expense.amountCents,
            currencyCode: expense.currency
        )
        lines.append("Amount: \(amount)")

        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy"
        lines.append("Date: \(fmt.string(from: expense.date))")

        if !tags.isEmpty {
            lines.append("Tags: \(tags.map(\.name).joined(separator: ", "))")
        }

        if let notes = expense.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Image Generation

    @MainActor
    static func generateImage(expense: ExpenseModel, tags: [TagModel], currency: String) -> UIImage {
        let cardWidth: CGFloat = 380
        let padding: CGFloat = 28

        let amount = CurrencyFormatter.shared.format(
            cents: expense.amountCents,
            currencyCode: expense.currency
        )
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy"
        let dateStr = fmt.string(from: expense.date)
        let merchant = expense.merchant ?? expense.expenseDescription ?? "Expense"
        let tagStr = tags.isEmpty ? nil : tags.map(\.name).joined(separator: ", ")

        var receiptImage: UIImage?
        if let key = expense.attachmentKey {
            receiptImage = AttachmentService.shared.loadImage(key: key)
        } else if let data = expense.attachmentData {
            receiptImage = UIImage(data: data)
        }

        let card = VStack(alignment: .leading, spacing: 16) {
            Text(merchant)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "111417"))

            Text(amount)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(Color(hex: "111417"))

            HStack(spacing: 16) {
                Label(dateStr, systemImage: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "6B7280"))

                if let tagStr {
                    Label(tagStr, systemImage: "tag")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
            }

            if let img = receiptImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Text("Generated by Tally")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            }
        }
        .padding(padding)
        .frame(width: cardWidth)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }

    // MARK: - PDF Generation

    @MainActor
    static func generatePDF(expense: ExpenseModel, tags: [TagModel], currency: String) -> URL {
        let amount = CurrencyFormatter.shared.format(
            cents: expense.amountCents,
            currencyCode: expense.currency
        )
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy"
        let dateStr = fmt.string(from: expense.date)
        let merchant = expense.merchant ?? expense.expenseDescription ?? "Expense"
        let tagStr = tags.isEmpty ? nil : tags.map(\.name).joined(separator: ", ")

        var receiptImage: UIImage?
        if let key = expense.attachmentKey {
            receiptImage = AttachmentService.shared.loadImage(key: key)
        } else if let data = expense.attachmentData {
            receiptImage = UIImage(data: data)
        }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 60

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tally_expense_\(expense.id).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            // Header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor(red: 0.61, green: 0.64, blue: 0.68, alpha: 1)
            ]
            let header = NSAttributedString(string: "Tally", attributes: headerAttrs)
            header.draw(at: CGPoint(x: margin, y: y))
            y += 30

            // Divider
            UIColor(red: 0.89, green: 0.91, blue: 0.9, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 0.5)).fill()
            y += 20

            // Merchant
            let merchantAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor(red: 0.067, green: 0.078, blue: 0.09, alpha: 1)
            ]
            let merchantStr = NSAttributedString(string: merchant, attributes: merchantAttrs)
            merchantStr.draw(at: CGPoint(x: margin, y: y))
            y += 34

            // Amount
            let amountAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor(red: 0.067, green: 0.078, blue: 0.09, alpha: 1)
            ]
            let amountStr = NSAttributedString(string: amount, attributes: amountAttrs)
            amountStr.draw(at: CGPoint(x: margin, y: y))
            y += 44

            // Details
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(red: 0.42, green: 0.44, blue: 0.5, alpha: 1)
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor(red: 0.067, green: 0.078, blue: 0.09, alpha: 1)
            ]

            let fields: [(String, String)] = [
                ("Date", dateStr),
                ("Tags", tagStr ?? "None"),
                ("Notes", expense.notes ?? "—")
            ]

            for (label, value) in fields {
                NSAttributedString(string: label, attributes: labelAttrs)
                    .draw(at: CGPoint(x: margin, y: y))
                y += 18
                NSAttributedString(string: value, attributes: valueAttrs)
                    .draw(at: CGPoint(x: margin, y: y))
                y += 28
            }

            // Receipt image
            if let img = receiptImage {
                y += 10
                let maxW = pageWidth - margin * 2
                let maxH: CGFloat = 300
                let ratio = min(maxW / img.size.width, maxH / img.size.height, 1)
                let drawW = img.size.width * ratio
                let drawH = img.size.height * ratio
                img.draw(in: CGRect(x: margin, y: y, width: drawW, height: drawH))
                y += drawH + 20
            }

            // Footer
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor(red: 0.61, green: 0.64, blue: 0.68, alpha: 1)
            ]
            let footer = NSAttributedString(string: "Generated by Tally", attributes: footerAttrs)
            footer.draw(at: CGPoint(x: margin, y: pageHeight - margin))
        }

        try? data.write(to: tempURL)
        return tempURL
    }
}
