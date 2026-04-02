import SwiftUI
import UIKit

// MARK: - Accessory toolbar

final class KeyboardAccessoryBar: UIToolbar {
    init(target: Any?, action: Selector) {
        super.init(frame: .zero)
        barStyle = .default
        isTranslucent = false
        barTintColor = .white
        backgroundColor = .white
        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        standardAppearance = appearance
        scrollEdgeAppearance = appearance
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .plain, target: target, action: action)
        done.tintColor = UIColor(red: 0.184, green: 0.251, blue: 0.180, alpha: 1.0)
        done.setTitleTextAttributes(
            [
                .foregroundColor: UIColor(red: 0.184, green: 0.251, blue: 0.180, alpha: 1.0),
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            ],
            for: .normal
        )
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
    /// When true, requests the UITextField become first responder synchronously in `updateUIView` (paired with `hasFocused` in the coordinator).
    var focusRequested: Bool = false
    /// When true, field text is invisible so a SwiftUI `Text` overlay can supply styling (Add Expense hero).
    var hidesFieldText: Bool = false
    var onBeginEditing: (() -> Void)? = nil
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
        tf.textColor = hidesFieldText
            ? .clear
            : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        context.coordinator.textField = tf
        tf.inputAccessoryView = KeyboardAccessoryBar(target: context.coordinator, action: #selector(Coordinator.doneTapped))
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onDone = onDone
        if uiView.font != font {
            uiView.font = font
        }
        uiView.keyboardType = keyboardType
        uiView.textAlignment = textAlignment
        if uiView.text != text {
            uiView.text = text
        }
        if hidesFieldText {
            uiView.textColor = .clear
        } else {
            uiView.textColor = text.isEmpty
                ? UIColor(red: 0x8F / 255, green: 0x9E / 255, blue: 0x94 / 255, alpha: 1)
                : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        }

        if focusRequested && !uiView.isFirstResponder && !context.coordinator.hasFocused {
            context.coordinator.hasFocused = true
            DispatchQueue.main.async {
                guard !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        }
        if !focusRequested {
            context.coordinator.hasFocused = false
        }
    }

    final class Coordinator: NSObject {
        @Binding var text: String
        var hasFocused: Bool = false
        var onBeginEditing: (() -> Void)?
        var onDone: (() -> Void)?
        weak var textField: UITextField?

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ tf: UITextField) {
            text = tf.text ?? ""
        }

        @objc func editingDidBegin() {
            onBeginEditing?()
        }

        @objc func doneTapped() {
            textField?.resignFirstResponder()
            onDone?()
        }
    }
}
