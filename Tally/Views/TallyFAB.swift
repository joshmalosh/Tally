import SwiftUI
import UIKit
import AudioToolbox

struct TallyFAB: View {
    let diameter: CGFloat
    let action: () -> Void

    @State private var isRippling: Bool = false

    var body: some View {
        Button {
            action()
            isRippling = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                isRippling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    isRippling = false
                }
            }
        } label: {
            ZStack {
                if isRippling {
                    Circle()
                        .stroke(Color(hex: "2F402E"), lineWidth: 2.5)
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(isRippling ? 1.7 : 1.0)
                        .opacity(isRippling ? 0 : 0.6)
                        .animation(.easeOut(duration: 0.5), value: isRippling)
                }

                Circle()
                    .fill(Color(hex: "2F402E"))
                    .frame(width: diameter, height: diameter)

                Image(systemName: "plus")
                    .font(.system(size: diameter * 0.34, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(FABButtonStyle())
    }
}

// MARK: - Button style

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FABButtonBody(configuration: configuration)
    }
}

private struct FABButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var shadowRadius: CGFloat = 14
    @State private var shadowY: CGFloat = 6

    var body: some View {
        configuration.label
            .shadow(
                color: Color(hex: "2F402E").opacity(0.45),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(configuration.isPressed ? 0.84 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.38, dampingFraction: 0.35),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(pressed ? .easeIn(duration: 0.08) : .spring(response: 0.38, dampingFraction: 0.35)) {
                    shadowRadius = pressed ? 4 : 14
                    shadowY = pressed ? 2 : 6
                }
                if pressed {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    AudioServicesPlaySystemSound(1104)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
    }
}
