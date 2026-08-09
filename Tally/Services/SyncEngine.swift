import Foundation
import Network
import CoreData

/// Monitors network reachability and iCloud sync status.
/// Actual data sync is handled automatically by SwiftData + CloudKit.
@Observable
final class SyncEngine {
    private(set) var isOnline = true
    private(set) var lastSyncDate: Date?
    /// Whether the device is signed into iCloud. Backup only works when it is.
    /// Read from the ubiquity token, which needs no CloudKit entitlement, so it
    /// is accurate even before CloudKit sync is switched on.
    private(set) var isSignedIntoiCloud = FileManager.default.ubiquityIdentityToken != nil

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.tally.network-monitor")

    private static let lastSyncKey = "lastCloudKitSyncDate"

    init() {
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        startMonitoring()
        observeCloudKitSync()
        observeAccountChanges()
    }

    deinit {
        monitor.cancel()
    }

    /// The user can sign in or out of iCloud in the Settings app while Tally is
    /// running; refresh when that happens.
    private func observeAccountChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSignedIntoiCloud = FileManager.default.ubiquityIdentityToken != nil
        }
    }

    /// Re-check on foreground, in case the account changed while backgrounded.
    func refreshAccountStatus() {
        isSignedIntoiCloud = FileManager.default.ubiquityIdentityToken != nil
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
