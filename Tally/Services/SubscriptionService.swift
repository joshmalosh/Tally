import Foundation
import OSLog
import RevenueCat

enum SubscriptionService {
    /// Refreshes Pro status from RevenueCat and updates the given AppState.
    static func refreshProStatus(appState: AppState) async {
        #if DEBUG
        if RevenueCatConfig.forcePro {
            await MainActor.run { appState.subscriptionStatus = .pro }
            return
        }
        #endif
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let isActive = customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true
            Log.subscription.info("entitlement resolved active=\(isActive, privacy: .public)")
            await MainActor.run {
                appState.subscriptionStatus = isActive ? .pro : .free
            }
        } catch {
            Log.subscription.error("customerInfo fetch failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                appState.subscriptionStatus = .free
            }
        }
    }
}
