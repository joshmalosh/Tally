import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var syncEngine = SyncEngine()
    @State private var adManager = AdManager()

    let modelContainer: ModelContainer

    // Flip to true once enrolled in Apple Developer Program and
    // entitlements are configured for iCloud + Push Notifications.
    static let cloudKitEnabled = false

    /// Bump when the SwiftData schema changes in dev; wipes the local store once so no migration is required.
    private static let storeSchemaVersionKey = "tallySwiftDataStoreSchemaVersion"
    private static let currentStoreSchemaVersion = 2

    private static func deletePersistentStoreFiles() {
        let urls = [
            URL.applicationSupportDirectory.appending(path: "default.store"),
            URL.applicationSupportDirectory.appending(path: "default.store-shm"),
            URL.applicationSupportDirectory.appending(path: "default.store-wal"),
        ]
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    init() {
        let schema = Schema([ExpenseModel.self, TagModel.self])

        if UserDefaults.standard.integer(forKey: Self.storeSchemaVersionKey) < Self.currentStoreSchemaVersion {
            Self.deletePersistentStoreFiles()
            UserDefaults.standard.set(Self.currentStoreSchemaVersion, forKey: Self.storeSchemaVersionKey)
            #if DEBUG
            print("[Tally] SwiftData store recreated for schema version \(Self.currentStoreSchemaVersion).")
            #endif
        }

        func makeContainer(deleteFirst: Bool = false) -> ModelContainer {
            if deleteFirst {
                Self.deletePersistentStoreFiles()
                #if DEBUG
                print("[Tally] Deleted old database to resolve schema mismatch.")
                #endif
            }

            do {
                let config: ModelConfiguration
                if Self.cloudKitEnabled {
                    config = ModelConfiguration(
                        schema: schema,
                        cloudKitDatabase: .private("iCloud.com.tally.app")
                    )
                } else {
                    config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                }
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                if !deleteFirst {
                    #if DEBUG
                    print("[Tally] ModelContainer failed: \(error). Recreating store...")
                    #endif
                    return makeContainer(deleteFirst: true)
                }
                fatalError("[Tally] Could not create ModelContainer: \(error)")
            }
        }

        self.modelContainer = makeContainer()
        #if DEBUG
        print("[Tally] ModelContainer created successfully (CloudKit: \(Self.cloudKitEnabled))")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(syncEngine)
                .environment(adManager)
        }
        .modelContainer(modelContainer)
    }
}
