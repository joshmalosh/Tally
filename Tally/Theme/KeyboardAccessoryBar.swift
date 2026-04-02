import SwiftUI
import UIKit

// MARK: - Accessory bar (plain UIView — avoids UIToolbar extra grey strip above Done)

/// Full-width accessory above the keyboard with a trailing Done control.
/// Uses `UIView` instead of `UIToolbar` so iOS does not draw the extra neutral/grey layer
/// that commonly appears above `UIToolbar` when used as `inputAccessoryView`.
final class KeyboardAccessoryBar: UIView {
    private let doneGreen = UIColor(red: 0.184, green: 0.251, blue: 0.180, alpha: 1.0)
    private let barHeight: CGFloat = 44

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: barHeight)
    }

    init(target: Any?, action: Selector) {
        super.init(frame: .zero)
        commonInit(target: target, action: action)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func commonInit(target: Any?, action: Selector) {
        backgroundColor = .white
        isOpaque = true

        let button = UIButton(type: .system)
        button.setTitle("Done", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(doneGreen, for: .normal)
        button.tintColor = doneGreen
        button.addTarget(target, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// iOS often wraps `inputAccessoryView` in a taller container with a default grey top; painting
    /// the host chain removes the neutral strip above the Done row (Add Expense amount field).
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        paintKeyboardAccessoryHostBackgroundsWhite()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundColor = .white
        paintKeyboardAccessoryHostBackgroundsWhite()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil {
            DispatchQueue.main.async { [weak self] in
                self?.paintKeyboardAccessoryHostBackgroundsWhite()
            }
        }
    }

    private func paintKeyboardAccessoryHostBackgroundsWhite() {
        var view: UIView? = superview
        for _ in 0 ..< 5 {
            guard let v = view else { break }
            v.backgroundColor = .white
            v.isOpaque = true
            view = v.superview
        }
    }
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
        Self.configureNumberPadKeyboardChrome(tf)
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
        Self.configureNumberPadKeyboardChrome(uiView)
        if let accessory = uiView.inputAccessoryView {
            accessory.setNeedsLayout()
            accessory.layoutIfNeeded()
        }
    }

    /// Hides the system shortcuts/assistant strip that can render as an empty grey bar above the
    /// numeric keyboard (separate from our `inputAccessoryView` Done row).
    private static func configureNumberPadKeyboardChrome(_ tf: UITextField) {
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.inputAssistantItem.leadingBarButtonGroups = []
        tf.inputAssistantItem.trailingBarButtonGroups = []
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
