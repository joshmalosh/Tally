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
                    .font(.system(size: diameter * 0.34, weight: .medium))
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
                    withAnimation(.easeIn(duration: 0.08)) {
                        scale = 0.84
                        shadowRadius = 4
                        shadowY = 2
                    }
                } else {
                    // Phase 1: inflate (balloon puffs up)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.35)) {
                        scale = 1.18
                        shadowRadius = 14
                        shadowY = 6
                    }
                    // Phase 2: pop (balloon snaps back to rest)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            scale = 1.0
                        }
                    }
                }
            }
    }
}
