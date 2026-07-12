import UIKit
import UniformTypeIdentifiers

/// Tally share extension: accepts shared images (screenshots, photos) and PDFs,
/// writes them into the App Group inbox, shows a brief confirmation, and
/// completes. The main app picks the files up on next foreground and routes
/// them into the receipt review flow — the user always reviews before saving.
final class ShareViewController: UIViewController {
    private static let appGroupId = "group.com.asimplelife.tally"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        processAttachments()
    }

    private var inboxURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) else { return nil }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private func processAttachments() {
        guard let inbox = inboxURL,
              let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }
        let providers = items.flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        var savedCount = 0
        let lock = NSLock()
        func recordSave() {
            lock.lock(); savedCount += 1; lock.unlock()
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                    defer { group.leave() }
                    guard let url else { return }
                    let dest = inbox.appendingPathComponent("\(UUID().uuidString).pdf")
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                        recordSave()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data {
                        let dest = inbox.appendingPathComponent("\(UUID().uuidString).img")
                        if (try? data.write(to: dest)) != nil {
                            recordSave()
                        }
                        group.leave()
                        return
                    }
                    // Some providers (e.g. fresh screenshots) only vend a UIImage
                    // object, not encoded data — fall back to loading the item.
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                        defer { group.leave() }
                        var image: UIImage?
                        if let img = item as? UIImage {
                            image = img
                        } else if let url = item as? URL, let d = try? Data(contentsOf: url) {
                            image = UIImage(data: d)
                        } else if let d = item as? Data {
                            image = UIImage(data: d)
                        }
                        guard let png = image?.pngData() else { return }
                        let dest = inbox.appendingPathComponent("\(UUID().uuidString).img")
                        if (try? png.write(to: dest)) != nil {
                            recordSave()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.showConfirmationAndFinish(savedCount: savedCount)
        }
    }

    private func showConfirmationAndFinish(savedCount: Int) {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.18, green: 0.25, blue: 0.18, alpha: 1) // #2F402E
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = savedCount > 0
            ? "Added to Tally — open Tally to review"
            : "Couldn't add to Tally"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(label)
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -60),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])

        card.alpha = 0
        UIView.animate(withDuration: 0.18) { card.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
