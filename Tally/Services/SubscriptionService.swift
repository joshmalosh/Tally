import Foundation
import StoreKit

/// StoreKit subscription checks and `UserDefaults` cache for instant Pro UI on cold launch.
enum SubscriptionService {
    static let proProductId = "com.tally.pro.monthly"
    static let proCacheKey = "tally_is_pro_cached"

    /// Persists Pro to `UserDefaults` whenever subscription state is set from StoreKit or purchase flows.
    @MainActor
    static func setSubscriptionActive(_ active: Bool, appState: AppState) {
        appState.subscriptionStatus = active ? .pro : .free
        UserDefaults.standard.set(active, forKey: proCacheKey)
    }

    /// Syncs with App Store and updates `appState` + cache. On `AppStore.sync()` failure, leaves current state unchanged.
    @MainActor
    static func restoreSubscriptionStatus(appState: AppState) async {
        do {
            try await AppStore.sync()
        } catch {
            return
        }

        var isPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == proProductId {
                isPro = true
                break
            }
        }

        if isPro {
            appState.subscriptionStatus = .pro
            UserDefaults.standard.set(true, forKey: proCacheKey)
        } else {
            appState.subscriptionStatus = .free
            UserDefaults.standard.set(false, forKey: proCacheKey)
        }
    }
}
