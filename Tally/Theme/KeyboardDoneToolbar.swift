import SwiftUI
import UIKit

struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.endEditing()
                    }
                    .foregroundStyle(Color(hex: "346049"))
                    .fontWeight(.medium)
                }
            }
    }
}

extension View {
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbar())
    }
}
