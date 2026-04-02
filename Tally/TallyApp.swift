import SwiftUI
import SwiftData
import UIKit
import RevenueCat

@main
struct TallyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @StateObject private var invoicingState = InvoicingState()
    @State private var syncEngine = SyncEngine()
    @State private var adManager = AdManager()

    let modelContainer: ModelContainer

    // Flip to true once enrolled in Apple Developer Program and
    // entitlements are configured for iCloud + Push Notifications.
    static let cloudKitEnabled = false

    init() {
        let schema = Schema([
            ExpenseModel.self,
            TagModel.self,
            Company.self,
            Client.self,
            Product.self,
            Invoice.self,
            LineItem.self,
            InvoiceFee.self,
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
            fatalError("Failed to create ModelContainer: \(error)")
        }
        configureRevenueCat()
        #if DEBUG
        print("[Tally] ModelContainer created successfully (CloudKit: \(Self.cloudKitEnabled))")
        #endif
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
                .environmentObject(invoicingState)
                .environment(syncEngine)
                .environment(adManager)
        }
        .modelContainer(modelContainer)
    }
}
