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

    var body: some View {
        ZStack(alignment: .top) {

            // MARK: White background — extends through home indicator to screen bottom
            VStack(spacing: 0) {
                Color.white
                    .frame(height: 60)
                Color.white
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: "DEDAD2"))
                    .frame(height: 0.5)
            }

            // MARK: Tab items — sit within the 60pt bar height
            HStack(spacing: 0) {
                tabItem(tab: .home, icon: "house", label: "Home")
                tabItem(tab: .reports, icon: "chart.line.uptrend.xyaxis", label: "Reports")
                Spacer().frame(maxWidth: .infinity) // centre space reserved for FAB
                tabItem(tab: .tags, icon: "tag", label: "Tags")
                moreItem
            }
            .frame(height: 60)

            // MARK: FAB — centred, sitting above the bar
            Button(action: onFABTap) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "2F402E"))
                        .frame(width: 73, height: 73)
                        .shadow(color: Color(hex: "2F402E").opacity(0.35), radius: 12, x: 0, y: 6)
                    Image(systemName: "plus")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .offset(y: -24)
        }
        .frame(height: 60)
    }

    // MARK: Regular tab item
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

    // MARK: More item — opens Settings
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
