import SwiftUI
import UIKit
import AudioToolbox

// MARK: - FAB Button View
// Standalone: press animation, haptics, and sound.

struct TallyFAB: View {
    let diameter: CGFloat
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var isRippling: Bool = false
    @State private var pressScale: CGFloat = 1.0
    @State private var shadowRadius: CGFloat = 14
    @State private var shadowY: CGFloat = 6

    var body: some View {
        ZStack {
            // Ripple ring — expands outward on release
            if isRippling {
                Circle()
                    .stroke(Color(hex: "2F402E"), lineWidth: 2.5)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(isRippling ? 1.7 : 1.0)
                    .opacity(isRippling ? 0 : 0.6)
                    .animation(.easeOut(duration: 0.5), value: isRippling)
            }

            // Main FAB circle
            Circle()
                .fill(Color(hex: "2F402E"))
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: Color(hex: "2F402E").opacity(0.45),
                    radius: shadowRadius,
                    x: 0,
                    y: shadowY
                )

            Image(systemName: "plus")
                .font(.system(size: diameter * 0.34, weight: .medium))
                .foregroundStyle(.white)
        }
        .scaleEffect(pressScale)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true

                    // Press down — scale in, shadow collapses
                    withAnimation(.easeIn(duration: 0.08)) {
                        pressScale = 0.84
                        shadowRadius = 4
                        shadowY = 2
                    }

                    // Heavy haptic on press down
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

                    // System sound on press — punchy click
                    AudioServicesPlaySystemSound(1104)
                }
                .onEnded { _ in
                    isPressed = false

                    // Trigger action immediately — simultaneous with animation
                    action()

                    // Ripple
                    isRippling = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        isRippling = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            isRippling = false
                        }
                    }

                    // Spring rebound with exaggerated overshoot
                    withAnimation(
                        .spring(
                            response: 0.38,
                            dampingFraction: 0.35,
                            blendDuration: 0
                        )
                    ) {
                        pressScale = 1.0
                        shadowRadius = 14
                        shadowY = 6
                    }

                    // Light haptic on release
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
        )
    }
}
