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

    private init() {
        guard let url = Bundle.main.url(forResource: "Coin_Expense_Logged", withExtension: "mp3") else {
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    /// Plays the coin drop sound and fires a success haptic.
    func playExpenseLogged() {
        player?.currentTime = 0
        player?.play()
        let haptic = UINotificationFeedbackGenerator()
        haptic.prepare()
        haptic.notificationOccurred(.success)
    }
}
