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
                    withAnimation(.easeIn(duration: 0.08)) {
                        scale = 0.84
                        shadowRadius = 4
                        shadowY = 2
                    }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    AudioServicesPlaySystemSound(1104)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
    }
}
