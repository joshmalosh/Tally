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

    // Loaded asynchronously so the animated boot splash renders and runs *during*
    // the real store/CloudKit setup, instead of the OS showing a static launch
    // image while a synchronous init blocks the first frame.
    @State private var modelContainer: ModelContainer?

    // iCloud + Push Notifications + Background Modes capabilities are configured
    // on the Tally target, so CloudKit sync is on. Expenses and receipt images
    // (stored on the expense via .externalStorage) back up to the user's private
    // iCloud automatically.
    static let cloudKitEnabled = true

    init() {
        // Fast, non-blocking. The store opens later, off the main thread.
        Self.configureRevenueCat()
    }

    private static func configureRevenueCat() {
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .error
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let modelContainer {
                    ContentView()
                        .environment(appState)
                        .environment(syncEngine)
                        .environment(adManager)
                        .modelContainer(modelContainer)
                        .transition(.opacity)
                } else {
                    BootSplashView()
                        .transition(.opacity)
                        .task { await loadContainerIfNeeded() }
                }
            }
            .animation(.easeOut(duration: 0.3), value: modelContainer == nil)
        }
    }

    @MainActor
    private func loadContainerIfNeeded() async {
        guard modelContainer == nil else { return }
        modelContainer = await Self.makeContainer()
    }

    /// Builds the SwiftData container off the main thread so the splash keeps
    /// animating while the store opens. `ModelContainer` is `Sendable` and may be
    /// created on any thread.
    private static func makeContainer() async -> ModelContainer {
        await Task.detached(priority: .userInitiated) {
            let schema = Schema([
                ExpenseModel.self,
                TagModel.self,
                ReportModel.self,
            ])
            do {
                let config: ModelConfiguration
                if cloudKitEnabled {
                    config = ModelConfiguration(
                        schema: schema,
                        cloudKitDatabase: .private("iCloud.com.asimplelife.tally")
                    )
                } else {
                    config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                }
                let container = try ModelContainer(for: schema, configurations: [config])
                Log.data.info("ModelContainer created (CloudKit: \(cloudKitEnabled, privacy: .public))")
                return container
            } catch {
                Log.data.critical("ModelContainer creation failed: \(error.localizedDescription, privacy: .public)")
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }.value
    }
}
