import UIKit
import ImageIO
import PDFKit

actor AttachmentService {
    static let shared = AttachmentService()

    // MARK: - PDF → image

    /// First page of a PDF rendered to a white-backed image at 2x. A file upload
    /// is turned into a receipt image with this, so PDFs flow through the exact
    /// same photo path everywhere (upload hero, list thumbnail, expense detail).
    nonisolated static func firstPageImage(fromPDF data: Data) -> UIImage? {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        return render(page)
    }

    nonisolated static func firstPageImage(fromPDF url: URL) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        return render(page)
    }

    private nonisolated static func render(_ page: PDFPage) -> UIImage {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    /// Decodes image data straight to a small, fully-rendered thumbnail via
    /// ImageIO. This does the expensive work (decode + downscale) up front off
    /// the main thread, so SwiftUI never decodes a full-resolution receipt on
    /// the main thread at draw time — the cause of slow/janky thumbnails.
    /// Target pixel size for list thumbnails: a ~44pt slot at 3x plus headroom.
    /// A fixed value keeps this callable off the main thread (no UIScreen).
    nonisolated static func downsampledThumbnail(from data: Data, maxPixel: CGFloat = 300) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private let fileManager = FileManager.default
    private let attachmentsDirectory: URL
    private let thumbnailsDirectory: URL

    private static let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    init() {
        let attachDir = Self.docsDir.appendingPathComponent("Attachments", isDirectory: true)
        let thumbDir = Self.docsDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        self.attachmentsDirectory = attachDir
        self.thumbnailsDirectory = thumbDir
    }

    func saveImage(_ image: UIImage, id: String) throws -> String {
        let key = "\(id).jpg"
        let url = attachmentsDirectory.appendingPathComponent(key)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw AttachmentError.compressionFailed
        }
        guard data.count <= 20 * 1024 * 1024 else {
            throw AttachmentError.fileTooLarge
        }

        try data.write(to: url)
        try generateThumbnail(from: image, key: key)
        return key
    }

    func saveFile(from sourceURL: URL, id: String) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        let key = "\(id).\(ext)"
        let destURL = attachmentsDirectory.appendingPathComponent(key)

        let attrs = try fileManager.attributesOfItem(atPath: sourceURL.path)
        if let size = attrs[.size] as? Int, size > 20 * 1024 * 1024 {
            throw AttachmentError.fileTooLarge
        }

        try fileManager.copyItem(at: sourceURL, to: destURL)
        return key
    }

    nonisolated static func exceedsMaxSize(_ image: UIImage) -> Bool {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        let estimatedBytes = pixels * 0.3
        return estimatedBytes > 20 * 1024 * 1024
    }

    nonisolated func loadImage(key: String) -> UIImage? {
        let url = Self.docsDir.appendingPathComponent("Attachments", isDirectory: true).appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    nonisolated func loadThumbnail(key: String) -> UIImage? {
        let url = Self.docsDir.appendingPathComponent("Thumbnails", isDirectory: true).appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Force full decode now (off the main thread) rather than lazily at draw.
        return Self.downsampledThumbnail(from: data) ?? UIImage(data: data)
    }

    nonisolated func loadImageData(key: String) -> Data? {
        let url = Self.docsDir.appendingPathComponent("Attachments", isDirectory: true).appendingPathComponent(key)
        return try? Data(contentsOf: url)
    }

    /// Persist a thumbnail for an attachment whose thumbnail file is missing
    /// (failed write, or the attachment arrived without one).
    func saveThumbnail(_ image: UIImage, key: String) {
        try? generateThumbnail(from: image, key: key)
    }

    func deleteAttachment(key: String) {
        let url = attachmentsDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: url)
        let thumbURL = thumbnailsDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: thumbURL)
    }

    func attachmentURL(for key: String) -> URL {
        attachmentsDirectory.appendingPathComponent(key)
    }

    private func generateThumbnail(from image: UIImage, key: String) throws {
        let maxDimension: CGFloat = 200
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let data = renderer.jpegData(withCompressionQuality: 0.6) { ctx in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        let url = thumbnailsDirectory.appendingPathComponent(key)
        try data.write(to: url)
    }
}

enum AttachmentError: LocalizedError {
    case compressionFailed
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .compressionFailed: "Failed to compress the image."
        case .fileTooLarge: "File is too large. Maximum size is 20MB."
        }
    }
}
