import Foundation
import OSLog
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
            let signedIn = FileManager.default.ubiquityIdentityToken != nil
            self?.isSignedIntoiCloud = signedIn
            Log.sync.info("iCloud account changed, signedIn=\(signedIn, privacy: .public)")
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

            // Only completed events carry a result. A failed sync is the quiet
            // data-loss path, so log it at error level (no user data included).
            guard event.endDate != nil else { return }
            if let error = event.error {
                Log.sync.error("cloudkit \(event.type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            } else if event.succeeded {
                Log.sync.info("cloudkit \(event.type.rawValue, privacy: .public) ok")
                if event.type == .export {
                    let now = Date()
                    self?.lastSyncDate = now
                    UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
                }
            }
        }
    }
}
