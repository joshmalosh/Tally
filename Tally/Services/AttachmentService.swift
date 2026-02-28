import UIKit

actor AttachmentService {
    static let shared = AttachmentService()

    private let fileManager = FileManager.default

    private var attachmentsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var thumbnailsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
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

    nonisolated func loadImage(key: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Attachments", isDirectory: true).appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    nonisolated func loadThumbnail(key: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Thumbnails", isDirectory: true).appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let data = thumbnail?.jpegData(compressionQuality: 0.6) else { return }
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
