import UIKit

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Installs a single window-wide tap recogniser that dismisses the keyboard when
/// the user taps anywhere — empty space or another button — mirroring the way a
/// tap outside a field closes the keyboard in native iOS apps. It does NOT fire
/// when the tap lands on a text field itself, so tapping a field still opens (or
/// switches) the keyboard. `cancelsTouchesInView = false` lets the underlying
/// button/row still receive the tap.
final class KeyboardDismissGesture: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGesture()

    func install() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }
        if window.gestureRecognizers?.contains(where: { $0.name == "kbDismiss" }) == true { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.name = "kbDismiss"
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        UIApplication.shared.endEditing()
    }

    // Fire alongside buttons, rows, scroll views — never swallow their taps.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // Don't dismiss when the tap is on a text input (or any subview of one) — let
    // it take focus, and let the field's own double-tap-to-select work. Checking
    // only `touch.view` missed multi-line fields, whose taps land on an inner
    // subview of the UITextView, so the dismiss fired mid-double-tap.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView { return false }
            view = v.superview
        }
        return true
    }
}
