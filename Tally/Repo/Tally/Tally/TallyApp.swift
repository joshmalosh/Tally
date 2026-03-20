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

    init() {
        let schema = Schema([ExpenseModel.self, TagModel.self])

        func makeContainer(deleteFirst: Bool = false) -> ModelContainer {
            if deleteFirst {
                let urls = [
                    URL.applicationSupportDirectory.appending(path: "default.store"),
                    URL.applicationSupportDirectory.appending(path: "default.store-shm"),
                    URL.applicationSupportDirectory.appending(path: "default.store-wal"),
                ]
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
                print("[Tally] Deleted old database to resolve schema mismatch.")
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
                    print("[Tally] ModelContainer failed: \(error). Recreating store...")
                    return makeContainer(deleteFirst: true)
                }
                fatalError("[Tally] Could not create ModelContainer: \(error)")
            }
        }

        self.modelContainer = makeContainer()
        print("[Tally] ModelContainer created successfully (CloudKit: \(Self.cloudKitEnabled))")
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
