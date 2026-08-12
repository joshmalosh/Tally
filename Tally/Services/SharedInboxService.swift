import Foundation
import UIKit

/// Reads receipt files deposited by the TallyShare extension into the shared
/// App Group container. The extension writes; the app consumes and deletes.
enum SharedInboxService {
    static let appGroupId = "group.com.asimplelife.tally"

    struct InboxItem {
        let url: URL
        var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
    }

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// All pending shared files, oldest first.
    static func pendingItems() -> [InboxItem] {
        guard let dir = inboxURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.creationDateKey]
              ) else { return [] }
        return urls
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }
            .map { InboxItem(url: $0) }
    }

    static func loadImage(_ item: InboxItem) -> UIImage? {
        guard !item.isPDF, let data = try? Data(contentsOf: item.url) else { return nil }
        return UIImage(data: data)
    }

    /// Moves a pending PDF out of the inbox into a temporary location the
    /// add-expense flow can attach from, and removes the inbox copy.
    static func claimPDF(_ item: InboxItem) -> URL? {
        guard item.isPDF else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(item.url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        guard (try? FileManager.default.copyItem(at: item.url, to: tmp)) != nil else { return nil }
        remove(item)
        return tmp
    }

    static func remove(_ item: InboxItem) {
        try? FileManager.default.removeItem(at: item.url)
    }
}

/// Identifiable wrapper so a claimed shared PDF can drive a fullScreenCover(item:).
struct SharedPDFItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Identifiable wrapper so a single shared image can drive a fullScreenCover(item:).
struct SharedImageItem: Identifiable {
    let image: UIImage
    let id = UUID().uuidString
}

/// Identifiable wrapper carrying a batch of picked/shared images so multi-receipt
/// review can be driven by fullScreenCover(item:). Presenting off a separate Bool
/// plus an images array raced — the cover could build before the array settled,
/// giving an empty "Review receipts" screen. Binding the images to the item makes
/// presentation and data atomic.
struct MultiReceiptBatch: Identifiable {
    let images: [UIImage]
    let id = UUID().uuidString
}
