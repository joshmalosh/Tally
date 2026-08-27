import SwiftUI

/// Tags tab — surfaces the same tags & groups management as Settings.
/// Note: intentionally has no NavigationStack — TagsTabView is a ZStack
/// overlay inside HomeView's NavigationStack, and a nested NavigationStack
/// creates a UIKit presentation conflict that causes sheets to open and
/// immediately dismiss on first tap.
struct TagsTabView: View {
    // The tag/group sheet is presented here, on the stable List container, not
    // from inside a recycling row — that was what made a tapped tag open and then
    // immediately dismiss on the first tap (working only on the second).
    @State private var activeSheet: TagSheet?

    var body: some View {
        List {
            Section {
                TagsAndGroupsManagementRows(activeSheet: $activeSheet)
            }
        }
        .listSectionSpacing(0)
        // Pull the header up to the top like the Reports page (the List's default
        // top inset is what made the Tags heading start too low).
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 90)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newTag:
                TagCreationView(suppressNameFieldAutofocus: true)
            case .newGroup:
                TagCreationView(isGroupMode: true, suppressNameFieldAutofocus: true)
            case .edit(let tag):
                TagCreationView(editingTag: tag, suppressNameFieldAutofocus: true)
            case .groupDetail(let group):
                // GroupDetailView needs its own NavigationStack because it uses
                // .navigationTitle and toolbar items (push-nav semantics via sheet).
                NavigationStack {
                    GroupDetailView(group: group)
                }
            }
        }
    }
}
