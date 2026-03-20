import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingSubscription = false
    @State private var showingProFeature = false
    @State private var showingCurrencyPicker = false
    @State private var showingTagCreation = false
    @State private var showingGroupCreation = false
    @State private var editingTag: TagModel?
    @State private var editingGroup: TagModel?
    @State private var expandedGroups: Set<String> = []

    private var topLevelTags: [TagModel] {
        tags.filter { $0.parentId == nil }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Subscription") {
                    if appState.isPro {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Pro")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("Active")
                                .font(Fonts.caption(13))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.success)
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Image(systemName: "star.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Go Pro")
                                        .foregroundStyle(Color.brandPrimary)
                                    Text("Unlimited exports, PDF, OCR, no ads")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Text("$4.99/mo")
                                    .font(Fonts.caption(13))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }

                Section("Preferences") {
                    Button { showingCurrencyPicker = true } label: {
                        HStack {
                            Image(systemName: "coloncurrencysign.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Default currency")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(CurrencyFormatter.shared.symbol(for: appState.defaultCurrency)) \(appState.defaultCurrency)")
                                .font(Fonts.caption(14))
                                .foregroundStyle(Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }

                Section {
                    ForEach(topLevelTags) { tag in
                        Toggle(isOn: Binding(
                            get: { tag.showOnHome },
                            set: { tag.showOnHome = $0 }
                        )) {
                            HStack(spacing: Spacing.smd) {
                                if tag.isGroup {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(tag.tagColor.primaryColor)
                                } else {
                                    Circle()
                                        .fill(tag.tagColor.primaryColor)
                                        .frame(width: 12, height: 12)
                                }
                                Text(tag.name)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .tint(Color.brandPrimary)
                    }
                } header: {
                    Text("Home Screen Tags")
                } footer: {
                    Text("Choose which tags and groups appear as filters on the home screen.")
                }

                Section("Tags & Groups") {
                    ForEach(topLevelTags) { tag in
                        if tag.isGroup {
                            groupRow(tag)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { deleteTag(tag) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editingGroup = tag } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color.brandPrimary)
                                }
                            if expandedGroups.contains(tag.id) {
                                ForEach(childrenOf(tag)) { child in
                                    childTagRow(child)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) { deleteTag(child) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        } else {
                            tagRow(tag)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { deleteTag(tag) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    Button {
                        showingTagCreation = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Add tag")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }

                    Button {
                        showingGroupCreation = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Add group")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }

                Section("Data") {
                    Button {
                        appState.showingExport = true
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.brandPrimary)
                            Text("Export your expenses")
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }

                Section("Pro Features") {
                    ocrRow
                }

                Section("iCloud") {
                    HStack {
                        Image(systemName: appState.isOffline ? "wifi.slash" : "checkmark.icloud")
                            .foregroundStyle(appState.isOffline ? Color.danger : Color.success)

                        if appState.isOffline {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud unavailable")
                                    .foregroundStyle(Color.textPrimary)
                                Text("Data saved locally")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textMuted)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud Sync")
                                    .foregroundStyle(Color.textPrimary)
                                if let lastSync = syncEngine.lastSyncDate {
                                    Text("Last backup \(lastSync, format: .relative(presentation: .named))")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                } else {
                                    Text("Waiting for first sync...")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        Spacer()
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Color.textMuted)
                    }

                    if let privacyURL = URL(string: "https://tally.app/privacy") {
                        Link(destination: privacyURL) {
                            HStack {
                                Text("Privacy Policy")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }

                    if let termsURL = URL(string: "https://tally.app/terms") {
                        Link(destination: termsURL) {
                            HStack {
                                Text("Terms of Service")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerSheet(selectedCode: Binding(
                    get: { appState.defaultCurrency },
                    set: { appState.defaultCurrency = $0 }
                ))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .sheet(isPresented: $showingTagCreation) {
                TagCreationView()
            }
            .sheet(isPresented: $showingGroupCreation) {
                TagCreationView(isGroupMode: true)
            }
            .sheet(item: $editingTag) { tag in
                TagCreationView(editingTag: tag)
            }
            .sheet(item: $editingGroup) { group in
                TagCreationView(editingTag: group, isGroupMode: true)
            }
            .sheet(isPresented: $showingProFeature) {
                ProFeatureSheet(featureName: "Receipt auto-fill (OCR)")
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var ocrRow: some View {
        if appState.isPro {
            Toggle(isOn: Binding(
                get: { appState.ocrEnabled },
                set: { appState.ocrEnabled = $0 }
            )) {
                HStack {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brandPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receipt auto-fill (OCR)")
                            .foregroundStyle(Color.textPrimary)
                        Text("Extract amount and merchant from receipts")
                            .font(Fonts.caption(12))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .tint(Color.brandPrimary)
        } else {
            Button {
                showingProFeature = true
            } label: {
                HStack {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receipt auto-fill (OCR)")
                            .foregroundStyle(Color.textMuted)
                        Text("Extract amount and merchant from receipts")
                            .font(Fonts.caption(12))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    private func groupRow(_ group: TagModel) -> some View {
        let isExpanded = expandedGroups.contains(group.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedGroups.remove(group.id)
                } else {
                    expandedGroups.insert(group.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.smd) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(group.tagColor.primaryColor)
                Text(group.name)
                    .font(Fonts.label(15))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(childrenOf(group).count)")
                    .font(Fonts.caption(13))
                    .foregroundStyle(Color.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
        }
    }

    private func childTagRow(_ tag: TagModel) -> some View {
        Button {
            editingTag = tag
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 10, height: 10)
                Text(tag.name)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.leading, Spacing.lg)
        }
    }

    private func tagRow(_ tag: TagModel) -> some View {
        Button {
            editingTag = tag
        } label: {
            HStack(spacing: Spacing.smd) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 12, height: 12)
                Text(tag.name)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func deleteTag(_ tag: TagModel) {
        if appState.selectedTagFilter == tag.id {
            appState.selectedTagFilter = nil
            appState.isGroupFilter = false
        }

        if tag.isGroup {
            for child in childrenOf(tag) {
                if appState.selectedTagFilter == child.id {
                    appState.selectedTagFilter = nil
                    appState.isGroupFilter = false
                }
                child.parentId = nil
            }
        }
        modelContext.delete(tag)
        do {
            try modelContext.save()
        } catch {
            print("[Tally] ERROR deleting tag: \(error)")
        }
    }
}
