import AVFoundation
import UIKit

// MARK: - Notification name

extension NSNotification.Name {
    /// Posted immediately when an expense is saved.
    /// userInfo: ["expenseId": String]
    static let expenseLogged = NSNotification.Name("com.tally.expenseLogged")
}

// MARK: - Sound + haptic service

final class ExpenseSoundService {
    static let shared = ExpenseSoundService()

    private var player: AVAudioPlayer?
    /// Stored so UIKit can warm up the Taptic Engine in advance.
    private let haptic = UINotificationFeedbackGenerator()

    private init() {
        // Use .ambient so the sound respects the ringer/mute switch and
        // .mixWithOthers so it doesn't interrupt music or podcasts.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let url = Bundle.main.url(forResource: "Coin_Expense_Logged", withExtension: "mp3") else {
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()

        // Pre-warm the Taptic Engine so the haptic fires with minimal latency.
        haptic.prepare()
    }

    /// Plays the coin drop sound and fires a success haptic.
    func playExpenseLogged() {
        player?.currentTime = 0
        player?.play()
        haptic.notificationOccurred(.success)
        // Re-prepare so the next call is also latency-free.
        haptic.prepare()
    }
}
