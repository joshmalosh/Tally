import Foundation
import Network
import CoreData

/// Monitors network reachability and iCloud sync status.
/// Actual data sync is handled automatically by SwiftData + CloudKit.
@Observable
final class SyncEngine {
    private(set) var isOnline = true
    private(set) var lastSyncDate: Date?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.tally.network-monitor")

    private static let lastSyncKey = "lastCloudKitSyncDate"

    init() {
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        startMonitoring()
        observeCloudKitSync()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func observeCloudKitSync() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }

            if event.endDate != nil && event.succeeded && event.type == .export {
                let now = Date()
                self?.lastSyncDate = now
                UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            }
        }
    }
}
