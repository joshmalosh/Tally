import SwiftUI

/// Tags tab — surfaces the same tags & groups management as Settings.
struct TagsTabView: View {
    var body: some View {
        NavigationStack {
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
    }
}
