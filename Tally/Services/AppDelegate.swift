import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Start immediately so the WKWebView / WebContent process warms up
        // in the background before the user's first tap — eliminates the
        // ~1 s first-interaction freeze caused by on-demand WebView launch.
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = ["47c300b01015cb536fe429152419658d"]
        #endif
        return true
    }
}
