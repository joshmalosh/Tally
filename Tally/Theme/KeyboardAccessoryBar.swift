import SwiftUI
import UIKit

// MARK: - Accessory toolbar

final class KeyboardAccessoryBar: UIToolbar {
    init(target: Any?, action: Selector) {
        super.init(frame: .zero)
        barStyle = .default
        isTranslucent = true
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .plain, target: target, action: action)
        done.setTitleTextAttributes([
            .foregroundColor: UIColor(red: 0x34 / 255, green: 0x60 / 255, blue: 0x49 / 255, alpha: 1),
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
        ], for: .normal)
        items = [spacer, done]
        sizeToFit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Numeric field + Done (inputAccessoryView)

struct NumericFieldWithDone: UIViewRepresentable {
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad
    var font: UIFont = UIFont.monospacedSystemFont(ofSize: 52, weight: .regular)
    var textAlignment: NSTextAlignment = .natural
    /// When true, keeps the UIKit field as first responder; sync with SwiftUI focus for amount fields.
    var isFirstResponder: Bool = false
    var onDone: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = keyboardType
        tf.font = font
        tf.textAlignment = textAlignment
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.tintColor = UIColor(red: 0x34 / 255, green: 0x60 / 255, blue: 0x49 / 255, alpha: 1)
        tf.textColor = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        context.coordinator.textField = tf
        tf.inputAccessoryView = KeyboardAccessoryBar(target: context.coordinator, action: #selector(Coordinator.doneTapped))
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onDone = onDone
        if uiView.font != font {
            uiView.font = font
        }
        uiView.keyboardType = keyboardType
        uiView.textAlignment = textAlignment
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = text.isEmpty
            ? UIColor(red: 0x8F / 255, green: 0x9E / 255, blue: 0x94 / 255, alpha: 1)
            : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)

        if isFirstResponder {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject {
        @Binding var text: String
        var onDone: (() -> Void)?
        weak var textField: UITextField?

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ tf: UITextField) {
            text = tf.text ?? ""
        }

        @objc func doneTapped() {
            textField?.resignFirstResponder()
            onDone?()
        }
    }
}
