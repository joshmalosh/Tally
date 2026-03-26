import Foundation
import RevenueCat

enum SubscriptionService {
    /// Refreshes Pro status from RevenueCat and updates the given AppState.
    static func refreshProStatus(appState: AppState) async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let isActive = customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true
            await MainActor.run {
                appState.subscriptionStatus = isActive ? .pro : .free
            }
        } catch {
            #if DEBUG
            print("[Tally] SubscriptionService: Failed to fetch customerInfo: \(error)")
            #endif
            await MainActor.run {
                appState.subscriptionStatus = .free
            }
        }
    }
}
