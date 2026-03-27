import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            GADMobileAds.sharedInstance().start(completionHandler: nil)
            #if DEBUG
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = ["47c300b01015cb536fe429152419658d"]
            #endif
        }
        return true
    }
}
