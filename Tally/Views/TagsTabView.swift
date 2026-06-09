import SwiftUI

/// Tags tab — surfaces the same tags & groups management as Settings.
/// Note: intentionally has no NavigationStack — TagsTabView is a ZStack
/// overlay inside HomeView's NavigationStack, and a nested NavigationStack
/// creates a UIKit presentation conflict that causes sheets to open and
/// immediately dismiss on first tap.
struct TagsTabView: View {
    var body: some View {
        List {
            Section {
                TagsAndGroupsManagementRows()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 90)
        }
    }
}
