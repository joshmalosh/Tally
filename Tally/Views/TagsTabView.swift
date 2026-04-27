import SwiftUI

/// Tags tab — surfaces the same tags & groups management as Settings.
struct TagsTabView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TagsAndGroupsManagementRows()
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags & Groups")
                        Text("Toggle tags to show them as filters on your home screen.")
                            .font(Fonts.caption(13))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
