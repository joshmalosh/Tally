import Foundation
import RevenueCat

enum SubscriptionService {

    static let proCacheKey = "tally_is_pro_cached"

    /// Call once on cold launch. Reads cached Pro state immediately, then
    /// fetches from RevenueCat and corrects if needed.
    static func restoreSubscriptionStatus(appState: AppState) async {
        // Fast-path: apply cached value immediately so UI renders correctly
        let cached = UserDefaults.standard.bool(forKey: proCacheKey)
        await MainActor.run {
            appState.subscriptionStatus = cached ? .pro : .free
        }

        // Authoritative check from RevenueCat
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let isActive = customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true
            UserDefaults.standard.set(isActive, forKey: proCacheKey)
            await MainActor.run {
                appState.subscriptionStatus = isActive ? .pro : .free
            }
        } catch {
            #if DEBUG
            print("[Tally] SubscriptionService: Failed to fetch customerInfo: \(error)")
            #endif
            // Leave status as cached value — do not downgrade to free on network failure
        }
    }

    /// Call after a successful purchase or restore to immediately update Pro status.
    static func setSubscriptionActive(_ active: Bool, appState: AppState) {
        UserDefaults.standard.set(active, forKey: proCacheKey)
        appState.subscriptionStatus = active ? .pro : .free
    }
}
