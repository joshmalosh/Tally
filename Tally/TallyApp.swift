import SwiftUI
import OSLog
import SwiftData
import UIKit
import RevenueCat

@main
struct TallyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var syncEngine = SyncEngine()
    @State private var adManager = AdManager()

    let modelContainer: ModelContainer

    // iCloud + Push Notifications + Background Modes capabilities are configured
    // on the Tally target, so CloudKit sync is on. Expenses and receipt images
    // (stored on the expense via .externalStorage) back up to the user's private
    // iCloud automatically.
    static let cloudKitEnabled = true

    init() {
        let schema = Schema([
            ExpenseModel.self,
            TagModel.self,
        ])
        do {
            let config: ModelConfiguration
            if Self.cloudKitEnabled {
                config = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.asimplelife.tally")
                )
            } else {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            }
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Log.data.critical("ModelContainer creation failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
        configureRevenueCat()
        Log.data.info("ModelContainer created (CloudKit: \(Self.cloudKitEnabled, privacy: .public))")
    }

    private func configureRevenueCat() {
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .error
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
