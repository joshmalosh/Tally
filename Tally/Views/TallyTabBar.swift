import SwiftUI

enum TallyTab {
    case home
    case reports
    case tags
}

struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab
    @Environment(AppState.self) private var appState
    let onFABTap: () -> Void

    private let fabDiameter: CGFloat = 99        // 73 × 1.35 ≈ 99
    private let fabOverlapBelowBar: CGFloat = 33  // lower third of 99pt FAB
    private var fabOffset: CGFloat { -(fabDiameter - fabOverlapBelowBar) }

    var body: some View {
        ZStack(alignment: .top) {

            // White background — fills bar + home indicator area fully
            VStack(spacing: 0) {
                Color.white.frame(height: 54)
                Color.white
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: "DEDAD2"))
                    .frame(height: 0.5)
            }

            // Tab items
            HStack(spacing: 0) {
                tabItem(tab: .home, icon: "house", label: "Home")
                tabItem(tab: .reports, icon: "chart.line.uptrend.xyaxis", label: "Reports")
                Spacer().frame(maxWidth: .infinity)
                tabItem(tab: .tags, icon: "tag", label: "Tags")
                moreItem
            }
            .frame(height: 54)

            // FAB
            Button(action: onFABTap) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "2F402E"))
                        .frame(width: fabDiameter, height: fabDiameter)
                        .shadow(color: Color(hex: "2F402E").opacity(0.35), radius: 14, x: 0, y: 6)
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .offset(y: fabOffset)
        }
        .frame(height: 54)
        // Shift the entire bar down — reduces whitespace beneath it
        .padding(.bottom, -16)
    }

    private func tabItem(tab: TallyTab, icon: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? "\(icon).fill" : icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == tab ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
                Text(label)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? Color(hex: "2F402E") : Color(hex: "8F9E94"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var moreItem: some View {
        Button {
            appState.showingSettings = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "8F9E94"))
                Text("More")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
