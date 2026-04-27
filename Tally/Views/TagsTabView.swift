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
            .navigationTitle("Tags & Groups")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(Color(hex: "F6F5F3"))
        }
        .background(Color(hex: "F6F5F3").ignoresSafeArea())
    }
}
