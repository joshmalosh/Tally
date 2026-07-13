import SwiftUI
import UIKit

enum TallyTab {
    case home
    case reports
    case tags
}

struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab
    @Environment(AppState.self) private var appState
    let onFABTap: () -> Void

    private let fabDiameter: CGFloat = 79
    private let barHeight: CGFloat = 44
    private var fabOffset: CGFloat {
        -((fabDiameter / 2) + (barHeight / 2) - barHeight + 6)
    }

    var body: some View {
        ZStack(alignment: .top) {

            // Frosted translucent background so the Home gradient reads through
            // to the bottom edge, rather than being cut off by a solid bar.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "DEDAD2").opacity(0.6))
                        .frame(height: 0.5)
                }

            // Tab items — extend frame into safe area so icons are vertically
            // centred in the full white zone (bar height + safe area inset).
            HStack(alignment: .bottom, spacing: 0) {
                tabItem(tab: .home, icon: "house", filledIcon: "house.fill", label: "Home")
                tabItem(tab: .tags, icon: "tag", filledIcon: "tag.fill", label: "Tags")
                Spacer().frame(maxWidth: .infinity)
                tabItem(tab: .reports, icon: "chart.line.uptrend.xyaxis", filledIcon: "chart.line.uptrend.xyaxis", label: "Reports")
                exportItem
            }
            .frame(height: barHeight + 13)   // +13 ≈ half safe-area, centres icons in visible white zone
            .ignoresSafeArea(edges: .bottom) // allow frame to extend into safe-area region
            .padding(.bottom, 2)

            // FAB
            TallyFAB(diameter: fabDiameter, action: onFABTap)
                .offset(y: fabOffset)
        }
        .frame(height: barHeight)
        .padding(.bottom, -12)
    }

    private func tabItem(tab: TallyTab, icon: String, filledIcon: String, label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selectedTab == tab ? filledIcon : icon)
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

    private var exportItem: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            appState.showingExport = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "8F9E94"))
                Text("Export")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
