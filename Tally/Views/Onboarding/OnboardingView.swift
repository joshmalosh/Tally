import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @Environment(AppState.self) private var appState
    @State private var currentPage = 0
    @State private var showingCurrencySetup = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "bolt.fill",
            title: "Track expenses in seconds",
            subtitle: "Snap a receipt, upload a file, or type it in. Your expenses are saved instantly.",
            accentColor: .brandPrimary
        ),
        OnboardingPage(
            icon: "square.and.arrow.up.fill",
            title: "Export anytime",
            subtitle: "Clean CSV and PDF exports. Always ready when you need them.",
            accentColor: .brandSecondary
        ),
        OnboardingPage(
            icon: "icloud.fill",
            title: "Securely stored in your iCloud",
            subtitle: "Your expenses stay on your device and in your iCloud. Private by default.",
            accentColor: .success
        ),
    ]

    var body: some View {
        if showingCurrencySetup {
            CurrencySetupView {
                hasCompleted = true
            }
        } else {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                bottomSection
            }
            .background(Color.bgPrimary)
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(page.accentColor)
                .frame(height: 80)

            VStack(spacing: Spacing.md) {
                Text(page.title)
                    .font(Fonts.brand(24))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(Fonts.body(16))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
    }

    private var bottomSection: some View {
        VStack(spacing: Spacing.md) {
            pageIndicator

            if currentPage == pages.count - 1 {
                PrimaryButton(title: "Get started") {
                    // No withAnimation: avoids a long layout transaction where currency rows ignore taps.
                    showingCurrencySetup = true
                }
            } else {
                PrimaryButton(title: "Next") {
                    withAnimation { currentPage += 1 }
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
    }

    private var pageIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.brandPrimary : Color.borderColor)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .padding(.bottom, Spacing.sm)
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}
