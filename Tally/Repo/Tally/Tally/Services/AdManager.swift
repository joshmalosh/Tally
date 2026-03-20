import SwiftUI
import GoogleMobileAds

@Observable
final class AdManager {
    var shouldShowBannerAd = true

    static let bannerAdUnitID = "ca-app-pub-7313737046490523/5051262373"

    func configure(isPro: Bool) {
        shouldShowBannerAd = !isPro
    }
}
