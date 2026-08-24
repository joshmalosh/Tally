import SwiftUI
import GoogleMobileAds

@Observable
final class AdManager {
    var shouldShowBannerAd = true

    static var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-7313737046490523/5051262373"
        #endif
    }

    func configure(isPro: Bool) {
        shouldShowBannerAd = !isPro
        #if DEBUG
        print("[Tally][Ads] configure isPro=\(isPro) shouldShowBannerAd=\(shouldShowBannerAd)")
        #endif
    }
}
