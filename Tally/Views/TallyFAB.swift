import SwiftUI
import AudioToolbox

struct TallyFAB: View {
    let diameter: CGFloat
    let action: () -> Void

    @State private var isRippling: Bool = false
    // Bumped on every press; drives .sensoryFeedback, which manages the Taptic
    // Engine (preparation + lifecycle) internally for instant, reliable haptics.
    @State private var pressTick: Int = 0

    var body: some View {
        Button {
            action()
            // Ripple runs alongside balloon — no delay on action
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
                    // Glyph only, 20% larger than the prior 0.34 ratio; button size unchanged.
                    .font(.system(size: diameter * 0.408, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(FABButtonStyle(pressTick: $pressTick))
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: pressTick)
    }
}

// MARK: - Button style

private struct FABButtonStyle: ButtonStyle {
    @Binding var pressTick: Int

    func makeBody(configuration: Configuration) -> some View {
        FABButtonBody(configuration: configuration, pressTick: $pressTick)
    }
}

private struct FABButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Binding var pressTick: Int
    @State private var shadowRadius: CGFloat = 14
    @State private var shadowY: CGFloat = 6
    @State private var scale: CGFloat = 1.0

    var body: some View {
        configuration.label
            .shadow(
                color: Color(hex: "2F402E").opacity(0.45),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(scale)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    // Fire the haptic on touch-down for an instant, tactile press.
                    pressTick &+= 1
                    AudioServicesPlaySystemSound(1104)
                    // Compress to 90% — a firm press without a violent warp.
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        scale = 0.90
                        shadowRadius = 6
                        shadowY = 3
                    }
                } else {
                    // Ease back with a soft rubber-stamp settle (a hint of overshoot,
                    // no big balloon) — ease-out-expo feel, damping ~0.7.
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                        scale = 1.0
                        shadowRadius = 14
                        shadowY = 6
                    }
                }
            }
    }
}
