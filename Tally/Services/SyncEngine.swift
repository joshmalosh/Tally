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

    /// CloudKit sync events fire in bursts; handle them off the main thread so a
    /// mid-scroll import can't do work on the main queue. Serial (one at a time)
    /// so the throttle timestamp below needs no extra locking.
    private let cloudKitQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.tally.cloudkit-events"
        q.qualityOfService = .utility
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Last export event we surfaced to `lastSyncDate`. Touched only on
    /// `cloudKitQueue` (serial), so it needs no synchronisation; ignored by the
    /// observation system since it never drives the UI.
    @ObservationIgnored private var lastExportEventAt: Date?

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
            queue: cloudKitQueue
        ) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }

            // Only completed events carry a result. A failed sync is the quiet
            // data-loss path, so log it at error level (no user data included).
            guard event.endDate != nil else { return }
            if let error = event.error {
                Log.sync.error("cloudkit \(event.type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard event.succeeded, event.type == .export else { return }

            #if DEBUG
            Log.sync.info("cloudkit export ok")
            #endif

            // Throttle the @Observable write: a burst of export events would
            // otherwise invalidate the UI on the main thread once per event,
            // mid-scroll. At most one refresh per minute.
            let now = Date()
            if let last = self.lastExportEventAt, now.timeIntervalSince(last) < 60 { return }
            self.lastExportEventAt = now
            DispatchQueue.main.async {
                self.lastSyncDate = now
                UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            }
        }
    }
}
